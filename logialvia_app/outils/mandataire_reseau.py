#!/usr/bin/env python3
"""Mandataire de TEST du réseau réel (docs/logialvia/47r_MYSQL_ET_RESEAU_REEL.md).

Un mandataire inverse minuscule, devant le VRAI serveur Laravel, qui reproduit les
pièges d'un hébergement mutualisé : TLS (certificat auto-signé, autorité maison, expiré,
mauvais nom), 413 (`LimitRequestBody`), coupures en plein lot, lenteurs, 502/503/504,
429 + `Retry-After`, redirection http -> https, page HTML d'hébergeur, en-tête
`Authorization` retiré.

Uniquement la bibliothèque standard + la commande `openssl`. Aucun secret : les
certificats sont jetables (dossier de travail), la vérification TLS du poste n'est JAMAIS
désactivée : c'est précisément ce que l'essai prouve.

    python3 mandataire_reseau.py --amont http://127.0.0.1:8765 --port 8780 --controle 8781
    python3 mandataire_reseau.py ... --tls /tmp/lv/certs --certificat autosigne|valide|expire|mauvais_nom

Commande (HTTP clair, port --controle) :
    PUT    /regles    corps JSON : liste de règles (remplace les règles et vide le journal)
    DELETE /regles    supprime les règles
    GET    /journal   requêtes vues : [{n, methode, chemin, octets, action, statut}]
    GET    /sante

Règle : {"chemin": "/api/sync/push", "methode": "POST", "fois": 1, "action": "...", ...}
  `fois` : nombre d'applications (défaut 1 ; -1 = toujours). Les règles s'essaient dans l'ordre ;
  la première qui correspond ET qui reste applicable gagne ; sinon la requête passe telle quelle.
Actions :
  statut               {statut, corps?, type?, entetes?}   répond sans joindre le serveur
  html                 {statut?}                            page HTML d'hébergeur (200 par défaut)
  retard               {ms}                                 attend, puis laisse passer
  retard_reponse       {ms}                                 sert la requête (le serveur AGIT), puis attend avant de répondre
  coupe_requete        {octets}                             ferme après N octets du corps, rien n'atteint le serveur
  coupe_avant_reponse  {}                                   le serveur traite TOUT, la connexion est fermée sans réponse
  coupe_reponse        {octets}                             renvoie N octets de la réponse puis ferme
  sans_authorization   {aussi_x?}                           retire l'en-tête Authorization (Apache/CGI) ; aussi_x : X-Authorization aussi
  limite_corps         {octets}                             413 HTML si le corps dépasse (LimitRequestBody)
  redirige             {statut?, location}                  301/302/307/308
"""

import argparse
import http.client
import json
import os
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PAGE_HEBERGEUR = (
    "<!DOCTYPE html><html><head><title>Maintenance</title></head>"
    "<body><h1>Site en maintenance</h1><p>Revenez dans quelques minutes.</p></body></html>"
)
PAGE_413 = (
    "<!DOCTYPE html><html><head><title>413 Request Entity Too Large</title></head>"
    "<body><h1>Request Entity Too Large</h1>"
    "<p>The requested resource does not allow request data with POST requests, "
    "or the amount of data provided in the request exceeds the capacity limit.</p></body></html>"
)

verrou = threading.Lock()
etat = {"regles": [], "journal": [], "n": 0, "amont": None}


def prendre_regle(chemin, methode):
    with verrou:
        for r in etat["regles"]:
            if r.get("chemin") and r["chemin"] not in chemin:
                continue
            if r.get("methode") and r["methode"].upper() != methode:
                continue
            reste = r.get("reste", r.get("fois", 1))
            if reste == 0:
                continue
            if reste > 0:
                r["reste"] = reste - 1
            return dict(r)
    return None


def noter(entree):
    with verrou:
        etat["journal"].append(entree)


class Mandataire(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"  # une requete par connexion : coupures nettes

    def log_message(self, *a):
        pass

    # --------------------------------------------------------------- utilitaires
    def _lire_corps(self, limite=None):
        n = int(self.headers.get("Content-Length") or 0)
        if limite is None or limite >= n:
            return self.rfile.read(n) if n else b""
        return self.rfile.read(limite)

    def _repondre(self, statut, corps=b"", type_="application/json", entetes=None):
        if isinstance(corps, str):
            corps = corps.encode()
        self.send_response(statut)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(corps)))
        self.send_header("Connection", "close")
        for k, v in (entetes or {}).items():
            self.send_header(k, str(v))
        self.end_headers()
        self.wfile.write(corps)

    def _couper(self):
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.close_connection = True

    def _transmettre(self, corps, sans_auth=False, journal=None):
        amont = etat["amont"]
        c = http.client.HTTPConnection(amont[0], amont[1], timeout=120)
        entetes = {k: v for k, v in self.headers.items()
                   if k.lower() not in ("host", "connection", "content-length", "transfer-encoding")}
        if sans_auth:
            retires = ("authorization", "x-authorization") if sans_auth == "tous" else ("authorization",)
            entetes = {k: v for k, v in entetes.items() if k.lower() not in retires}
        entetes["Content-Length"] = str(len(corps))
        if journal is not None:  # ce que le serveur RECOIT (apres retrait eventuel)
            journal["authorization"] = any(k.lower() == "authorization" for k in entetes)
            journal["x_authorization"] = any(k.lower() == "x-authorization" for k in entetes)
        c.request(self.command, self.path, body=corps if corps else None, headers=entetes)
        r = c.getresponse()
        donnees = r.read()
        c.close()
        return r.status, r.getheaders(), donnees

    def _relayer(self, statut, ent, donnees):
        self.send_response(statut)
        for k, v in ent:
            if k.lower() in ("transfer-encoding", "connection", "content-length", "date", "server"):
                continue
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(donnees)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(donnees)

    # ------------------------------------------------------------------ requete
    def _traiter(self):
        chemin = self.path
        n_octets = int(self.headers.get("Content-Length") or 0)
        with verrou:
            etat["n"] += 1
            numero = etat["n"]
        regle = prendre_regle(chemin, self.command)
        action = regle["action"] if regle else "passe"
        journal = {"n": numero, "methode": self.command, "chemin": chemin, "octets": n_octets,
                   "action": action, "statut": None,
                   "authorization": "Authorization" in self.headers}

        try:
            if action == "statut":
                self._lire_corps()
                corps = regle.get("corps", "")
                journal["statut"] = regle["statut"]
                noter(journal)
                self._repondre(regle["statut"], corps if isinstance(corps, (str, bytes)) else json.dumps(corps),
                               regle.get("type", "text/html" if not isinstance(corps, (dict, list)) else "application/json"),
                               regle.get("entetes"))
            elif action == "html":
                self._lire_corps()
                journal["statut"] = regle.get("statut", 200)
                noter(journal)
                self._repondre(regle.get("statut", 200), PAGE_HEBERGEUR, "text/html; charset=UTF-8")
            elif action == "redirige":
                self._lire_corps()
                journal["statut"] = regle.get("statut", 301)
                noter(journal)
                self._repondre(regle.get("statut", 301), "", "text/html", {"Location": regle["location"]})
            elif action == "limite_corps":
                if n_octets > regle["octets"]:
                    journal["statut"] = 413
                    noter(journal)
                    self._couper_apres_413(regle)
                else:
                    corps = self._lire_corps()
                    s, e, d = self._transmettre(corps, journal=journal)
                    journal["statut"] = s
                    noter(journal)
                    self._relayer(s, e, d)
                    # la regle reste (LimitRequestBody est permanent)
            elif action == "coupe_requete":
                self._lire_corps(regle.get("octets", 0))
                noter(journal)
                self._couper()
            elif action == "coupe_avant_reponse":
                corps = self._lire_corps()
                s, _, _ = self._transmettre(corps, journal=journal)
                journal["statut"] = s
                journal["serveur_a_traite"] = True
                noter(journal)
                self._couper()
            elif action == "coupe_reponse":
                corps = self._lire_corps()
                s, e, d = self._transmettre(corps, journal=journal)
                journal["statut"] = s
                journal["serveur_a_traite"] = True
                noter(journal)
                brut = (f"HTTP/1.0 {s} OK\r\nContent-Type: application/json\r\n"
                        f"Content-Length: {len(d)}\r\n\r\n").encode() + d
                self.wfile.write(brut[: regle.get("octets", 20)])
                self.wfile.flush()
                self._couper()
            else:
                if action == "retard":
                    time.sleep(regle.get("ms", 0) / 1000)
                corps = self._lire_corps()
                s, e, d = self._transmettre(
                    corps, journal=journal, sans_auth=(("tous" if regle.get("aussi_x") else True) if action == "sans_authorization" else False))
                if action == "retard_reponse":
                    time.sleep(regle.get("ms", 0) / 1000)
                journal["statut"] = s
                noter(journal)
                self._relayer(s, e, d)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass
        except Exception as erreur:  # amont injoignable : 502 comme un vrai mandataire
            try:
                self._repondre(502, PAGE_HEBERGEUR, "text/html", None)
            except OSError:
                pass
            sys.stderr.write(f"[mandataire] {erreur!r}\n")

    def _couper_apres_413(self, regle):
        # Apache repond 413 SANS lire le corps : le client voit la reponse (ou une coupure).
        self._repondre(413, PAGE_413, "text/html; charset=iso-8859-1")

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = _traiter


class Commande(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    def _json(self, statut, valeur):
        corps = json.dumps(valeur).encode()
        self.send_response(statut)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        if self.path.startswith("/journal"):
            with verrou:
                return self._json(200, list(etat["journal"]))
        return self._json(200, {"ok": True})

    def do_PUT(self):
        n = int(self.headers.get("Content-Length") or 0)
        regles = json.loads(self.rfile.read(n) or b"[]")
        with verrou:
            etat["regles"] = regles
            etat["journal"] = []
            etat["n"] = 0
        self._json(200, {"regles": len(regles)})

    def do_DELETE(self):
        with verrou:
            etat["regles"] = []
            etat["journal"] = []
            etat["n"] = 0
        self._json(200, {"regles": 0})


# ------------------------------------------------------------------ certificats
def _openssl(*args, **kw):
    subprocess.run(["openssl", *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw)


def generer_certificats(dossier):
    """Autorité maison + 4 certificats serveur : valide, auto-signé, expiré, mauvais nom."""
    os.makedirs(dossier, exist_ok=True)
    j = lambda f: os.path.join(dossier, f)
    san = "subjectAltName=DNS:localhost,IP:127.0.0.1"
    _openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30", "-subj", "/CN=Autorite LogiALVIA (essai)",
             "-keyout", j("ca.key"), "-out", j("ca.pem"),
             "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign")

    def serveur(nom, sujet, san_ext, debut=None, fin=None, jours=30):
        _openssl("req", "-newkey", "rsa:2048", "-nodes", "-subj", sujet, "-keyout", j(nom + ".key"), "-out", j(nom + ".csr"))
        ext = j(nom + ".ext")
        with open(ext, "w") as f:
            f.write(san_ext + "\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n")
        if debut:
            # certificat date : `openssl ca` accepte -startdate / -enddate
            base = j("ca_" + nom)
            os.makedirs(base, exist_ok=True)
            open(os.path.join(base, "index.txt"), "w").close()
            open(os.path.join(base, "serial"), "w").write("0A\n")
            cfg = j(nom + ".cnf")
            with open(cfg, "w") as f:
                f.write(f"[ca]\ndefault_ca=c\n[c]\ndir={base}\ndatabase={base}/index.txt\nnew_certs_dir={base}\n"
                        f"serial={base}/serial\npolicy=p\ndefault_md=sha256\nunique_subject=no\ncopy_extensions=none\n"
                        f"x509_extensions=e\n[p]\ncommonName=supplied\n[e]\nbasicConstraints=CA:FALSE\n"
                        f"{san_ext}\n")
            _openssl("ca", "-batch", "-config", cfg, "-cert", j("ca.pem"), "-keyfile", j("ca.key"),
                     "-in", j(nom + ".csr"), "-out", j(nom + ".pem"), "-startdate", debut, "-enddate", fin)
        else:
            _openssl("x509", "-req", "-in", j(nom + ".csr"), "-CA", j("ca.pem"), "-CAkey", j("ca.key"), "-CAcreateserial",
                     "-days", str(jours), "-out", j(nom + ".pem"), "-extfile", ext)

    serveur("valide", "/CN=localhost", san)
    serveur("mauvais_nom", "/CN=autre.exemple.bj", "subjectAltName=DNS:autre.exemple.bj")
    serveur("expire", "/CN=localhost", san, debut="20200101000000Z", fin="20200102000000Z")
    _openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30", "-subj", "/CN=localhost",
             "-keyout", j("autosigne.key"), "-out", j("autosigne.pem"), "-addext", san)
    return dossier


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--amont", default="http://127.0.0.1:8765")
    p.add_argument("--port", type=int, default=8780)
    p.add_argument("--controle", type=int, default=8781)
    p.add_argument("--tls", help="dossier des certificats (générés s'ils manquent) : active HTTPS")
    p.add_argument("--certificat", default="valide", choices=["valide", "autosigne", "expire", "mauvais_nom"])
    p.add_argument("--generer-seulement", help="génère les certificats dans ce dossier et sort")
    a = p.parse_args()

    if a.generer_seulement:
        print(generer_certificats(a.generer_seulement))
        return
    h, _, port = a.amont.replace("http://", "").partition(":")
    etat["amont"] = (h, int(port or 80))

    serveur = ThreadingHTTPServer(("127.0.0.1", a.port), Mandataire)
    serveur.daemon_threads = True
    if a.tls:
        if not os.path.exists(os.path.join(a.tls, "ca.pem")):
            generer_certificats(a.tls)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(os.path.join(a.tls, a.certificat + ".pem"), os.path.join(a.tls, a.certificat + ".key"))
        serveur.socket = ctx.wrap_socket(serveur.socket, server_side=True)
    commande = ThreadingHTTPServer(("127.0.0.1", a.controle), Commande)
    commande.daemon_threads = True
    threading.Thread(target=commande.serve_forever, daemon=True).start()
    print(f"mandataire {'https' if a.tls else 'http'}://127.0.0.1:{a.port} -> {a.amont} (controle :{a.controle})", flush=True)
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
