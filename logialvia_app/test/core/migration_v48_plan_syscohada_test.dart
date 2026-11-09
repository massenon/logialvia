import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/comptabilite/data/migration/migration_plan_syscohada.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/domain/plan_syscohada.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';

/// Migration v48 — renumérotation de l'historique vers le plan SYSCOHADA révisé (`47p_` §8).
///
/// Jeu d'écritures de l'ANCIEN plan, chiffré à la main ; les soldes attendus par compte NOUVEAU
/// sont écrits en dur (pas recalculés par le code testé). Risques couverts : le croisement
/// 601↔602 et 613→622 (un compte reprend le numéro d'un autre), les frais de livraison (707 sans
/// centre → 7071) distincts des ventes de marchandises (707 → 701), le rejeu, l'interruption,
/// l'équilibre, les libellés, les demandes de plan en attente et les pièces refusées par un
/// serveur déjà migré.
void main() {
  late Directory dossier;
  late File fichier;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('logialvia_v48');
    fichier = File('${dossier.path}/logialvia.db');
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  const ancienPlan = <(String, String, String)>[
    ('31', 'Stocks de Marchandises (Commerce Annexe)', '3'),
    ('32', 'Stocks de Matières (Intrants Provende)', '3'),
    ('401', 'Fournisseurs', '4'),
    ('411', 'Clients', '4'),
    ('419', 'Clients — Avances Reçues', '4'),
    ('512', 'Banques — Mobile Money', '5'),
    ('531', 'Caisse', '5'),
    ('601', 'Achats de Matières (Intrants Provende)', '6'),
    ('602', 'Achats de Marchandises (Commerce Annexe)', '6'),
    ('622', 'Frais Vétérinaires', '6'),
    ('701', 'Ventes de Produits Avicoles', '7'),
    ('707', 'Ventes de Marchandises (Commerce Annexe)', '7'),
    ('101', 'Capital Social', '1'),
    ('121', 'Report à Nouveau', '1'),
    ('131', 'Résultat de l\'Exercice', '1'),
    ('613', 'Locations', '6'),
    ('616', 'Assurances', '6'),
    ('624', 'Transports', '6'),
    ('628', 'Charges Diverses de Gestion', '6'),
    ('111', 'Réserve Légale', '1'),
    ('118', 'Autres Réserves', '1'),
    ('129', 'Report à Nouveau — Solde Débiteur', '1'),
    ('139', 'Résultat Net : Perte', '1'),
    ('465', 'Associés — Dividendes à Payer', '4'),
    // Sous-comptes créés à la main : ils suivent leur compte (6011 sous 601 matières, 6021 sous 602).
    ('6011', 'Aliment démarrage', '6'),
    ('6021', 'Marchandises revente', '6'),
  ];

  /// (pièce, journal, vente_ref, [(compte, débit, crédit, axe)]) — numérotation de l'ANCIEN plan.
  const pieces =
      <(String, String, String?, List<(String, double, double, String?)>)>[
        (
          'P1',
          'OD',
          null,
          [('531', 1000000, 0, null), ('101', 0, 1000000, null)],
        ),
        (
          'P2',
          'VT',
          'V1',
          [('531', 600000, 0, null), ('701', 0, 600000, 'Goliaths')],
        ),
        (
          'P3',
          'VT',
          'V2',
          [('512', 90000, 0, null), ('707', 0, 90000, 'Commerce Annexe')],
        ),
        (
          'P4',
          'VT',
          'V3',
          [
            ('531', 7500, 0, null),
            ('701', 0, 6000, 'Pintades'),
            ('707', 0, 1500, null), // frais de livraison facturés : sans centre
          ],
        ),
        (
          'P5',
          'AC',
          null,
          [('601', 250000, 0, null), ('401', 0, 250000, null)],
        ),
        ('P6', 'AC', null, [('602', 40000, 0, null), ('401', 0, 40000, null)]),
        ('P7', 'AC', null, [('622', 10000, 0, null), ('531', 0, 10000, null)]),
        (
          'P8',
          'CA',
          null,
          [
            ('613', 20000, 0, null),
            ('616', 5000, 0, null),
            ('624', 3000, 0, null),
            ('628', 2000, 0, null),
            ('531', 0, 30000, null),
          ],
        ),
        ('P9', 'AN', null, [('531', 100, 0, null), ('101', 0, 100, null)]),
        (
          'P10',
          'AC',
          null,
          [('6011', 8000, 0, null), ('6021', 2000, 0, null), ('401', 0, 10000, null)],
        ),
      ];

  /// Soldes (débit, crédit) attendus par compte NOUVEAU — écrits à la main.
  const attendu = <String, (double, double)>{
    '571': (
      1607600,
      40000,
    ), // 1 000 000 + 600 000 + 7 500 + 100 / 10 000 + 30 000
    '552': (90000, 0), // ex-512 Mobile Money
    '702': (0, 606000), // ex-701 : 600 000 + 6 000
    '701': (0, 90000), // ex-707 marchandises
    '7071': (0, 1500), // ex-707 livraison
    '602': (250000, 0), // ex-601 matières
    '601': (40000, 0), // ex-602 marchandises
    '604': (10000, 0), // ex-622 vétérinaire
    '622': (20000, 0), // ex-613 locations
    '625': (5000, 0), // ex-616 assurances
    '618': (3000, 0), // ex-624 transports
    '658': (2000, 0), // ex-628 charges diverses
    '6021': (8000, 0), // ex-6011 : sous-compte de l'ancien 601 (matières) → sous-compte du 602
    '6011': (2000, 0), // ex-6021 : sous-compte de l'ancien 602 (marchandises) → du 601
    '401': (0, 300000),
    '101': (0, 1000100),
  };

  /// Une base v47 : schéma courant, plan et écritures de l'ancien plan, marqueur effacé.
  Future<void> baseV47({
    bool avecDemandes = true,
    bool avecConflit = true,
    int version = 47,
    Future<void> Function(AppDatabase db)? personnaliser,
  }) async {
    final db = AppDatabase.pourFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DELETE FROM plan_comptable');
    for (final (n, l, c) in ancienPlan) {
      await db.customStatement(
        'INSERT INTO plan_comptable (numero_compte, libelle, classe, archive) VALUES (?, ?, ?, 0)',
        [n, l, c],
      );
    }
    final annee = DateTime.now().year;
    await db.customStatement(
      'INSERT OR IGNORE INTO exercice_comptable (annee, is_cloture, sync_status, updated_at) '
      "VALUES (?, 0, 'synced', '2026-01-01T00:00:00.000000Z')",
      [annee],
    );
    var i = 0;
    for (final (piece, journal, vente, lignes) in pieces) {
      for (final (compte, d, c, axe) in lignes) {
        i++;
        final conflit = avecConflit && piece == 'P2' && compte == '531';
        await db.customStatement(
          'INSERT INTO ecriture_comptable (id, piece_id, exercice_annee, numero_compte, '
          'date_ecriture, debit, credit, libelle, journal_code, numero_piece, vente_ref, '
          'axe_analytique, sync_status, sync_motif, updated_at) '
          "VALUES (?, ?, ?, ?, 1788000000, ?, ?, 'Ligne', ?, ?, ?, ?, ?, ?, '2026-01-01T00:00:00.000000Z')",
          [
            'ligne-$i',
            'piece-$piece',
            annee,
            compte,
            d,
            c,
            journal,
            piece,
            vente,
            axe,
            conflit ? 'conflict' : 'synced',
            conflit
                ? "Ce poste utilise l'ancien plan comptable : mettez-le à jour"
                : null,
          ],
        );
      }
    }
    if (avecDemandes) {
      await db.customStatement(
        'INSERT INTO demandes_referentiel (id, type, cle, donnees, saisi_le, sync_status) '
        "VALUES ('d1', 'compte_comptable', '624', ?, '2026-01-01T00:00:00.000000Z', 'pending')",
        [
          jsonEncode({
            'numero_compte': '624',
            'libelle': 'Déplacements',
            'classe': '6',
            'archive': false,
          }),
        ],
      );
    }
    if (personnaliser != null) await personnaliser(db);
    await db.customStatement('PRAGMA application_id = 0');
    await db.customStatement('PRAGMA user_version = $version');
    await db.close();
  }

  Future<Map<String, (double, double)>> soldes(AppDatabase db) async {
    final l = await db
        .customSelect(
          'SELECT numero_compte AS c, SUM(debit) AS d, SUM(credit) AS k '
          'FROM ecriture_comptable GROUP BY numero_compte',
        )
        .get();
    return {
      for (final x in l)
        x.read<String>('c'): (x.read<double>('d'), x.read<double>('k')),
    };
  }

  test(
    'la balance est identique à l\'ancien numéro près, équilibrée avant et après',
    () async {
      await baseV47();
      final db = AppDatabase.pourFichier(fichier);
      final s = await soldes(db);
      expect(s, attendu);
      var d = 0.0;
      var k = 0.0;
      for (final v in s.values) {
        d += v.$1;
        k += v.$2;
      }
      // Avant : 1 000 000 + 600 000 + 90 000 + 7 500 + 250 000 + 40 000 + 10 000 + 30 000 + 100.
      expect(d, 2037600);
      expect(k, 2037600);
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM ecriture_comptable')
                .getSingle())
            .read<int>('n'),
        25,
        reason: 'aucune ligne perdue ni ajoutée',
      );
      await db.close();
    },
  );

  test(
    'le plan : comptes anciens retirés, plan officiel semé, 601↔602 et 613→622 croisés',
    () async {
      await baseV47();
      final db = AppDatabase.pourFichier(fichier);
      final plan = {
        for (final c
            in await db.customSelect('SELECT * FROM plan_comptable').get())
          c.read<String>('numero_compte'): c.read<String>('libelle'),
      };
      for (final ancien in ['531', '512', '613', '616']) {
        expect(
          plan.containsKey(ancien),
          isFalse,
          reason: '$ancien n\'existe plus',
        );
      }
      // 624 et 628 existent au plan officiel, avec un AUTRE sens que l'ancien (transports → 618).
      expect(plan['624'], 'Entretien, réparations et maintenance');
      expect(plan['628'], 'Frais de télécommunications');
      expect(plan['601'], 'Achats de marchandises');
      expect(plan['602'], 'Achats de matières premières et fournitures liées');
      expect(plan['622'], 'Locations et charges locatives');
      expect(
        plan['604'],
        'Achats stockés de matières et fournitures consommables',
      );
      expect(plan['571'], 'Caisse siège social');
      expect(plan['552'], 'Monnaie électronique : téléphone portable');
      expect(plan['702'], 'Ventes de produits finis');
      expect(plan['701'], 'Ventes de marchandises');
      expect(plan['7071'], 'Ports, emballages perdus et autres frais facturés');
      expect(plan['4431'], 'TVA facturée sur ventes');
      expect(plan['4452'], 'État, TVA récupérable sur achats');
      expect(plan['31'], 'Marchandises');
      expect(plan['401'], 'Fournisseurs, dettes en compte');
      for (final c in PlanSyscohada.comptes) {
        expect(
          plan[c.numero],
          c.libelle,
          reason: 'compte ${c.numero} officiel',
        );
      }
      await db.close();
    },
  );

  test(
    'les frais de livraison (707 sans centre) deviennent 7071, les marchandises 701',
    () async {
      await baseV47();
      final db = AppDatabase.pourFichier(fichier);
      final l = await db
          .customSelect(
            "SELECT numero_compte AS c, axe_analytique AS a FROM ecriture_comptable WHERE numero_piece IN ('P3', 'P4') AND numero_compte IN ('701', '7071')",
          )
          .get();
      expect(
        l.map((x) => '${x.read<String>('c')}|${x.read<String?>('a')}').toSet(),
        {'701|Commerce Annexe', '7071|null'},
      );
      await db.close();
    },
  );

  test(
    'rejouable : une seconde ouverture, ou un second appel, ne change rien',
    () async {
      await baseV47();
      final db = AppDatabase.pourFichier(fichier);
      expect(await soldes(db), attendu);
      expect(await MigrationPlanSyscohada(db).dejaMigre(), isTrue);
      expect(await MigrationPlanSyscohada(db).executer(), isNull);
      expect(
        await soldes(db),
        attendu,
        reason: 'un rejeu ne re-croise pas 601/602',
      );
      await db.close();

      // Remise de la version : le marqueur, lui, empêche de re-renuméroter.
      final b = AppDatabase.pourFichier(fichier);
      await b.customStatement('PRAGMA user_version = 47');
      await b.close();
      final c = AppDatabase.pourFichier(fichier);
      expect(await soldes(c), attendu);
      await c.close();
    },
  );

  test(
    'reprise après interruption : la transaction annule tout, puis la migration aboutit',
    () async {
      // user_version = 48 : l'ouverture ne migre pas ; on lance la migration à la main avec une
      // règle qui lève au milieu de la transaction.
      await baseV47(version: 48);
      final db = AppDatabase.pourFichier(fichier);
      expect(await MigrationPlanSyscohada(db).dejaMigre(), isFalse);
      final avant = await soldes(db);
      expect(avant['531'], isNotNull);

      await expectLater(
        MigrationPlanSyscohada(db).executer(
          regles: [
            // Première règle valide : ses lignes passent par un numéro temporaire…
            (
              ancien: '531',
              nouveau: '571',
              libelleAncien: 'Caisse',
              fraisLivraisonSeulement: false,
            ),
            // … la seconde lève au milieu de la transaction : tout doit être annulé.
            (
              ancien: '512',
              nouveau: '',
              libelleAncien: 'Banques — Mobile Money',
              fraisLivraisonSeulement: false,
            ),
          ],
        ),
        throwsA(anything),
      );
      expect(await soldes(db), avant, reason: 'rien n\'a bougé après l\'échec');
      expect(await MigrationPlanSyscohada(db).dejaMigre(), isFalse);

      final rapport = await MigrationPlanSyscohada(db).executer();
      expect(rapport, isNotNull);
      expect(rapport!.lignesRenumerotees, greaterThan(0));
      expect(await soldes(db), attendu);
      await db.close();
    },
  );

  test(
    'demandes de plan en attente renumérotées ; pièces refusées pour ancien plan relancées',
    () async {
      await baseV47();
      final db = AppDatabase.pourFichier(fichier);
      final d = await db
          .customSelect(
            "SELECT cle, donnees FROM demandes_referentiel WHERE id = 'd1'",
          )
          .getSingle();
      expect(d.read<String>('cle'), '618');
      final donnees =
          jsonDecode(d.read<String>('donnees')) as Map<String, dynamic>;
      expect(donnees['numero_compte'], '618');
      expect(donnees['plan_version'], PlanSyscohada.version);
      final conflit = await db
          .customSelect(
            "SELECT sync_status AS s, sync_motif AS m FROM ecriture_comptable WHERE id = 'ligne-3'",
          )
          .getSingle();
      expect(conflit.read<String>('s'), 'pending');
      expect(conflit.read<String?>('m'), isNull);
      await db.close();
    },
  );

  test(
    'libellé personnalisé reporté sur le nouveau numéro, y compris au croisement',
    () async {
      await baseV47(
        personnaliser: (b) => b.customStatement(
          "UPDATE plan_comptable SET libelle = 'Aliments volaille' WHERE numero_compte = '601'",
        ),
      );
      final db = AppDatabase.pourFichier(fichier);
      final plan = {
        for (final c
            in await db.customSelect('SELECT * FROM plan_comptable').get())
          c.read<String>('numero_compte'): c.read<String>('libelle'),
      };
      expect(
        plan['602'],
        'Aliments volaille',
        reason: 'la matière a changé de numéro, pas de nom',
      );
      expect(plan['601'], 'Achats de marchandises');
      await db.close();
    },
  );

  test(
    'états financiers après migration : mêmes montants que le calcul fait à la main sur l\'ancien plan',
    () async {
      await baseV47();
      final db = AppDatabase.pourFichier(fichier);
      final vm = ComptabiliteViewModel(ComptabiliteRepositoryDrift(db));
      await vm.charger();
      // Produits : 606 000 (702) + 90 000 (701) + 1 500 (7071) = 697 500.
      // Charges  : 250 000 + 40 000 + 10 000 + 20 000 + 5 000 + 3 000 + 2 000 = 330 000.
      expect(vm.resultatNet, 357500);
      final cr = {
        for (final p in vm.compteResultat.postes) p.libelle: p.montant,
      };
      expect(cr['Ventes de Marchandises'], 90000);
      expect(cr['Achats de Marchandises Consommés'], -42000);
      expect(cr['MARGE COMMERCIALE'], 48000);
      expect(cr['Ventes de Produits Avicoles'], 606000);
      expect(cr['RÉSULTAT NET DE L\'EXERCICE'], 357500);
      // Bilan : trésorerie 1 567 600 (571) + 90 000 (552) = 1 657 600 ;
      // capital 1 000 100 + fournisseurs 300 000 + résultat 357 500 = 1 657 600.
      expect(vm.bilan.estEquilibre, isTrue);
      expect(vm.bilan.totalActif, 1657600);
      expect(vm.tafire.tresorerieCloture, 1657600);
      await db.close();
    },
  );

  test(
    'base neuve : marquée migrée, aucun ancien numéro à convertir',
    () async {
      final db = AppDatabase.pourFichier(fichier);
      await db.customSelect('SELECT 1').get();
      expect(await MigrationPlanSyscohada(db).dejaMigre(), isTrue);
      await db.close();
    },
  );

  group('table de correspondance (fonction pure)', () {
    test('chaque règle, numéro par numéro', () {
      const attenduRegles = {
        '531': '571',
        '512': '552',
        '601': '602',
        '602': '601',
        '622': '604',
        '613': '622',
        '616': '625',
        '624': '618',
        '628': '658',
        '701': '702',
        '707': '701',
      };
      attenduRegles.forEach((ancien, nouveau) {
        expect(
          MigrationPlanSyscohada.nouveauNumero(ancien, axe: 'X', venteRef: 'V'),
          nouveau,
          reason: 'ancien $ancien',
        );
      });
      expect(
        MigrationPlanSyscohada.nouveauNumero('707', axe: null, venteRef: 'V'),
        '7071',
      );
      expect(
        MigrationPlanSyscohada.nouveauNumero('707', axe: null, venteRef: null),
        '701',
        reason:
            'une OD manuelle sur 707 sans pièce de vente reste une vente de marchandises',
      );
      // Les sous-comptes suivent leur compte (jamais le frais de livraison : exact 707 seulement).
      expect(MigrationPlanSyscohada.nouveauNumero('6011'), '6021');
      expect(MigrationPlanSyscohada.nouveauNumero('6021'), '6011');
      expect(MigrationPlanSyscohada.nouveauNumero('5311'), '5711');
      expect(MigrationPlanSyscohada.nouveauNumero('6241'), '6181');
      expect(MigrationPlanSyscohada.nouveauNumero('7071', axe: null, venteRef: 'V'), '7011');
      for (final inchange in [
        '31',
        '32',
        '401',
        '411',
        '419',
        '101',
        '111',
        '118',
        '121',
        '129',
        '131',
        '139',
        '465',
        '231',
      ]) {
        expect(MigrationPlanSyscohada.nouveauNumero(inchange), inchange);
      }
    });
  });
}
