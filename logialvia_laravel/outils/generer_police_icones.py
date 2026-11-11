#!/usr/bin/env python3
"""Genere config/icones.php (nom -> point de code) et la police d'icones reduite du web.

Usage : python3 outils/generer_police_icones.py <dossier lib/ de material_symbols_icons> [dossier fonttools]
Source des noms : outils/icones.txt. La police est celle du poste (meme paquet Dart) : memes glyphes.
"""
import re
import sys
from pathlib import Path

racine = Path(__file__).resolve().parent.parent
lib = Path(sys.argv[1])
if len(sys.argv) > 2:
    sys.path.insert(0, sys.argv[2])
from fontTools import subset  # noqa: E402

noms = [l.strip() for l in (racine / 'outils/icones.txt').read_text(encoding='utf8').splitlines()
        if l.strip() and not l.startswith('#')]
dart = (lib / 'symbols.dart').read_text(encoding='utf8')
points = {}
for n in noms:
    m = re.search(r'static const IconData ' + re.escape(n) + r' =\s*IconData\((0x[0-9a-fA-F]+)', dart)
    if not m:
        sys.exit(f'Icone inconnue dans material_symbols_icons : {n}')
    points[n] = m.group(1)[2:].lower()

lignes = ["<?php", "", "// GENERE par outils/generer_police_icones.py : ne pas modifier a la main.", "", "return ["]
lignes += [f"    '{n}' => '{points[n]}'," for n in sorted(points)]
lignes += ["];", ""]
(racine / 'config/icones.php').write_text("\n".join(lignes), encoding='utf8')

opts = subset.Options()
opts.flavor = None
opts.layout_features = ['*']
opts.notdef_outline = True
opts.glyph_names = False
police = subset.load_font(str(lib / 'fonts/MaterialSymbolsOutlined.ttf'), opts)
s = subset.Subsetter(opts)
s.populate(unicodes=[int(c, 16) for c in points.values()])
s.subset(police)
# Instance STATIQUE (remplissage 0, graisse 400, opsz 24, GRAD 0) : le web n'utilise aucun autre axe ;
# la police variable pesait ~150 Ko, l'instance WOFF2 ~12 Ko (garde de performance LCP < 2 s, 47x_).
from fontTools.varLib import instancer  # noqa: E402

police = instancer.instantiateVariableFont(police, {'FILL': 0, 'wght': 400, 'GRAD': 0, 'opsz': 24})
police.flavor = 'woff2'
sortie = racine / 'public/fonts/MaterialSymbolsOutlined-LogiALVIA.woff2'
police.save(str(sortie))
print(f'{len(points)} icones, {sortie.stat().st_size} octets')
