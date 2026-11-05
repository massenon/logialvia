import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/seed/seed_demonstration.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/elevage/data/repositories/cycle_couveuse_repository_drift.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/cycle_couveuse_view_model.dart';
import 'package:logialvia_app/pilotage/data/repositories/tableau_bord_repository_drift.dart';
import 'package:logialvia_app/pilotage/presentation/viewmodels/tableau_bord_view_model.dart';
import 'package:logialvia_app/rapports/data/repositories/inventaire_repository_drift.dart';

/// Les chiffres se recoupent-ils d'un écran à l'autre ?
///
/// ## La classe de défaut que ces tests visent
///
/// Les 33 écrans s'affichent sans exception avec un mois de données. Reste la
/// question qui compte : **disent-ils vrai ?**
///
/// Un chiffre faux ne plante rien. Il s'affiche, il est plausible, et il se
/// découvre des mois plus tard — au moment où la Gérante compare son tableau de
/// bord à son journal comptable et n'obtient pas la même chose. C'est le seul
/// type de bug que ni `flutter analyze`, ni les tests de rendu, ni l'œil ne
/// rattrapent.
///
/// Chaque test confronte donc un écran à la **source** de son chiffre, calculée
/// indépendamment en SQL.
void main() {
  late AppDatabase db;
  final reference = DateTime(2026, 8, 20);

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    await SeedDemonstration(db).executer(jusqua: reference);
  });

  tearDown(() => db.close());

  Future<double> unSeulNombre(String sql) async {
    final ligne = await db.customSelect(sql).getSingle();
    final valeur = ligne.data.values.first;
    return valeur == null ? 0 : (valeur as num).toDouble();
  }

  group('Comptabilité — la partie double tient', () {
    test('chaque écriture est équilibrée, débit = crédit', () async {
      // BR-CPT-001. Une seule ecriture bancale rend tous les etats faux, et
      // aucun ecran ne le crierait.
      final ecart = await unSeulNombre(
        'SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) '
        'FROM ecriture_comptable',
      );
      expect(ecart.abs(), lessThan(0.01));
    });

    test('chaque pièce prise isolément est équilibrée', () async {
      final pieces = await db
          .customSelect(
            'SELECT numero_piece, '
            'COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS ecart '
            'FROM ecriture_comptable GROUP BY numero_piece',
          )
          .get();

      expect(
        pieces,
        isNotEmpty,
        reason: 'Le mois doit avoir généré des pièces.',
      );
      for (final p in pieces) {
        expect(
          p.read<double>('ecart').abs(),
          lessThan(0.01),
          reason:
              'La pièce ${p.read<String>('numero_piece')} n\'est pas '
              'équilibrée : l\'équilibre global peut masquer deux pièces '
              'fausses qui se compensent.',
        );
      }
    });

    test('chaque vente non annulée a produit son écriture', () async {
      final ventes = await unSeulNombre(
        "SELECT COUNT(*) FROM ventes WHERE status <> 'Annulée'",
      );
      final piecesDeVente = await unSeulNombre(
        "SELECT COUNT(DISTINCT numero_piece) FROM ecriture_comptable "
        "WHERE journal_code = '${CodeJournal.ventes}'",
      );
      expect(
        piecesDeVente,
        ventes,
        reason:
            'Une vente sans écriture, c\'est du chiffre d\'affaires qui '
            'n\'arrive jamais en comptabilité.',
      );
    });

    test('le produit comptabilisé égale le total des ventes', () async {
      final ventes = await unSeulNombre(
        "SELECT COALESCE(SUM(total), 0) FROM ventes WHERE status <> 'Annulée'",
      );
      // Comptes de produits : classe 7.
      final produits = await unSeulNombre(
        "SELECT COALESCE(SUM(credit) - SUM(debit), 0) FROM ecriture_comptable "
        "WHERE numero_compte LIKE '7%'",
      );
      expect(produits, closeTo(ventes, 0.01));
    });
  });

  group('Tableau de Bord — les KPI viennent bien des données', () {
    test(
      'le chiffre d\'affaires égale la somme des ventes de la période',
      () async {
        final vm = TableauBordViewModel(TableauBordRepositoryDrift(db));
        await vm.charger({'goliaths', 'pintades'});

        final attendu = await unSeulNombre(
          "SELECT COALESCE(SUM(total), 0) FROM ventes "
          "WHERE status <> 'Annulée' "
          "AND date_vente >= ${vm.debutPeriode.millisecondsSinceEpoch ~/ 1000} "
          "AND date_vente <= ${vm.finPeriode.millisecondsSinceEpoch ~/ 1000}",
        );

        final ca = vm.indicateurs.firstWhere(
          (i) => i.libelle.toLowerCase().contains('affaires'),
        );
        final affiche = double.parse(
          ca.valeur.replaceAll(RegExp(r'[^0-9]'), ''),
        );
        expect(
          affiche,
          closeTo(attendu, 1),
          reason:
              'Le KPI du tableau de bord et la table des ventes doivent dire la '
              'même chose : c\'est la première comparaison que fait la Gérante.',
        );
        vm.dispose();
      },
    );

    test(
      'l\'effectif de chaque filière est celui de sa dernière fiche saisie',
      () async {
        final vm = TableauBordViewModel(TableauBordRepositoryDrift(db));
        await vm.charger({'goliaths', 'pintades'});

        for (final filiere in vm.filieres) {
          final attendu = await unSeulNombre(
            "SELECT COALESCE(effectif, 0) FROM fiche_journee "
            "WHERE espece = '${filiere.espece}' AND is_recorded = 1 "
            "ORDER BY date DESC LIMIT 1",
          );
          expect(
            filiere.effectif.toDouble(),
            attendu,
            reason:
                'Filière ${filiere.libelle} : le recensement du tableau de bord '
                'diverge de la fiche d\'élevage.',
          );
        }
        vm.dispose();
      },
    );
  });

  group('Inventaire — le stock reconstitué égale le stock réel', () {
    test('à la date du jour, le stock final est celui des intrants', () async {
      final inv = await InventaireRepositoryDrift(db).construire(
        debut: reference.subtract(const Duration(days: 29)),
        fin: reference,
      );

      for (final ligne in inv.intrants) {
        final reel = await unSeulNombre(
          "SELECT stock FROM intrants WHERE code = '${ligne.code}'",
        );
        expect(
          ligne.stockFinal,
          closeTo(reel, 0.001),
          reason:
              'L\'inventaire arrêté aujourd\'hui doit retrouver le stock '
              'courant de ${ligne.article} : sinon la reconstitution à rebours '
              'est fausse.',
        );
      }
    });

    test('les mouvements expliquent le stock, ligne à ligne', () async {
      final inv = await InventaireRepositoryDrift(db).construire(
        debut: reference.subtract(const Duration(days: 29)),
        fin: reference,
      );

      expect(
        inv.intrantsDesequilibres,
        isEmpty,
        reason:
            'Stock initial + entrées − sorties = stock final. C\'est la '
            'première égalité que vérifie un contrôleur.',
      );
    });

    test('le stock d\'un jour passé exclut les mouvements postérieurs', () async {
      final milieu = reference.subtract(const Duration(days: 15));
      final inv = await InventaireRepositoryDrift(
        db,
      ).construire(debut: milieu, fin: milieu);

      for (final ligne in inv.intrants) {
        final posterieurs = await unSeulNombre(
          "SELECT COALESCE(SUM(quantite), 0) FROM mouvements_intrant "
          "WHERE intrant_code = '${ligne.code}' "
          "AND horodatage >= ${milieu.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000}",
        );
        final actuel = await unSeulNombre(
          "SELECT stock FROM intrants WHERE code = '${ligne.code}'",
        );
        expect(ligne.stockFinal, closeTo(actuel - posterieurs, 0.001));
      }
    });
  });

  group('Couveuse — le TER se recoupe avec les lots', () {
    test('le TER moyen est bien pondéré par les œufs retenus', () async {
      final vm = CycleCouveuseViewModel(CycleCouveuseRepositoryDrift(db));
      await vm.charger();
      vm.definirReference(reference);

      final eclos = vm.tousLesLots
          .where((l) => l.poussinsEclos != null)
          .where((l) => !l.dateEclosionPrevue.isAfter(reference));
      if (eclos.isEmpty) return;

      final numerateur = eclos.fold<int>(0, (s, l) => s + l.poussinsEclos!);
      final denominateur = eclos.fold<int>(
        0,
        (s, l) => s + l.oeufsRetenusApresMirages,
      );

      expect(
        vm.tauxEclosionReelMoyen,
        closeTo(numerateur / denominateur * 100, 0.01),
        reason:
            'Une moyenne des taux, au lieu d\'un taux des totaux, ferait peser '
            'un lot de 12 œufs autant qu\'un lot de 300.',
      );
      vm.dispose();
    });

    test('les œufs retenus retirent bien les deux mirages', () async {
      final vm = CycleCouveuseViewModel(CycleCouveuseRepositoryDrift(db));
      await vm.charger();

      for (final lot in vm.tousLesLots) {
        expect(
          lot.oeufsRetenusApresMirages,
          lot.oeufsCharges -
              (lot.oeufsBlancsJ7 ?? 0) -
              (lot.oeufsGatesJ14 ?? 0),
        );
      }
      vm.dispose();
    });
  });

  group('Élevage — les effectifs se déduisent des mouvements', () {
    test('chaque journée découle de la précédente', () async {
      for (final espece in const ['goliaths', 'pintades']) {
        final jours = await db
            .customSelect(
              'SELECT date, achat, ne, vente, '
              'mort_cat1 + mort_cat2 + mort_cat3 AS morts, '
              'don_cat1 + don_cat2 + don_cat3 AS dons, effectif '
              'FROM fiche_journee WHERE espece = ? AND is_recorded = 1 '
              'ORDER BY date',
              variables: [Variable<String>(espece)],
            )
            .get();

        var precedent = 0;
        for (final j in jours) {
          final attendu =
              precedent +
              j.read<int>('achat') +
              j.read<int>('ne') -
              j.read<int>('vente') -
              j.read<int>('morts') -
              j.read<int>('dons');
          expect(
            j.read<int>('effectif'),
            attendu,
            reason:
                'Fiche $espece : l\'effectif d\'un jour doit se déduire de la '
                'veille et des mouvements. C\'est le bug historique n°1 du '
                'projet (Doc 05 §1).',
          );
          precedent = j.read<int>('effectif');
        }
      }
    });
  });

  group('Balance — les totaux se recoupent', () {
    test('total débit = total crédit sur la balance affichée', () async {
      final vm = ComptabiliteViewModel(ComptabiliteRepositoryDrift(db));
      await vm.charger();

      final lignes = vm.balance;
      expect(lignes, isNotEmpty);

      final debit = lignes.fold<double>(0, (s, l) => s + l.mouvementsDebit);
      final credit = lignes.fold<double>(0, (s, l) => s + l.mouvementsCredit);
      expect(debit, closeTo(credit, 0.01));
      vm.dispose();
    });
  });
}
