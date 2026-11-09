import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/data/seed/plan_comptable_seeder.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

/// Écrans du module F6 — ce que le ViewModel doit garantir pour qu'aucun des
/// 9 écrans n'affiche une valeur inventée ou divergente.
void main() {
  late AppDatabase db;
  late ComptabiliteViewModel vm;
  late int annee;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    vm = ComptabiliteViewModel(ComptabiliteRepositoryDrift(db));
    await vm.charger();
    annee = vm.exercice;
  });

  tearDown(() async => db.close());

  /// Enregistre une dépense comme le fait l'écran Saisie des Dépenses.
  Future<String> depense({
    required String compteCharge,
    required String compteReglement,
    required double montant,
    String libelle = 'Transport livraison',
    int mois = 6,
  }) async {
    final piece = vm.prochainNumeroPiece('DEP');
    final resultat = await vm.enregistrerPiece(
      date: DateTime(annee, mois, 12),
      journalCode: 'CA',
      numeroPiece: piece,
      lignes: [
        LigneAEcrire(
          numeroCompte: compteCharge,
          debit: montant,
          credit: 0,
          libelle: libelle,
        ),
        LigneAEcrire(
          numeroCompte: compteReglement,
          debit: 0,
          credit: montant,
          libelle: libelle,
        ),
      ],
    );
    expect(resultat, isA<Succes<void>>());
    return piece;
  }

  group('Plan comptable — le socle couvre les écrans qui s\'en servent', () {
    test('les 4 comptes de charges de saisie-depenses.html existent, alors '
        'que plan-comptable.html ne les listait pas', () async {
      final numeros = vm.plan.map((c) => c.numero).toSet();
      for (final compte in ['613', '616', '624', '628']) {
        expect(
          numeros,
          contains(compte),
          reason:
              'Sans $compte, la clé étrangère de ECRITURE_COMPTABLE rejette '
              'toute dépense de cette catégorie.',
        );
      }
    });

    test(
      'le plan d\'une base déjà installée est complété, pas réécrasé',
      () async {
        // Simule une base creee avant l'ajout des comptes de depenses.
        await db.customStatement(
          "DELETE FROM plan_comptable WHERE numero_compte IN "
          "('613','616','624','628')",
        );
        await ComptabiliteRepositoryDrift(db).modifierCompte(
          numero: '531',
          libelle: 'Caisse principale (renommée par la Gérante)',
          classe: '5',
        );

        await PlanComptableSeeder(db).completerComptesManquants();
        await vm.charger();

        final numeros = vm.plan.map((c) => c.numero).toSet();
        expect(numeros, containsAll(['613', '616', '624', '628']));

        final caisse = vm.plan.firstWhere((c) => c.numero == '531');
        expect(
          caisse.libelle,
          'Caisse principale (renommée par la Gérante)',
          reason:
              'Un compte renommé ne doit jamais être réécrasé par le socle.',
        );
      },
    );

    test('un compte mouvementé ne peut plus changer de classe', () async {
      await depense(
        compteCharge: '624',
        compteReglement: '531',
        montant: 12000,
      );

      final resultat = await vm.modifierCompte(
        numero: '624',
        libelle: 'Transports',
        classe: '6',
      );
      expect(resultat, isA<Succes<void>>(), reason: 'Même classe : autorisé.');

      // Changer la classe reclasserait retroactivement l'ecriture d'un poste
      // du bilan a un autre.
      final refus = await vm.modifierCompte(
        numero: '624',
        libelle: 'Transports',
        classe: '7',
      );
      expect(refus, isA<Echec<void>>());
    });

    test('le numéro doit rester cohérent avec sa classe', () async {
      final resultat = await vm.creerCompte(
        numero: '645',
        libelle: 'Charges de personnel',
        classe: '7',
      );
      expect(resultat, isA<Echec<void>>());
    });
  });

  group('Numérotation des pièces', () {
    test('la séquence repart de 1 et ne double jamais un numéro', () async {
      expect(vm.prochainNumeroPiece('DEP'), 'DEP-$annee-0001');

      await depense(
        compteCharge: '624',
        compteReglement: '531',
        montant: 12000,
      );
      expect(vm.prochainNumeroPiece('DEP'), 'DEP-$annee-0002');

      // Les prefixes sont independants.
      expect(vm.prochainNumeroPiece('OD'), 'OD-$annee-0001');
    });
  });

  group('Dépenses — reconstruites depuis les écritures, jamais stockées à '
      'part', () {
    test(
      'une dépense saisie apparaît aussitôt au Journal et à la Balance',
      () async {
        await depense(
          compteCharge: '628',
          compteReglement: '531',
          montant: 15000,
          libelle: 'Entretien groupe électrogène',
        );

        expect(vm.depenses, hasLength(1));
        expect(vm.depenses.first.libelle, 'Entretien groupe électrogène');
        expect(vm.depenses.first.montant, 15000);
        expect(vm.depenses.first.categorie, contains('628'));

        // Le meme fait comptable, vu par les autres ecrans.
        expect(vm.ecritures, hasLength(2));
        expect(vm.totalDebitJournal, 15000);
        expect(vm.totalCreditJournal, 15000);
        expect(vm.balanceEstEquilibree, isTrue);
        expect(vm.totalCharges, 15000);
        expect(vm.resultatNet, -15000);
      },
    );

    test(
      'une charge réglée par 401 reste « En attente », pas « Payée »',
      () async {
        await depense(
          compteCharge: '613',
          compteReglement: '401',
          montant: 30000,
          libelle: 'Location entrepôt',
        );

        expect(vm.depenses.single.payee, isFalse);
        expect(vm.depensesFiltrees, hasLength(1));

        vm.definirFiltrePayee(true);
        expect(vm.depensesFiltrees, isEmpty);

        vm.definirFiltrePayee(false);
        expect(vm.depensesFiltrees, hasLength(1));
      },
    );

    test(
      'charges fixes et variables suivent les comptes, pas un libellé',
      () async {
        await depense(
          compteCharge: '613',
          compteReglement: '531',
          montant: 30000,
        );
        await depense(
          compteCharge: '616',
          compteReglement: '531',
          montant: 10000,
        );
        await depense(
          compteCharge: '624',
          compteReglement: '531',
          montant: 12000,
        );

        expect(vm.chargesFixes, 40000); // 613 + 616
        expect(vm.chargesVariables, 12000); // 624
      },
    );

    test('un achat d\'intrant n\'est PAS une dépense de cet écran', () async {
      // Ecriture d'achat : meme compte de classe 6, mais avec un `achatRef`.
      await ComptabiliteRepositoryDrift(db).enregistrerPiece(
        date: DateTime(annee, 6, 12),
        journalCode: 'AC',
        numeroPiece: 'A-001',
        achatRef: 'A-001',
        lignes: const [
          LigneAEcrire(
            numeroCompte: '601',
            debit: 25000,
            credit: 0,
            libelle: 'Achat Maïs',
          ),
          LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 25000,
            libelle: 'Achat Maïs',
          ),
        ],
      );
      await vm.charger();

      expect(vm.ecritures, hasLength(2));
      expect(
        vm.depenses,
        isEmpty,
        reason:
            'L\'écran Dépenses ne doit pas doubler les achats déjà tenus par '
            'Achats & Commandes.',
      );
      expect(vm.totalCharges, 25000, reason: 'La charge existe bel et bien.');
    });

    test('supprimer une dépense supprime SES DEUX lignes', () async {
      final piece = await depense(
        compteCharge: '624',
        compteReglement: '531',
        montant: 12000,
      );
      expect(vm.ecritures, hasLength(2));

      final resultat = await vm.supprimerPiece(piece);
      expect(resultat, isA<Succes<void>>());
      expect(vm.ecritures, isEmpty);
      expect(
        vm.balanceEstEquilibree,
        isTrue,
        reason:
            'Supprimer une seule ligne aurait laissé la balance déséquilibrée.',
      );
    });

    test(
      'une écriture automatique ne peut pas être supprimée à la main',
      () async {
        await ComptabiliteRepositoryDrift(db).enregistrerPiece(
          date: DateTime(annee, 6, 12),
          journalCode: 'VT',
          numeroPiece: 'V-001',
          venteRef: 'V-2026-001',
          lignes: const [
            LigneAEcrire(
              numeroCompte: '531',
              debit: 4500,
              credit: 0,
              libelle: 'Vente',
            ),
            LigneAEcrire(
              numeroCompte: '701',
              debit: 0,
              credit: 4500,
              libelle: 'Vente',
            ),
          ],
        );
        await vm.charger();

        final resultat = await vm.supprimerPiece('V-001');
        expect(resultat, isA<Echec<void>>());
        expect(vm.ecritures, hasLength(2));
      },
    );
  });

  group('Grand Livre — le solde progressif reste juste quand on filtre', () {
    setUp(() async {
      await depense(
        compteCharge: '624',
        compteReglement: '531',
        montant: 5000,
        libelle: 'Transport janvier',
        mois: 1,
      );
      await depense(
        compteCharge: '624',
        compteReglement: '531',
        montant: 7000,
        libelle: 'Transport juin',
        mois: 6,
      );
      vm.selectionnerCompte('624');
    });

    test('sans borne, tout l\'exercice est cumulé', () {
      expect(vm.soldeOuvertureCompte, 0);
      expect(vm.grandLivre, hasLength(2));
      expect(vm.soldeFinalCompte, 12000);
    });

    test('restreindre la période reporte les écritures antérieures en '
        'ouverture — sinon le solde progressif serait faux', () {
      vm.definirPeriodeGrandLivre(debut: DateTime(annee, 3, 1));

      expect(vm.soldeOuvertureCompte, 5000);
      expect(vm.grandLivre, hasLength(1));
      expect(vm.grandLivre.single.soldeProgressif, 12000);
      expect(vm.soldeFinalCompte, 12000);
    });

    test('la borne de fin est inclusive', () {
      vm.definirPeriodeGrandLivre(fin: DateTime(annee, 6, 12));
      expect(vm.grandLivre, hasLength(2));
    });

    test('la recherche masque des lignes mais ne fausse ni les totaux ni le '
        'solde final', () {
      vm.definirRechercheGrandLivre('juin');

      expect(vm.grandLivre, hasLength(1));
      expect(
        vm.totalDebitCompte,
        12000,
        reason:
            'Le KPI annonce « Total Débit Période », pas « des lignes '
            'affichées ».',
      );
      expect(vm.soldeFinalCompte, 12000);
    });
  });

  group('Analytique — aucune filière inventée', () {
    test('la ventilation suit les comptes réellement mouvementés', () async {
      await ComptabiliteRepositoryDrift(db).enregistrerPiece(
        date: DateTime(annee, 6, 12),
        journalCode: 'VT',
        numeroPiece: 'V-001',
        venteRef: 'V-2026-001',
        lignes: const [
          LigneAEcrire(
            numeroCompte: '531',
            debit: 10000,
            credit: 0,
            libelle: 'Vente',
          ),
          LigneAEcrire(
            numeroCompte: '701',
            debit: 0,
            credit: 6000,
            libelle: 'Vente avicole',
          ),
          LigneAEcrire(
            numeroCompte: '707',
            debit: 0,
            credit: 4000,
            libelle: 'Vente marchandises',
          ),
        ],
      );
      await depense(
        compteCharge: '622',
        compteReglement: '531',
        montant: 1000,
        libelle: 'Vétérinaire',
      );
      await depense(
        compteCharge: '628',
        compteReglement: '531',
        montant: 500,
        libelle: 'Divers',
      );
      await vm.charger();

      final centres = vm.centresAnalytiques;
      expect(centres, hasLength(2));

      // Aucune ecriture n'est imputee : tout retombe sur l'heuristique du
      // numero de compte, exactement comme avant la v19.
      final avicole = centres.firstWhere(
        (c) => c.nom == 'Avicole — filière non précisée',
      );
      expect(avicole.revenus, 6000);
      expect(avicole.couts, 1000); // 622
      expect(avicole.marge, 5000);

      final commerce = centres.firstWhere((c) => c.nom == 'Commerce Annexe');
      expect(commerce.revenus, 4000);
      expect(commerce.couts, 0);

      // La charge de structure n'est affectee a aucun centre.
      expect(vm.chargesNonAffectees, 500);
      expect(vm.produitsNonAffectes, 0);

      // Invariant : rien ne se perd en route.
      expect(
        avicole.marge +
            commerce.marge +
            vm.produitsNonAffectes -
            vm.chargesNonAffectees,
        vm.resultatNet,
      );
    });

    test('une charge imputée quitte les charges non affectées', () async {
      // Deux charges 628 : l'une imputee, l'autre non. Un compte 628 n'est
      // rattachable a aucune filiere par son numero — seule l'imputation
      // explicite le permet.
      await ComptabiliteRepositoryDrift(db).enregistrerPiece(
        date: DateTime(annee, 6, 15),
        journalCode: 'CA',
        numeroPiece: 'DEP-2026-0099',
        lignes: const [
          LigneAEcrire(
            numeroCompte: '628',
            debit: 800,
            credit: 0,
            libelle: 'Électricité couvoir',
            axeAnalytique: 'Goliaths',
          ),
          LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 800,
            libelle: 'Électricité couvoir',
          ),
        ],
      );
      await depense(
        compteCharge: '628',
        compteReglement: '531',
        montant: 500,
        libelle: 'Divers non imputés',
      );
      await vm.charger();

      final goliaths = vm.centresAnalytiques.firstWhere(
        (c) => c.nom == 'Goliaths',
      );
      expect(goliaths.couts, 800);
      expect(
        vm.chargesNonAffectees,
        500,
        reason: 'Les 800 F imputés n\'y sont plus, les 500 F restants si.',
      );
    });

    test('une charge imputée n\'est jamais comptée deux fois', () async {
      // 622 EST rattachable par son numero. Il porte pourtant un axe : l'axe
      // prime, et l'heuristique doit l'ignorer sous peine de double compte.
      await ComptabiliteRepositoryDrift(db).enregistrerPiece(
        date: DateTime(annee, 6, 16),
        journalCode: 'CA',
        numeroPiece: 'DEP-2026-0100',
        lignes: const [
          LigneAEcrire(
            numeroCompte: '622',
            debit: 2000,
            credit: 0,
            libelle: 'Vétérinaire pintades',
            axeAnalytique: 'Pintades',
          ),
          LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 2000,
            libelle: 'Vétérinaire pintades',
          ),
        ],
      );
      await depense(
        compteCharge: '622',
        compteReglement: '531',
        montant: 1000,
        libelle: 'Vétérinaire, filière non précisée',
      );
      await vm.charger();

      final pintades = vm.centresAnalytiques.firstWhere(
        (c) => c.nom == 'Pintades',
      );
      final avicole = vm.centresAnalytiques.firstWhere(
        (c) => c.nom == 'Avicole — filière non précisée',
      );

      expect(pintades.couts, 2000);
      expect(
        avicole.couts,
        1000,
        reason:
            'Les 2 000 F imputés aux Pintades ne doivent PAS revenir dans '
            'l\'avicole non précisé : ils y pèseraient deux fois.',
      );

      final total = vm.centresAnalytiques.fold<double>(
        0,
        (s, c) => s + c.marge,
      );
      expect(
        total + vm.produitsNonAffectes - vm.chargesNonAffectees,
        closeTo(vm.resultatNet, 0.01),
        reason: 'Invariant : rien ne se perd en route.',
      );
    });

    test(
      'taux de marge indéfini si le centre n\'a produit aucun revenu',
      () async {
        // Une charge imputee, aucun revenu : la marge existe (negative), le
        // TAUX de marge n'existe pas — on ne divise pas par zero, et « 0,0 % »
        // laisserait croire a une activite a l'equilibre.
        await ComptabiliteRepositoryDrift(db).enregistrerPiece(
          date: DateTime(annee, 6, 20),
          journalCode: 'CA',
          numeroPiece: 'DEP-2026-0200',
          lignes: const [
            LigneAEcrire(
              numeroCompte: '628',
              debit: 700,
              credit: 0,
              libelle: 'Aliment lapins',
              axeAnalytique: 'Lapins',
            ),
            LigneAEcrire(
              numeroCompte: '531',
              debit: 0,
              credit: 700,
              libelle: 'Aliment lapins',
            ),
          ],
        );
        await vm.charger();

        final lapins = vm.centresAnalytiques.firstWhere(
          (c) => c.nom == 'Lapins',
        );
        expect(lapins.revenus, 0);
        expect(lapins.couts, 700);
        expect(lapins.marge, -700);
        expect(lapins.tauxMarge, isNull);
      },
    );
  });

  group('Verrouillage — les écrans ne peuvent pas contourner la règle', () {
    test('un mois clôturé refuse toute nouvelle dépense à sa date', () async {
      expect(await vm.cloturerMois(6), isA<Succes<void>>());

      final piece = vm.prochainNumeroPiece('DEP');
      final resultat = await vm.enregistrerPiece(
        date: DateTime(annee, 6, 12),
        journalCode: 'CA',
        numeroPiece: piece,
        lignes: const [
          LigneAEcrire(
            numeroCompte: '624',
            debit: 1000,
            credit: 0,
            libelle: 'Transport',
          ),
          LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 1000,
            libelle: 'Transport',
          ),
        ],
      );

      expect(resultat, isA<Echec<void>>());
      expect(vm.ecritures, isEmpty);

      // Un autre mois reste ouvert.
      await depense(
        compteCharge: '624',
        compteReglement: '531',
        montant: 1000,
        mois: 7,
      );
      expect(vm.ecritures, hasLength(2));
    });

    test('la déclôture est refusée à un rôle non administrateur', () async {
      await vm.cloturerMois(6);

      final refus = await vm.decloturerMois(
        mois: 6,
        roleId: 'caissier',
        utilisateurId: '2',
      );
      expect(refus, isA<Echec<void>>());
      expect(vm.cloturesMois[6], isTrue);

      final accepte = await vm.decloturerMois(
        mois: 6,
        roleId: 'admin',
        utilisateurId: '1',
      );
      expect(accepte, isA<Succes<void>>());
      expect(vm.cloturesMois[6], isFalse);
    });

    test(
      'la clôture annuelle ouvre l\'exercice suivant et verrouille tout',
      () async {
        await depense(
          compteCharge: '624',
          compteReglement: '531',
          montant: 1000,
        );

        expect(
          await vm.cloturerExercice(roleId: 'admin'),
          isA<Succes<void>>(),
        );
        expect(vm.exerciceEstCloture, isTrue);
        expect(vm.exercices, contains(annee + 1));
        expect(vm.ecritures.every((e) => e.isLocked), isTrue);

        // Plus aucune ecriture possible sur l'exercice clos.
        final piece = vm.prochainNumeroPiece('DEP');
        final resultat = await vm.enregistrerPiece(
          date: DateTime(annee, 8, 1),
          journalCode: 'CA',
          numeroPiece: piece,
          lignes: const [
            LigneAEcrire(
              numeroCompte: '624',
              debit: 500,
              credit: 0,
              libelle: 'Transport',
            ),
            LigneAEcrire(
              numeroCompte: '531',
              debit: 0,
              credit: 500,
              libelle: 'Transport',
            ),
          ],
        );
        expect(resultat, isA<Echec<void>>());
      },
    );
  });

  group('Notes annexes', () {
    test('une note est persistée par exercice et relue telle quelle', () async {
      expect(vm.contenuNote(1), isEmpty);

      final resultat = await vm.enregistrerNote(
        const NoteAnnexe(
          numero: 1,
          titre: 'Méthodes Comptables',
          contenu: 'Amortissement linéaire, stocks au PMP.',
        ),
      );
      expect(resultat, isA<Succes<void>>());
      expect(vm.contenuNote(1), contains('linéaire'));

      // Reenregistrer la meme note la met a jour, sans doublon.
      await vm.enregistrerNote(
        const NoteAnnexe(
          numero: 1,
          titre: 'Méthodes Comptables',
          contenu: 'Texte révisé.',
        ),
      );
      expect(vm.notes.where((n) => n.numero == 1), hasLength(1));
      expect(vm.contenuNote(1), 'Texte révisé.');
    });
  });
}
