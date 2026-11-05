# -*- coding: utf-8 -*-
"""Fabrique l'icone Windows de LogiALVIA depuis le logo fourni.

    python outils/generer_icone.py

## Pourquoi le medaillon seul, et pas le logo entier

Le fichier fourni est un verrouillage complet : medaillon, mot-symbole
« LogiALVIA », baseline et raison sociale. Dans la barre des taches, l'icone
mesure 16 px de cote ; a cette taille le mot-symbole fait moins d'un pixel de
hauteur par lettre. Une icone qu'on ne peut pas distinguer ne remplit pas son
role -- reconnaitre l'application d'un coup d'oeil parmi vingt autres.

L'icone est donc batie sur le **medaillon**, decoupe dans le logo lui-meme :
meme dessin, meme marine, mais lisible de 16 a 256 px. Le logo complet reste
utilise la ou il a la place de s'exprimer : ecran d'accueil, documents, en-tete
des PDF.
"""
import os
import sys

from PIL import Image

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJET = os.path.dirname(RACINE)

SOURCE = os.path.join(PROJET, 'logo', 'logo_logialvia.png')
ICONE = os.path.join(RACINE, 'windows', 'runner', 'resources', 'app_icon.ico')
APERCU = os.path.join(PROJET, 'logo', 'app_icon_apercu.png')

# Les tailles que Windows pioche selon le contexte : barre des taches, titre de
# fenetre, explorateur en grandes icones, panneau de configuration.
TAILLES = [16, 24, 32, 48, 64, 128, 256]


def boite_du_medaillon(im):
    """Trouve le cercle clair dans le tiers superieur de l'image."""
    largeur, hauteur = im.size
    px = im.convert('RGB').load()
    xs, ys = [], []
    # On s'arrete avant le mot-symbole, dont le « Logi » est blanc lui aussi.
    limite = int(hauteur * 0.42)
    for y in range(limite):
        for x in range(largeur):
            r, v, b = px[x, y]
            if r > 200 and v > 200 and b > 200:
                xs.append(x)
                ys.append(y)
    if not xs:
        raise SystemExit('Medaillon introuvable dans %s' % SOURCE)

    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    rayon = max(max(xs) - min(xs), max(ys) - min(ys)) / 2
    # Une marge de 18 % : le cercle ne doit pas toucher le bord de l'icone.
    demi = rayon * 1.18
    return (
        int(round(cx - demi)),
        int(round(cy - demi)),
        int(round(cx + demi)),
        int(round(cy + demi)),
    )


def main():
    if not os.path.exists(SOURCE):
        raise SystemExit('Logo introuvable : %s' % SOURCE)

    logo = Image.open(SOURCE).convert('RGBA')
    boite = boite_du_medaillon(logo)
    medaillon = logo.crop(boite)

    # Carre parfait, quitte a rogner d'un pixel : une icone etiree se voit.
    cote = min(medaillon.size)
    medaillon = medaillon.crop((0, 0, cote, cote))

    # Un seul reechantillonnage depuis la source vers chaque taille, plutot
    # qu'une cascade : chaque reduction intermediaire coute de la nettete.
    calques = [
        medaillon.resize((t, t), Image.LANCZOS) for t in TAILLES
    ]

    calques[-1].save(ICONE, format='ICO', sizes=[(t, t) for t in TAILLES])

    # Une planche de controle : c'est a 16 px qu'une icone se juge.
    apercu = Image.new('RGBA', (sum(TAILLES) + 20 * len(TAILLES), 280),
                       (255, 255, 255, 255))
    x = 10
    for calque, taille in zip(calques, TAILLES):
        apercu.paste(calque, (x, (280 - taille) // 2), calque)
        x += taille + 20
    apercu.save(APERCU)

    print('Icone ecrite : %s' % ICONE)
    print('Tailles : %s' % ', '.join('%dx%d' % (t, t) for t in TAILLES))
    print('Apercu : %s' % APERCU)
    return 0


if __name__ == '__main__':
    sys.exit(main())
