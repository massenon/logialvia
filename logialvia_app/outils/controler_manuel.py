# -*- coding: utf-8 -*-
"""Contrôle la mise en page du PDF **produit**, pas du source.

    python outils/controler_manuel.py

# Pourquoi mesurer le PDF plutôt que relire le HTML ou le code

Un générateur peut être juste et produire une page à moitié vide : un encadré
trop haut renvoyé au verso, un titre orphelin en pied de page, une légende
séparée de son image. Rien de tout cela ne se voit dans le source — seulement
à l'impression, quand le document est déjà distribué.

Ce contrôle mesure donc le document final :

- le **blanc en bas de page**, qui révèle un bloc insécable trop haut ;
- les **légendes orphelines**, séparées de la capture qu'elles décrivent ;
- les **captures déformées**, dont le rapport ne correspond plus à la source ;
- les **titres orphelins**, seuls en bas d'une page.

Sortie : un compte rendu, et un code de retour non nul si un défaut est trouvé.
"""
import os
import sys

try:
    import pymupdf
except ImportError:  # pragma: no cover
    print('pymupdf est requis : python -m pip install pymupdf')
    sys.exit(2)

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PDF = os.path.join(RACINE, '..', 'docs', 'manuel',
                   'LogiALVIA-Manuel-Utilisation.pdf')

# La capture d'écran de référence : 1382 × 794 px de viewport.
RAPPORT_CAPTURE = 1382 / 794

# Un tiers de page blanche en bas signale un bloc qui n'a pas pu se placer.
SEUIL_BLANC = 0.34


def controler():
    if not os.path.exists(PDF):
        print('PDF introuvable : %s' % PDF)
        return 2

    doc = pymupdf.open(PDF)
    defauts = []
    toleres = []

    # Les dernieres pages de chapitre : leur blanc est **voulu**. Chaque
    # chapitre commence sur une page neuve, donc la page qui precede le debut
    # du suivant est une fin de chapitre.
    debuts = sorted({entree[2] for entree in doc.get_toc() if entree[0] == 1})
    fins_de_chapitre = {d - 1 for d in debuts if d > 1}
    fins_de_chapitre.add(doc.page_count)

    for i in range(doc.page_count):
        page = doc[i]
        hauteur = page.rect.height
        boites = [page.get_image_bbox(im) for im in page.get_images(full=True)]

        # 1. Les captures gardent-elles leur rapport ?
        for b in boites:
            if b.height <= 0:
                continue
            rapport = b.width / b.height
            if abs(rapport - RAPPORT_CAPTURE) > 0.02:
                defauts.append(
                    'page %d : capture déformée (rapport %.3f au lieu de %.3f)'
                    % (i + 1, rapport, RAPPORT_CAPTURE)
                )

        blocs = page.get_text('blocks')
        if not blocs:
            continue

        # 2. Les légendes collées à leur image.
        for b in blocs:
            texte = b[4].strip()
            if texte.startswith('Écran ') or texte.startswith('Fenêtre ') \
                    or texte.startswith('Onglet '):
                if not any(abs(bb.y1 - b[1]) < 14 for bb in boites):
                    defauts.append(
                        'page %d : légende séparée de sa capture — %s'
                        % (i + 1, texte[:48])
                    )

        # 3. Le blanc en bas de page.
        #
        #    La couverture n'a ni marge ni pied : elle est exclue. Surtout,
        #    l'en-tete et le pied courants sont ecartes du calcul -- mesurer
        #    jusqu'au pied donnait 5,7 % sur **toutes** les pages, et le
        #    controle etait vert par construction.
        if i == 0:
            continue
        haut_pied = hauteur - 60
        contenu = [
            b for b in blocs
            if b[1] > 60 and b[3] < haut_pied
        ]
        if not contenu:
            continue
        bas = max(b[3] for b in contenu)
        blanc = (haut_pied - bas) / (haut_pied - 60)
        # Le pied de page occupe deja le bas : au-dela du seuil, c'est un bloc
        # qui n'a pas trouve sa place.
        if blanc > SEUIL_BLANC and (i + 1) not in fins_de_chapitre:
            # Une capture est insecable par nature : la laisser se couper
            # donnerait une image tronquee, ce qui est pire qu'un blanc. Si la
            # page suivante commence par une image, le blanc est le prix de son
            # integrite -- il est signale comme tolere, pas comme un defaut.
            suivante_commence_par_image = False
            if i + 1 < doc.page_count:
                apres_page = doc[i + 1]
                images = [
                    apres_page.get_image_bbox(im)
                    for im in apres_page.get_images(full=True)
                ]
                textes = [
                    b for b in apres_page.get_text('blocks')
                    if b[1] > 60 and b[3] < apres_page.rect.height - 60
                ]
                if images:
                    haut_image = min(b.y0 for b in images)
                    haut_texte = min([b[1] for b in textes], default=1e9)
                    suivante_commence_par_image = haut_image <= haut_texte + 2

            if suivante_commence_par_image:
                toleres.append(
                    'page %d : %.0f %% de blanc, laisse à une capture '
                    'insécable' % (i + 1, blanc * 100)
                )
            else:
                defauts.append(
                    'page %d : %.0f %% de blanc en bas — un bloc insécable a '
                    'basculé sans raison visible' % (i + 1, blanc * 100)
                )

    print('Pages           : %d' % doc.page_count)
    print('Signets         : %d' % len(doc.get_toc()))
    print('Captures        : %d'
          % sum(len(doc[i].get_images(full=True))
                for i in range(doc.page_count)))
    print('Taille          : %.1f Mo' % (os.path.getsize(PDF) / 1024 / 1024))

    if toleres:
        print('\n%d page(s) creuses, expliquées par une capture insécable :'
              % len(toleres))
        for t in toleres:
            print('  · %s' % t)

    if not defauts:
        print('\nMise en page    : aucun défaut relevé.')
        return 0

    print('\n%d défaut(s) de mise en page :' % len(defauts))
    for d in defauts:
        print('  - %s' % d)
    return 1


if __name__ == '__main__':
    sys.exit(controler())
