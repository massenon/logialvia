"""Ouvre un export XLSX avec openpyxl et en dit l'essentiel en JSON (appele par transversaux.mjs).

    python3 -I e2e/verifier_xlsx.py fichier.xlsx

Sortie : feuilles, lignes, premiere ligne (en-tete), nombre de cellules numeriques TYPEES, et liste des cellules
TEXTE qui ressemblent a un nombre (un montant range en texte ne se totalise pas dans Excel).
"""
import json
import re
import sys

from openpyxl import load_workbook

classeur = load_workbook(sys.argv[1], data_only=True)
resultat = {"feuilles": classeur.sheetnames, "details": []}
nombre = re.compile(r"^-?\d+([.,]\d+)?$")
for feuille in classeur.worksheets:
    lignes = list(feuille.iter_rows(values_only=True))
    numeriques = 0
    textes_numeriques = []
    # Un titre (cellule seule) peut precéder l'en-tete : l'en-tete est la 1re ligne a au moins 2 cellules remplies.
    debut = next((i for i, l in enumerate(lignes) if sum(1 for c in l if c not in (None, "")) >= 2), 0)
    titre_feuille = str(lignes[0][0]) if debut > 0 and lignes[0][0] else feuille.title
    entete = [str(c or "") for c in (lignes[debut] if lignes else [])]
    # Les IDENTIFIANTS (numero de compte, code, classe, reference, N° de piece) restent du texte : « 701 » n'est pas une quantite.
    identifiant = re.compile(r"compte|n°|numéro|numero|code|classe|réf|ref|pièce|piece|ifu|tel|tél", re.I)
    for l in lignes[debut + 1:]:
        for i, c in enumerate(l):
            if i < len(entete) and identifiant.search(entete[i]):
                continue
            if isinstance(c, (int, float)) and not isinstance(c, bool):
                numeriques += 1
            elif isinstance(c, str) and nombre.match(c.strip()) and len(c.strip()) < 9:
                textes_numeriques.append(c)
    resultat["details"].append({
        "titre": feuille.title,
        "titre_ligne": titre_feuille,
        "debut": debut,
        "lignes": len(lignes),
        "colonnes": feuille.max_column,
        "entete": [str(c) for c in (lignes[debut] if lignes else [])],
        "numeriques": numeriques,
        "textes_numeriques": textes_numeriques[:5],
        "entete_vide": any(c is None or str(c).strip() == "" for c in (list(lignes[debut]) if lignes else [None])[: max([i for i, c in enumerate(lignes[debut]) if c not in (None, "")] + [0]) + 1]),
    })
print(json.dumps(resultat, ensure_ascii=False))
