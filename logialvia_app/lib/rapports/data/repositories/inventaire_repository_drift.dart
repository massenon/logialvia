import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../elevage/domain/entities/configuration_espece.dart';
import '../../domain/entities/inventaire.dart';

/// Construit l'inventaire à une date, depuis les mouvements réellement tracés.
///
/// ## La règle qui gouverne tout ce dépôt
///
/// Le stock d'un article n'est pas stocké *par date* : `INTRANTS.stock` et
/// `PRODUITS_VENDABLES.stock` donnent l'état **d'aujourd'hui**. Un inventaire
/// daté se reconstitue donc à rebours :
///
/// > stock à la date T = stock actuel − (mouvements postérieurs à T)
///
/// C'est la seule méthode exacte avec ce modèle. Prendre `stock` tel quel pour
/// une date passée donnerait un inventaire d'aujourd'hui portant la date
/// d'hier — le genre d'erreur qu'un contrôle ne rattrape jamais.
class InventaireRepositoryDrift {
  const InventaireRepositoryDrift(this._db);

  final AppDatabase _db;

  Future<Inventaire> construire({
    required DateTime debut,
    required DateTime fin,
  }) async {
    final depuis = DateTime(debut.year, debut.month, debut.day);
    // Borne haute exclusive : « jusqu'au 8 » doit inclure toute la journee du 8.
    final jusqua = DateTime(
      fin.year,
      fin.month,
      fin.day,
    ).add(const Duration(days: 1));

    return Inventaire(
      debut: depuis,
      fin: DateTime(fin.year, fin.month, fin.day),
      intrants: await _intrants(depuis, jusqua),
      produits: await _produits(depuis, jusqua),
      effectifs: await _effectifs(jusqua),
      oeufsEnIncubation: await _oeufsEnIncubation(jusqua),
    );
  }

  // ------------------------------------------------------------- intrants

  Future<List<LigneInventaireIntrant>> _intrants(
    DateTime depuis,
    DateTime jusqua,
  ) async {
    final articles = await (_db.select(
      _db.intrants,
    )..orderBy([(i) => OrderingTerm.asc(i.name)])).get();
    final mouvements = await _db.select(_db.mouvementsIntrant).get();

    final lignes = <LigneInventaireIntrant>[];
    for (final a in articles) {
      final siens = mouvements.where((m) => m.intrantCode == a.code);

      // Ce qui a bouge APRES la periode : a defalquer du stock d'aujourd'hui
      // pour retrouver l'etat a la cloture.
      final apres = siens
          .where((m) => !m.horodatage.isBefore(jusqua))
          .fold<double>(0, (s, m) => s + m.quantite);

      final dansLaPeriode = siens.where(
        (m) => !m.horodatage.isBefore(depuis) && m.horodatage.isBefore(jusqua),
      );
      final entrees = dansLaPeriode
          .where((m) => m.quantite > 0)
          .fold<double>(0, (s, m) => s + m.quantite);
      final sorties = dansLaPeriode
          .where((m) => m.quantite < 0)
          .fold<double>(0, (s, m) => s - m.quantite);

      final stockFinal = a.stock - apres;

      lignes.add(
        LigneInventaireIntrant(
          code: a.code,
          article: a.name,
          categorie: a.cat,
          unite: a.unit,
          stockInitial: stockFinal - entrees + sorties,
          entrees: entrees,
          sorties: sorties,
          stockFinal: stockFinal,
          pmp: a.pmp,
        ),
      );
    }
    return lignes;
  }

  // ------------------------------------------------------------- produits

  Future<List<LigneInventaireProduit>> _produits(
    DateTime depuis,
    DateTime jusqua,
  ) async {
    final produits = await (_db.select(
      _db.produitsVendables,
    )..orderBy([(p) => OrderingTerm.asc(p.name)])).get();

    // Les seules sorties datees d'un produit fini sont ses ventes. Une vente
    // annulee ne sort rien : elle est ecartee ici, comme partout ailleurs.
    final jointure = await (_db.select(_db.lignesVente).join([
      innerJoin(_db.ventes, _db.ventes.ref.equalsExp(_db.lignesVente.venteRef)),
    ])..where(_db.ventes.status.equals('Annulée').not())).get();

    double vendu(int produitId, bool Function(DateTime) filtre) => jointure
        .where(
          (l) =>
              l.readTable(_db.lignesVente).produitId == produitId &&
              filtre(l.readTable(_db.ventes).dateVente),
        )
        .fold<double>(0, (s, l) => s + l.readTable(_db.lignesVente).qte);

    return [
      for (final p in produits)
        () {
          final apres = vendu(p.id, (d) => !d.isBefore(jusqua));
          final sorties = vendu(
            p.id,
            (d) => !d.isBefore(depuis) && d.isBefore(jusqua),
          );
          final stockFinal = (p.stock + apres).round();
          return LigneInventaireProduit(
            sku: p.sku ?? '—',
            produit: p.name,
            categorie: p.cat,
            unite: p.unit,
            stockInitial: (stockFinal + sorties).round(),
            sorties: sorties,
            stockFinal: stockFinal,
            coutRevient: p.coutRevient,
            espece: p.espece,
          );
        }(),
    ];
  }

  // ------------------------------------------------------------ effectifs

  Future<List<LigneInventaireEffectif>> _effectifs(DateTime jusqua) async {
    final lignes = <LigneInventaireEffectif>[];

    for (final config in ConfigurationsEspeces.parIdentifiant.values.toSet()) {
      // La derniere journee REELLEMENT saisie avant la cloture : une journee
      // projetee ne temoigne d'aucun comptage.
      final jour =
          await (_db.select(_db.ficheJournee)
                ..where(
                  (f) =>
                      f.espece.equals(config.identifiant) &
                      f.isRecorded.equals(true) &
                      f.date.isSmallerThanValue(jusqua),
                )
                ..orderBy([(f) => OrderingTerm.desc(f.date)])
                ..limit(1))
              .getSingleOrNull();

      lignes.add(
        LigneInventaireEffectif(
          espece: config.identifiant,
          libelle: config.libelle,
          effectif: jour?.effectif ?? 0,
          dateSaisie: jour?.date,
        ),
      );
    }
    return lignes;
  }

  Future<int> _oeufsEnIncubation(DateTime jusqua) async {
    final lots = await _db.select(_db.cycleCouveuse).get();
    return lots
        .where(
          (l) =>
              l.dateIncubation.isBefore(jusqua) && l.statut == 'En incubation',
        )
        .fold<int>(
          0,
          (total, l) =>
              total +
              l.oeufsCouves -
              (l.oeufsBlancsJ7 ?? 0) -
              (l.oeufsGatesJ14 ?? 0),
        );
  }
}
