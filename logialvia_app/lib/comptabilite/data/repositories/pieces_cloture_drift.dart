import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../domain/services/report_a_nouveau.dart';

/// Écriture et retrait des pièces de clôture (`CL`) et d'à-nouveaux (`AN`) — `47c_`.
///
/// ## Identifiants déterministes
///
/// La pièce et chacune de ses lignes ont un identifiant **dérivé** de la clé de la pièce
/// (`cloture:2026:resultat`, `an:2027`) et du compte : le poste et le serveur, qui clôturent
/// le même exercice depuis le même livre, produisent les mêmes identifiants. Rejouer la
/// clôture, ou recevoir du serveur une pièce que ce poste a déjà écrite, ne duplique rien.
///
/// ## Jamais envoyées
///
/// Les lignes sont créées `synced` : elles ne partent pas vers le serveur. Ce sont des
/// écritures **dérivées** du livre (aucune saisie) : le serveur les engendre lui-même à la
/// clôture, avec les mêmes identifiants, et les sert aux autres postes.
class PiecesClotureDrift {
  const PiecesClotureDrift(this._db);

  final AppDatabase _db;

  static String idPiece(String cle) => uuidDeterministe('piece:$cle');

  static String idLigne(String cle, String compte) =>
      uuidDeterministe('ligne:$cle:$compte');

  /// Écrit la pièce si elle n'existe pas déjà (idempotent). Les lignes de l'exercice
  /// [verrouille] sont écrites verrouillées.
  Future<bool> inserer(PieceCloture piece, {required bool verrouillee}) async {
    final pieceId = idPiece(piece.cle);
    final deja =
        await (_db.select(_db.ecritureComptable)
              ..where((e) => e.pieceId.equals(pieceId))
              ..limit(1))
            .getSingleOrNull();
    if (deja != null) return false;

    final saisie = instantSaisie();
    for (final ligne in piece.lignes) {
      await _db
          .into(_db.ecritureComptable)
          .insert(
            EcritureComptableCompanion.insert(
              id: Value(idLigne(piece.cle, ligne.numeroCompte)),
              pieceId: Value(pieceId),
              exerciceAnnee: piece.exerciceAnnee,
              numeroCompte: ligne.numeroCompte,
              dateEcriture: piece.date,
              debit: Value(ligne.debit),
              credit: Value(ligne.credit),
              libelle: ligne.libelle,
              journalCode: Value(piece.journalCode),
              numeroPiece: Value(piece.numeroPiece),
              isLocked: Value(verrouillee),
              // Dérivée : ne part jamais (le serveur engendre les mêmes lignes).
              syncStatus: const Value('synced'),
              updatedAt: Value(saisie),
            ),
          );
    }
    return true;
  }

  /// Retire les écritures de clôture de [annee] (`CL`) et les à-nouveaux de l'exercice
  /// suivant (`AN`). Utilisé par la réouverture et par le refus d'une clôture.
  Future<int> supprimerDeLExercice(int annee) async {
    final cl =
        await (_db.delete(_db.ecritureComptable)..where(
              (e) =>
                  e.exerciceAnnee.equals(annee) &
                  e.journalCode.equals(JournauxDeCloture.cloture),
            ))
            .go();
    final an =
        await (_db.delete(_db.ecritureComptable)..where(
              (e) =>
                  e.exerciceAnnee.equals(annee + 1) &
                  e.journalCode.equals(JournauxDeCloture.reportANouveau),
            ))
            .go();
    return cl + an;
  }
}
