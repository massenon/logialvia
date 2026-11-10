import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/livraison.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';

/// Jeu d'écritures de VENTE chiffré à la main, **commun au poste et au web**.
///
/// Le même jeu est rejoué côté serveur par
/// `logialvia_laravel/tests/Feature/Web/EcrituresAutomatiquesVentesTest.php` : si le web et
/// le poste s'écartent, l'un des deux tests rougit. (Doc `47a_COMMERCE_PARITE.md` §3.)
///
/// Chaque ligne : `compte, débit, crédit, centre analytique`.
typedef Ligne = (String, double, double, String?);

void main() {
  late AppDatabase db;
  late EventBus bus;
  late VentesRepositoryDrift repository;
  late List<ProduitVendable> catalogue;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    bus = EventBus();
    repository = VentesRepositoryDrift(db, bus);
    catalogue = await repository.chargerCatalogue();
  });

  tearDown(() async {
    bus.dispose();
    await db.close();
  });

  ProduitVendable produit(String nom) =>
      catalogue.firstWhere((p) => p.nom == nom);

  LignePanier ligne(String nom, double qte, double montant) {
    final p = produit(nom);
    return LignePanier(
      produitId: p.id,
      nom: p.nom,
      montantGlobal: montant,
      quantite: qte,
      stockDisponible: p.stock,
      prixIndicatif: p.prix,
      espece: p.espece,
      unite: p.unite,
    );
  }

  /// Lignes d'une pièce, triées par (débit décroissant, compte, crédit décroissant).
  Future<List<Ligne>> piece(String numero) async {
    final lignes = await db
        .customSelect(
          'SELECT numero_compte, debit, credit, axe_analytique '
          'FROM ecriture_comptable WHERE numero_piece = ?',
          variables: [Variable.withString(numero)],
        )
        .get();
    final resultat = [
      for (final l in lignes)
        (
          l.read<String>('numero_compte'),
          l.read<double>('debit'),
          l.read<double>('credit'),
          l.read<String?>('axe_analytique'),
        ),
    ];
    resultat.sort((a, b) {
      final d = b.$2.compareTo(a.$2);
      if (d != 0) return d;
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : (b.$3.compareTo(a.$3));
    });
    return resultat;
  }

  /// Solde (débit − crédit) de l'ensemble des écritures d'un compte.
  Future<double> solde(String compte) async {
    final l = await db
        .customSelect(
          'SELECT COALESCE(SUM(debit - credit), 0) AS s '
          'FROM ecriture_comptable WHERE numero_compte = ?',
          variables: [Variable.withString(compte)],
        )
        .getSingle();
    return l.read<double>('s');
  }

  Future<double> ecartPiece(String numero) async {
    final l = await db
        .customSelect(
          'SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS e '
          'FROM ecriture_comptable WHERE numero_piece = ?',
          variables: [Variable.withString(numero)],
        )
        .getSingle();
    return l.read<double>('e');
  }

  group('Jeu commun poste / web — ventes', () {
    test('A. comptant en espèces : 571 D / 702 C (centre Goliaths)', () async {
      final r = await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 12000,
        panier: [ligne('Goliath mature', 2, 12000)],
      );
      expect(await piece(r.vente.reference), [
        ('571', 12000.0, 0.0, null),
        ('702', 0.0, 12000.0, 'Goliaths'),
      ]);
    });

    test(
      'B. avance en Mobile Money, trois centres : 552 + 411 / 702 x2 + 701',
      () async {
        final r = await repository.enregistrerVente(
          client: 'AGOSSOU Prudence',
          mode: ModeReglement.mobileMoney,
          statut: StatutVente.avance,
          montantPaye: 4000,
          ligneMobileMoney: '+229 97 00 00 00',
          panier: [
            ligne('Goliath mature', 1, 6000),
            ligne('Pintade mature', 1, 6500),
            ligne('Tee-shirt enfant', 3, 3000),
          ],
        );
        expect(await piece(r.vente.reference), [
          ('411', 11500.0, 0.0, null),
          ('552', 4000.0, 0.0, null),
          ('701', 0.0, 3000.0, 'Commerce Annexe'),
          ('702', 0.0, 6500.0, 'Pintades'),
          ('702', 0.0, 6000.0, 'Goliaths'),
        ]);
      },
    );

    test('C. livraison facturée : les frais sont un produit accessoire (7071), la pièce '
        'est ÉQUILIBRÉE', () async {
      final r = await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 7500,
        panier: [ligne('Goliath mature', 1, 6000)],
        livraison: const Livraison(mode: ModeLivraison.facturee, frais: 1500),
      );
      expect(await ecartPiece(r.vente.reference), 0);
      expect(await piece(r.vente.reference), [
        ('571', 7500.0, 0.0, null),
        ('702', 0.0, 6000.0, 'Goliaths'),
        ('7071', 0.0, 1500.0, null),
      ]);
    });

    test('D. un recouvrement supérieur au reste dû est borné AUSSI en '
        'comptabilité', () async {
      final r = await repository.enregistrerVente(
        client: 'AGOSSOU Prudence',
        mode: ModeReglement.especes,
        statut: StatutVente.avance,
        montantPaye: 3500,
        panier: [ligne('Goliath mature', 2, 12000)],
      );
      await repository.enregistrerPaiement(
        reference: r.vente.reference,
        montant: 999999,
      );
      // Reste dû : 12 000 − 3 500 = 8 500, pas 999 999.
      expect(await piece('REG-${r.vente.reference}'), [
        ('571', 8500.0, 0.0, null),
        ('411', 0.0, 8500.0, null),
      ]);
      expect(
        await solde('411'),
        0,
        reason: 'créance soldée : 8 500 + 3 500 = 12 000',
      );
    });

    test(
      'E. recouvrement partiel puis annulation : tout est contrepassé',
      () async {
        final r = await repository.enregistrerVente(
          client: 'AGOSSOU Prudence',
          mode: ModeReglement.mobileMoney,
          statut: StatutVente.avance,
          montantPaye: 4000,
          ligneMobileMoney: '+229 97 00 00 00',
          panier: [
            ligne('Goliath mature', 1, 6000),
            ligne('Pintade mature', 1, 6500),
            ligne('Tee-shirt enfant', 3, 3000),
          ],
        );
        await repository.enregistrerPaiement(
          reference: r.vente.reference,
          montant: 2000,
        );
        await repository.annulerVente(
          reference: r.vente.reference,
          motif: 'Client non honoré',
        );
        // Payé au moment de l'annulation : 4 000 + 2 000 ; reste dû : 15 500 − 6 000.
        expect(await piece('ANN-${r.vente.reference}'), [
          ('702', 6500.0, 0.0, 'Pintades'),
          ('702', 6000.0, 0.0, 'Goliaths'),
          ('701', 3000.0, 0.0, 'Commerce Annexe'),
          ('411', 0.0, 9500.0, null),
          ('552', 0.0, 6000.0, null),
        ]);
        for (final compte in ['411', '552', '702', '701']) {
          expect(await solde(compte), 0, reason: 'compte $compte soldé');
        }
      },
    );

    test('F. annulation d\'une vente avec livraison facturée : les frais '
        'sont repris', () async {
      final r = await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 7500,
        panier: [ligne('Goliath mature', 1, 6000)],
        livraison: const Livraison(mode: ModeLivraison.facturee, frais: 1500),
      );
      await repository.annulerVente(
        reference: r.vente.reference,
        motif: 'Erreur de saisie',
      );
      expect(await ecartPiece('ANN-${r.vente.reference}'), 0);
      for (final compte in ['571', '702', '7071']) {
        expect(await solde(compte), 0, reason: 'compte $compte soldé');
      }
    });

    // --- TVA ventilée (`47p_` §6) : les prix du catalogue sont TTC, la TVA s'en extrait au
    // taux du groupe de taxe du produit (A exonéré, B 18 %). Calculs faits à la main, rejoués à
    // l'identique côté web (`EcrituresAutomatiquesVentesTest`).
    Future<void> taxer(String nom, String groupe) => (db.update(
      db.produitsVendables,
    )..where((p) => p.id.equals(produit(nom).id))).write(
      ProduitsVendablesCompanion(groupeTaxe: Value(groupe)),
    );

    test('G. produit taxable à 18 % : 11 800 TTC = 10 000 HT + 1 800 de TVA '
        'collectée (4431)', () async {
      await taxer('Tee-shirt enfant', 'B');
      final r = await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 11800,
        panier: [ligne('Tee-shirt enfant', 2, 11800)],
      );
      expect(await piece(r.vente.reference), [
        ('571', 11800.0, 0.0, null),
        ('4431', 0.0, 1800.0, null),
        ('701', 0.0, 10000.0, 'Commerce Annexe'),
      ]);
      expect(await ecartPiece(r.vente.reference), 0);
    });

    test('H. panier mixte exonéré + taxable, livraison facturée au taux unique '
        'du panier taxable : 4431 et 4432 distinctes', () async {
      await taxer('Tee-shirt enfant', 'B');
      final r = await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 12980,
        panier: [ligne('Tee-shirt enfant', 2, 11800)],
        livraison: const Livraison(mode: ModeLivraison.facturee, frais: 1180),
      );
      // 11 800 → HT 10 000 + TVA 1 800 ; livraison 1 180 → HT 1 000 + TVA 180.
      expect(await piece(r.vente.reference), [
        ('571', 12980.0, 0.0, null),
        ('4431', 0.0, 1800.0, null),
        ('4432', 0.0, 180.0, null),
        ('701', 0.0, 10000.0, 'Commerce Annexe'),
        ('7071', 0.0, 1000.0, null),
      ]);
      expect(await ecartPiece(r.vente.reference), 0);
    });

    test('I. panier mixte (exonéré + taxable) : livraison exonérée, TVA sur la '
        'seule ligne taxable', () async {
      await taxer('Tee-shirt enfant', 'B');
      final r = await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 19300,
        panier: [
          ligne('Goliath mature', 1, 6000),
          ligne('Tee-shirt enfant', 2, 11800),
        ],
        livraison: const Livraison(mode: ModeLivraison.facturee, frais: 1500),
      );
      expect(await piece(r.vente.reference), [
        ('571', 19300.0, 0.0, null),
        ('4431', 0.0, 1800.0, null),
        ('701', 0.0, 10000.0, 'Commerce Annexe'),
        ('702', 0.0, 6000.0, 'Goliaths'),
        ('7071', 0.0, 1500.0, null),
      ]);
    });

    test('J. annulation d\'une vente taxable : la TVA collectée est reprise, le '
        'résultat ne la contient jamais', () async {
      await taxer('Tee-shirt enfant', 'B');
      final r = await repository.enregistrerVente(
        client: 'Client Comptant',
        mode: ModeReglement.especes,
        statut: StatutVente.payee,
        montantPaye: 11800,
        panier: [ligne('Tee-shirt enfant', 2, 11800)],
      );
      expect(await solde('4431'), -1800);
      await repository.annulerVente(
        reference: r.vente.reference,
        motif: 'Erreur',
      );
      expect(await ecartPiece('ANN-${r.vente.reference}'), 0);
      for (final compte in ['571', '701', '4431']) {
        expect(await solde(compte), 0, reason: 'compte $compte soldé');
      }
    });

    test('K. règlement d\'une créance taxable : la TVA reste facturée à la vente, '
        'le recouvrement ne touche que 411 et la trésorerie', () async {
      await taxer('Tee-shirt enfant', 'B');
      final r = await repository.enregistrerVente(
        client: 'AGOSSOU Prudence',
        mode: ModeReglement.especes,
        statut: StatutVente.avance,
        montantPaye: 3800,
        panier: [ligne('Tee-shirt enfant', 2, 11800)],
      );
      expect(await piece(r.vente.reference), [
        ('411', 8000.0, 0.0, null),
        ('571', 3800.0, 0.0, null),
        ('4431', 0.0, 1800.0, null),
        ('701', 0.0, 10000.0, 'Commerce Annexe'),
      ]);
      await repository.enregistrerPaiement(
        reference: r.vente.reference,
        montant: 8000,
      );
      expect(await solde('411'), 0);
      expect(await solde('4431'), -1800);
    });
  });
}
