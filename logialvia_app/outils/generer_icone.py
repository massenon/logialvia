# -*- coding: utf-8 -*-
"""Fabrique les icones de LogiALVIA depuis le logo ALLMANY ET COMPAGNIE (logo/logo_allmany.png).

    python outils/generer_icone.py

Sorties (toutes derivees du meme embleme, un seul reechantillonnage par taille) :
  - poste : windows/runner/resources/app_icon.ico (icone de l'installateur, de la fenetre
    et de la barre des taches) + logo/app_icon_apercu.png (planche de controle) ;
  - web   : logialvia_laravel/public/favicon.ico, icons/favicon-32.png, apple-touch-icon.png,
    icon-192.png, icon-512.png, icon-maskable-512.png.

## Pourquoi l'embleme seul, sur une pastille blanche

Le fichier fourni est un verrouillage complet : embleme (le « A » et sa feuille verte), mot
« ALLMANY » et « ET COMPAGNIE ». A 16 px (barre des taches, onglet du navigateur) le texte
est illisible : l'icone est batie sur l'**embleme**, decoupe dans le logo lui-meme, pose sur
une pastille blanche arrondie (le marine du logo disparaitrait sur une barre sombre). Le logo
complet reste utilise la ou il a la place de s'exprimer.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJET = os.path.dirname(RACINE)

SOURCE = os.path.join(PROJET, 'logo', 'logo_allmany.png')
ICONE = os.path.join(RACINE, 'windows', 'runner', 'resources', 'app_icon.ico')
APERCU = os.path.join(PROJET, 'logo', 'app_icon_apercu.png')
WEB = os.path.join(PROJET, 'logialvia_laravel', 'public')

# Tailles que Windows pioche : barre des taches, titre, explorateur, panneau de config.
TAILLES = [16, 24, 32, 48, 64, 128, 256]
BLANC = (255, 255, 255, 255)


def embleme(logo):
    """Decoupe l'embleme : le premier bloc de colonnes non blanches, a gauche du mot-symbole."""
    a = np.array(logo.convert('RGB')).astype(int)
    non_blanc = (255 * 3 - a.sum(2)) > 60
    colonnes = np.where(non_blanc.any(0))[0]
    fin = colonnes[0]
    for c in colonnes:
        if c - fin > 3:
            break
        fin = c
    bloc = non_blanc[:, colonnes[0]:fin + 1]
    lignes = np.where(bloc.any(1))[0]
    boite = (int(colonnes[0]), int(lignes.min()), int(fin) + 1, int(lignes.max()) + 1)
    return logo.convert('RGBA').crop(boite)


def pastille(em, taille, remplissage=0.70, arrondi=0.22, plein=False):
    """Embleme centre (remplissage = part de la pastille) sur fond blanc arrondi ou plein."""
    s = taille * 4  # sur-echantillonne : bords arrondis propres
    fond = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(fond)
    if plein:
        d.rectangle((0, 0, s, s), fill=BLANC)
    else:
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * arrondi), fill=BLANC)
    largeur = s * remplissage
    ratio = largeur / max(em.size)
    e = em.resize((max(1, round(em.width * ratio)), max(1, round(em.height * ratio))), Image.LANCZOS)
    fond.alpha_composite(e, ((s - e.width) // 2, (s - e.height) // 2))
    return fond.resize((taille, taille), Image.LANCZOS)


def main():
    if not os.path.exists(SOURCE):
        raise SystemExit('Logo introuvable : %s' % SOURCE)
    em = embleme(Image.open(SOURCE))

    calques = [pastille(em, t) for t in TAILLES]
    calques[-1].save(ICONE, format='ICO', sizes=[(t, t) for t in TAILLES])

    apercu = Image.new('RGBA', (sum(TAILLES) + 20 * len(TAILLES), 280), (60, 60, 70, 255))
    x = 10
    for calque, taille in zip(calques, TAILLES):
        apercu.alpha_composite(calque, (x, (280 - taille) // 2))
        x += taille + 20
    apercu.save(APERCU)

    os.makedirs(os.path.join(WEB, 'icons'), exist_ok=True)
    pastille(em, 256).save(os.path.join(WEB, 'favicon.ico'), format='ICO', sizes=[(16, 16), (32, 32), (48, 48)])
    pastille(em, 32).save(os.path.join(WEB, 'icons', 'favicon-32.png'))
    pastille(em, 180, remplissage=0.74, plein=True).save(os.path.join(WEB, 'icons', 'apple-touch-icon.png'))
    pastille(em, 192).save(os.path.join(WEB, 'icons', 'icon-192.png'))
    pastille(em, 512).save(os.path.join(WEB, 'icons', 'icon-512.png'))
    # Maskable : fond plein, embleme dans la zone sure (80 % central, ici 56 %).
    pastille(em, 512, remplissage=0.56, plein=True).save(os.path.join(WEB, 'icons', 'icon-maskable-512.png'))

    print('Icone poste : %s (%s)' % (ICONE, ', '.join('%d' % t for t in TAILLES)))
    print('Icones web  : %s' % WEB)
    print('Apercu      : %s' % APERCU)
    return 0


if __name__ == '__main__':
    sys.exit(main())
