import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/widgets/geometrie_fenetre.dart';

void main() {
  // Bureau 1536 x 816 logiques (ecran 1920 x 1020 a 125 %), 250 % : 1382 x 794.
  const petit = Rect.fromLTWH(0, 0, 1536, 816);

  test('la fenetre restauree tient dans le bureau et est centree', () {
    final r = rectangleFenetreRestauree(petit);
    expect(r.height, lessThan(petit.height));
    expect(r.top, greaterThan(0));
    expect(r.bottom, lessThan(petit.bottom));
    expect((r.center - petit.center).distance, lessThan(0.01));
  });

  test('grand bureau : taille souhaitee conservee', () {
    final r = rectangleFenetreRestauree(const Rect.fromLTWH(0, 0, 2560, 1400));
    expect(r.size, tailleFenetreSouhaitee);
  });

  test('une fenetre qui deborde en haut est ramenee dans la zone', () {
    final r = ramenerDansZone(const Rect.fromLTWH(48, -41, 1440, 900), petit);
    expect(r.top, 0);
    expect(r.height, lessThanOrEqualTo(petit.height));
    expect(r.bottom, lessThanOrEqualTo(petit.bottom));
  });

  test('une fenetre deja bien placee ne bouge pas', () {
    const ok = Rect.fromLTWH(100, 50, 1000, 600);
    expect(ramenerDansZone(ok, petit), ok);
  });
}
