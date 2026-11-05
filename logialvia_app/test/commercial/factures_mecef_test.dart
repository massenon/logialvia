import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/commercial/data/repositories/factures_mecef_repository_drift.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/facture_mecef.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/commercial/domain/services/transmission_mecef.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';

/// La facturation normalisée MeCeF.
///
/// ## Ce que ces tests protègent
///
/// Une facture est une pièce fiscale : fausse, elle engage l'entreprise. Les
/// erreurs visées ici sont celles qui ne se voient pas à l'écran —
/// une taxe recalculée sur un montant déjà taxé, un avoir qui gonfle le chiffre
/// d'affaires au lieu de le réduire, une facture déclarée normalisée sans que
/// la DGI ait rien rendu.
void main() {
  late AppDatabase db;
  late FacturesMecefRepositoryDrift depot;
  late VentesRepositoryDrift ventes;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    depot = FacturesMecefRepositoryDrift(db);
    ventes = VentesRepositoryDrift(db, EventBus());
  });

  tearDown(() => db.close());

  /// Encaisse une vente réelle et renvoie sa référence.
  Future<String> unVente({double montant = 11800, double quantite = 2}) async {
    final produit = await db.select(db.produitsVendables).get();
    final p = produit.first;
    final resultat = await ventes.enregistrerVente(
      client: 'Client Comptant',
      mode: ModeReglement.especes,
      statut: StatutVente.payee,
      montantPaye: montant,
      panier: [
        LignePanier(
          produitId: p.id,
          nom: p.name,
          montantGlobal: montant,
          quantite: quantite,
          stockDisponible: p.stock,
          prixIndicatif: p.price,
          espece: p.espece,
          unite: p.unit,
        ),
      ],
    );
    return resultat.vente.reference;
  }

  group('Grille de taxe', () {
    test(
      'la grille est amorcée avec l\'exonération et le taux normal',
      () async {
        final groupes = await depot.groupesTaxe();
        expect(groupes.map((g) => g.code), containsAll(['A', 'B']));
        expect(groupes.firstWhere((g) => g.code == 'A').taux, 0);
        expect(groupes.firstWhere((g) => g.code == 'B').taux, 18);
      },
    );

    test('un produit est exonéré par défaut', () async {
      final produits = await db.select(db.produitsVendables).get();
      expect(
        produits.every((p) => p.groupeTaxe == 'A'),
        isTrue,
        reason:
            'Taxer par défaut ferait réclamer une TVA non due sur des '
            'produits agricoles, sans que personne ne relise le champ.',
      );
    });
  });

  group('Émission d\'une facture de vente', () {
    test('la facture reprend la vente et reste à transmettre', () async {
      final ref = await unVente(montant: 11800);
      final facture = await depot.emettrePourVente(venteRef: ref);

      expect(facture.reference, 'FV-${DateTime.now().year}-001');
      expect(facture.type, TypeFacture.vente);
      expect(facture.venteRef, ref);
      expect(facture.statut, StatutFacture.aTransmettre);
      expect(
        facture.estNormalisee,
        isFalse,
        reason: 'Sans code de la DGI, rien n\'est normalisé.',
      );
    });

    test('le total TTC facturé égale le montant encaissé', () async {
      // Le point le plus facile a rater : le panier est deja TTC. Recalculer
      // une taxe par-dessus ferait payer au client plus qu'il n'a regle.
      final ref = await unVente(montant: 11800);
      final facture = await depot.emettrePourVente(venteRef: ref);

      final vente = await (db.select(
        db.ventes,
      )..where((v) => v.ref.equals(ref))).getSingle();

      expect(facture.totalTtc, closeTo(vente.total, 0.01));
    });

    test(
      'sur un produit taxé, la taxe est extraite du montant, pas ajoutée',
      () async {
        final p = (await db.select(db.produitsVendables).get()).first;
        await (db.update(db.produitsVendables)..where((t) => t.id.equals(p.id)))
            .write(const ProduitsVendablesCompanion(groupeTaxe: Value('B')));

        final ref = await unVente(montant: 11800);
        final facture = await depot.emettrePourVente(venteRef: ref);

        expect(facture.totalTtc, closeTo(11800, 0.01));
        expect(facture.totalHt, closeTo(10000, 1));
        expect(facture.totalTaxe, closeTo(1800, 1));
      },
    );

    test('facturer deux fois la même vente est refusé', () async {
      final ref = await unVente();
      await depot.emettrePourVente(venteRef: ref);
      expect(
        () => depot.emettrePourVente(venteRef: ref),
        throwsA(isA<StateError>()),
      );
    });

    test('une vente annulée ne se facture pas', () async {
      final ref = await unVente();
      await ventes.annulerVente(reference: ref, motif: 'Erreur de saisie');
      expect(
        () => depot.emettrePourVente(venteRef: ref),
        throwsA(isA<StateError>()),
      );
    });

    test('la numérotation suit l\'ordre et l\'année', () async {
      final a = await depot.emettrePourVente(venteRef: await unVente());
      final b = await depot.emettrePourVente(venteRef: await unVente());
      final annee = DateTime.now().year;
      expect(a.reference, 'FV-$annee-001');
      expect(b.reference, 'FV-$annee-002');
    });
  });

  group('Avoir', () {
    test('l\'avoir reprend la facture et porte sa propre séquence', () async {
      final facture = await depot.emettrePourVente(venteRef: await unVente());
      final avoir = await depot.emettreAvoir(
        factureOrigine: facture.reference,
        motif: 'Erreur de facturation',
      );

      expect(avoir.type, TypeFacture.avoir);
      expect(avoir.reference, startsWith('FA-'));
      expect(avoir.origineRef, facture.reference);
      expect(avoir.totalTtc, closeTo(facture.totalTtc, 0.01));
      expect(avoir.motif, 'Erreur de facturation');
    });

    test('la facture d\'origine n\'est pas modifiée', () async {
      final facture = await depot.emettrePourVente(venteRef: await unVente());
      await depot.emettreAvoir(
        factureOrigine: facture.reference,
        motif: 'Retour',
      );

      final relue = await depot.parReference(facture.reference);
      expect(
        relue!.totalTtc,
        closeTo(facture.totalTtc, 0.01),
        reason:
            'Un avoir contrepasse, il ne réécrit pas — sinon la trace de '
            'l\'erreur disparaît avec l\'erreur.',
      );
      expect(relue.statut, facture.statut);
    });

    test('un avoir sans motif est refusé', () async {
      final facture = await depot.emettrePourVente(venteRef: await unVente());
      expect(
        () =>
            depot.emettreAvoir(factureOrigine: facture.reference, motif: '   '),
        throwsA(isA<StateError>()),
      );
    });

    test('on ne fait pas d\'avoir sur un avoir', () async {
      final facture = await depot.emettrePourVente(venteRef: await unVente());
      final avoir = await depot.emettreAvoir(
        factureOrigine: facture.reference,
        motif: 'Retour',
      );
      expect(
        () => depot.emettreAvoir(
          factureOrigine: avoir.reference,
          motif: 'Encore',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Normalisation', () {
    test(
      'une facture ne devient normalisée qu\'avec un code et un NIM',
      () async {
        final facture = await depot.emettrePourVente(venteRef: await unVente());
        expect(
          () => depot.normaliser(
            reference: facture.reference,
            codeMecef: '',
            nim: '',
          ),
          throwsA(isA<StateError>()),
        );

        await depot.normaliser(
          reference: facture.reference,
          codeMecef: 'ABC123',
          nim: 'NIM-001',
          compteur: '12/50',
        );
        final relue = await depot.parReference(facture.reference);
        expect(relue!.estNormalisee, isTrue);
        expect(relue.codeMecef, 'ABC123');
        expect(relue.compteur, '12/50');
      },
    );

    test(
      'un rejet garde la facture non normalisée et consigne la raison',
      () async {
        final facture = await depot.emettrePourVente(venteRef: await unVente());
        await depot.marquerRejetee(
          reference: facture.reference,
          erreur: 'IFU inconnu',
        );

        final relue = await depot.parReference(facture.reference);
        expect(relue!.statut, StatutFacture.rejetee);
        expect(relue.estNormalisee, isFalse);
        expect(relue.erreurTransmission, 'IFU inconnu');
      },
    );
  });

  group('Réponse e-MECeF', () {
    test('une réponse sans code est refusée', () {
      expect(
        () => ReponseMecef.depuisJson({'nim': 'NIM-001'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('une réponse complète est lue', () {
      final r = ReponseMecef.depuisJson({
        'codeMECeFDGI': 'XYZ',
        'nim': 'NIM-002',
        'counters': '3/40',
        'qrCode': 'https://verif.example/XYZ',
      });
      expect(r.codeMecef, 'XYZ');
      expect(r.nim, 'NIM-002');
      expect(r.compteur, '3/40');
      expect(r.lienVerification, 'https://verif.example/XYZ');
    });
  });

  group('Totaux par groupe', () {
    test('le récapitulatif cumule chaque groupe séparément', () {
      final facture = FactureMecef(
        reference: 'FV-2026-001',
        type: TypeFacture.vente,
        date: _uneDate,
        client: 'Client',
        statut: StatutFacture.aTransmettre,
        lignes: [
          const LigneFacture(
            designation: 'Poulet',
            quantite: 2,
            prixUnitaireHt: 1000,
            groupeTaxe: 'A',
            tauxTaxe: 0,
          ),
          const LigneFacture(
            designation: 'Provende',
            quantite: 1,
            prixUnitaireHt: 10000,
            groupeTaxe: 'B',
            tauxTaxe: 18,
          ),
        ],
      );

      final totaux = facture.totauxParGroupe;
      expect(totaux.length, 2);
      expect(totaux.first.groupe, 'A');
      expect(totaux.first.taxe, 0);
      expect(totaux.last.groupe, 'B');
      expect(totaux.last.taxe, closeTo(1800, 0.01));
      expect(facture.totalTtc, closeTo(13800, 0.01));
    });
  });
}

final DateTime _uneDate = DateTime(2026, 8, 20);
