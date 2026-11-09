import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import 'package:logialvia_app/approvisionnement/data/sync/table_achats_poste.dart';
import 'package:logialvia_app/approvisionnement/domain/entities/approvisionnement.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';

/// Parité achats au web : ce que le poste doit savoir absorber d'une commande saisie au
/// web (référence `ACH-WEB-…`, mode « Crédit », commande modifiée) et un défaut du poste
/// trouvé en portant les écritures d'achat en PHP (règlement supérieur au reste dû).
void main() {
  late AppDatabase db;
  late ApprovisionnementRepositoryDrift appro;
  late TableAchatsPoste table;

  const uuidAchat = '11111111-1111-4111-8111-111111111111';
  const uuidLigneA = '22222222-2222-4222-8222-222222222222';
  const uuidLigneB = '33333333-3333-4333-8333-333333333333';

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    appro = ApprovisionnementRepositoryDrift(db);
    table = TableAchatsPoste(db);
  });

  tearDown(() async => db.close());

  Future<String> fournisseur() async =>
      (await appro.creerFournisseur(nom: 'Maïs Local')).id;

  Map<String, dynamic> achatWeb(
    String fournisseurId, {
    String statut = 'Commandé',
    String mode = 'Crédit',
    String? updatedAt,
    List<Map<String, dynamic>>? lignes,
    num total = 6000,
    num paye = 0,
    String reference = 'ACH-WEB-2026-001',
  }) => {
    'id': uuidAchat,
    'reference': reference,
    'fournisseur_id': fournisseurId,
    'date_achat': '2026-11-09T10:00:00.000000Z',
    'statut': statut,
    'total': total,
    'paye': paye,
    'mode': mode,
    'echeance': '2026-11-30T11:00:00.000000Z',
    'updated_at': updatedAt ?? '2026-11-09T10:00:00.000000Z',
    'lignes':
        lignes ??
        [
          {
            'id': uuidLigneA,
            'intrant_code': 'INT-001',
            'nom': 'Maïs',
            'qte': 10,
            'pu_achat': 600,
          },
        ],
  };

  Map<String, dynamic> ligneSoja({String code = 'INT-002'}) => {
    'id': uuidLigneB,
    'intrant_code': code,
    'nom': 'Soja',
    'qte': 8,
    'pu_achat': 500,
  };

  Future<List<LigneAchatRow>> lignesDe(String ref) =>
      (db.select(db.lignesAchat)..where((l) => l.achatRef.equals(ref))).get();

  group('commande saisie au web', () {
    test(
      'la référence ACH-WEB-AAAA-NNN et le mode Crédit sont acceptés',
      () async {
        final f = await fournisseur();

        final r = await table.absorber([achatWeb(f)]);

        expect(r.absorbees, 1);
        expect(r.refusees, 0);
        final a = await (db.select(
          db.achats,
        )..where((a) => a.ref.equals('ACH-WEB-2026-001'))).getSingle();
        expect(a.mode, 'Crédit');
        expect(a.echeance, isNotNull);
        expect(a.syncStatus, 'synced');
      },
    );

    test('une référence « ACH-XYZ-… » reste refusée', () async {
      final f = await fournisseur();
      final r = await table.absorber([
        achatWeb(f, reference: 'ACH-XYZ-2026-001'),
      ]);
      expect(r.refusees, 1);
    });

    test(
      'commande modifiée au web : tant qu\'elle est « Commandé », ses lignes sont remplacées',
      () async {
        final f = await fournisseur();
        await table.absorber([achatWeb(f)]);

        final r = await table.absorber([
          achatWeb(
            f,
            total: 4000,
            updatedAt: '2026-11-09T11:00:00.000000Z',
            lignes: [ligneSoja()],
          ),
        ]);

        expect(r.absorbees, 1);
        final lignes = await lignesDe('ACH-WEB-2026-001');
        expect(lignes, hasLength(1), reason: 'l\'ancienne ligne est supprimée');
        expect(lignes.single.id, uuidLigneB);
        expect(lignes.single.intrantCode, 'INT-002');
        expect(lignes.single.qte, 8);
        expect((await db.select(db.achats).getSingle()).total, 4000);
      },
    );

    test('une modification plus ANCIENNE ne remplace rien', () async {
      final f = await fournisseur();
      await table.absorber([
        achatWeb(f, updatedAt: '2026-11-09T12:00:00.000000Z'),
      ]);

      await table.absorber([
        achatWeb(
          f,
          total: 1,
          updatedAt: '2026-11-09T09:00:00.000000Z',
          lignes: [ligneSoja()],
        ),
      ]);

      expect((await lignesDe('ACH-WEB-2026-001')).single.id, uuidLigneA);
    });

    test(
      'un achat déjà Livré ici : ses lignes ne bougent plus (le stock en dépend)',
      () async {
        final f = await fournisseur();
        await table.absorber([achatWeb(f, statut: 'Livré')]);

        await table.absorber([
          achatWeb(
            f,
            statut: 'Annulé',
            updatedAt: '2026-11-09T11:00:00.000000Z',
            lignes: [ligneSoja()],
          ),
        ]);

        expect((await lignesDe('ACH-WEB-2026-001')).single.id, uuidLigneA);
        expect((await db.select(db.achats).getSingle()).statut, 'Annulé');
      },
    );

    test(
      'une modification qui porte un intrant inconnu est refusée, rien n\'est perdu',
      () async {
        final f = await fournisseur();
        await table.absorber([achatWeb(f)]);

        final r = await table.absorber([
          achatWeb(
            f,
            updatedAt: '2026-11-09T11:00:00.000000Z',
            lignes: [ligneSoja(code: 'INT-999')],
          ),
        ]);

        expect(r.refusees, 1);
        expect((await lignesDe('ACH-WEB-2026-001')).single.id, uuidLigneA);
      },
    );

    test(
      'absorber une commande du web ne touche NI stock, NI PMP, NI journal, NI écriture',
      () async {
        final f = await fournisseur();
        final avant = (await appro.chargerIntrants()).firstWhere(
          (i) => i.code == 'INT-001',
        );

        await table.absorber([achatWeb(f, statut: 'Livré')]);

        final apres = (await appro.chargerIntrants()).firstWhere(
          (i) => i.code == 'INT-001',
        );
        expect(apres.stock, avant.stock);
        expect(apres.pmp, avant.pmp);
        expect(await db.select(db.mouvementsIntrant).get(), isEmpty);
        expect(await db.select(db.ecritureComptable).get(), isEmpty);
      },
    );
  });

  group('règlement d\'une dette fournisseur', () {
    LignePanierAchat panier(double qte, double pu) => LignePanierAchat(
      intrantCode: 'INT-001',
      nom: 'Maïs',
      quantite: qte,
      prixUnitaire: pu,
      unite: 'kg',
    );

    Future<double> somme(String compte, {required bool debit}) async {
      final l = await (db.select(
        db.ecritureComptable,
      )..where((e) => e.numeroCompte.equals(compte))).get();
      return l.fold<double>(0, (s, e) => s + (debit ? e.debit : e.credit));
    }

    test(
      'un versement supérieur au reste dû : l\'écriture porte le montant VERSÉ (401 reste à zéro)',
      () async {
        final f = await fournisseur();
        final achat = await appro.enregistrerAchat(
          fournisseurId: f,
          mode: 'Espèces',
          montantPaye: 0,
          livree: true,
          panier: [panier(10, 600)], // 6 000 dus
        );

        await appro.reglerAchat(reference: achat.reference, montant: 999999);

        expect(await somme('401', debit: false), 6000);
        expect(await somme('401', debit: true), 6000);
        expect(await somme('531', debit: false), 6000);
      },
    );

    test('régler une dette déjà soldée n\'écrit rien', () async {
      final f = await fournisseur();
      final achat = await appro.enregistrerAchat(
        fournisseurId: f,
        mode: 'Espèces',
        montantPaye: 6000,
        livree: true,
        panier: [panier(10, 600)],
      );
      final avant = (await db.select(db.ecritureComptable).get()).length;

      await appro.reglerAchat(reference: achat.reference, montant: 500);

      expect((await db.select(db.ecritureComptable).get()).length, avant);
    });

    test('une commande annulée ne se règle plus', () async {
      final f = await fournisseur();
      final achat = await appro.enregistrerAchat(
        fournisseurId: f,
        mode: 'Espèces',
        montantPaye: 0,
        livree: false,
        panier: [panier(10, 600)],
      );
      await (db.update(db.achats)..where((a) => a.ref.equals(achat.reference)))
          .write(const AchatsCompanion(statut: Value(StatutAchat.annule)));

      expect(
        () => appro.reglerAchat(reference: achat.reference, montant: 100),
        throwsStateError,
      );
    });
  });
}
