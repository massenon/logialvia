import 'package:drift/drift.dart';

/// Table `FOURNISSEURS` — Doc D1 §2.
@DataClassName('FournisseurRow')
class Fournisseurs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nom => text()();

  /// Doc D1 nomme cette colonne `contact` ; le tableau reel (`fournisseurs.html`
  /// l.135) l'intitule « Téléphone ». Meme donnee, nom aligne sur l'interface.
  TextColumn get telephone => text().nullable()();

  TextColumn get adresse => text().nullable()();

  /// ⚠️ AJOUTEE — colonne « Fournit » du tableau reel (l.136) : ce que le
  /// fournisseur approvisionne. Absente de Doc D1.
  TextColumn get fournit => text().nullable()();
}
