import 'package:flutter/foundation.dart';

import '../../../core/resultat/resultat.dart';
import '../../data/repositories/comptabilite_repository_drift.dart';
import '../../domain/entities/comptabilite.dart';
import '../../domain/services/bilan_entreprise.dart';
import '../../domain/services/moteur_comptable.dart';

/// État partagé du module Comptabilité — Doc F6.
///
/// Un seul ViewModel pour les 8 écrans : ils lisent tous `ECRITURE_COMPTABLE`
/// et doivent afficher le même Résultat Net (BR-CPT-005). Des ViewModels
/// séparés auraient chacun leur copie des écritures, donc leur propre version
/// du résultat — précisément ce que la règle interdit.
class ComptabiliteViewModel extends ChangeNotifier {
  ComptabiliteViewModel(this._repository);

  final ComptabiliteRepository _repository;

  bool _chargement = true;
  bool get chargement => _chargement;

  List<CompteComptable> _plan = const [];
  List<Ecriture> _toutesEcritures = const [];
  List<int> _exercices = const [];
  Map<int, bool> _cloturesMois = const {};
  List<NoteAnnexe> _notes = const [];
  bool _exerciceCloture = false;

  int _exercice = DateTime.now().year;
  int get exercice => _exercice;
  List<int> get exercices => _exercices;
  bool get exerciceEstCloture => _exerciceCloture;

  List<CompteComptable> get plan => _plan;
  List<CompteComptable> get planActif =>
      _plan.where((c) => !c.archive).toList();
  Map<int, bool> get cloturesMois => _cloturesMois;
  List<NoteAnnexe> get notes => _notes;

  /// Écritures de l'exercice sélectionné.
  List<Ecriture> get ecritures =>
      _toutesEcritures.where((e) => e.exerciceAnnee == _exercice).toList();

  /// Écritures antérieures à l'exercice — soldes d'ouverture.
  List<Ecriture> get _ecrituresAnterieures =>
      _toutesEcritures.where((e) => e.exerciceAnnee < _exercice).toList();

  // ------------------------------------------------------------- chargement

  Future<void> charger() async {
    _chargement = true;
    notifyListeners();
    await _rafraichir();
    _chargement = false;
    notifyListeners();
  }

  Future<void> _rafraichir() async {
    _plan = await _repository.chargerPlanComptable();
    _toutesEcritures = await _repository.chargerEcritures();
    _exercices = await _repository.chargerExercices();
    if (_exercices.isNotEmpty && !_exercices.contains(_exercice)) {
      _exercice = _exercices.first;
    }
    _cloturesMois = await _repository.chargerCloturesPeriodiques(_exercice);
    _notes = await _repository.chargerNotes(_exercice);
    _exerciceCloture = await _repository.exerciceEstCloture(_exercice);
  }

  Future<void> changerExercice(int annee) async {
    _exercice = annee;
    await _rafraichir();
    notifyListeners();
  }

  // -------------------------------------------------------------- Journal

  String _rechercheJournal = '';
  String? _filtreJournalCode;
  String get rechercheJournal => _rechercheJournal;
  String? get filtreJournalCode => _filtreJournalCode;

  void definirRechercheJournal(String valeur) {
    _rechercheJournal = valeur;
    notifyListeners();
  }

  void definirFiltreJournal(String? valeur) {
    _filtreJournalCode = valeur;
    notifyListeners();
  }

  List<Ecriture> get journalFiltre {
    final terme = _rechercheJournal.trim().toLowerCase();
    return ecritures.where((e) {
      if (_filtreJournalCode != null && e.journalCode != _filtreJournalCode) {
        return false;
      }
      if (terme.isEmpty) return true;
      return e.libelle.toLowerCase().contains(terme) ||
          e.numeroCompte.contains(terme) ||
          (e.numeroPiece?.toLowerCase().contains(terme) ?? false);
    }).toList();
  }

  double get totalDebitJournal => journalFiltre.fold(0, (s, e) => s + e.debit);
  double get totalCreditJournal =>
      journalFiltre.fold(0, (s, e) => s + e.credit);

  // ----------------------------------------------------------- Grand Livre

  String? _compteSelectionne;
  String? get compteSelectionne => _compteSelectionne;

  void selectionnerCompte(String? numero) {
    _compteSelectionne = numero;
    notifyListeners();
  }

  CompteComptable? get compteCourant {
    final numero = _compteSelectionne;
    if (numero == null) return null;
    for (final compte in _plan) {
      if (compte.numero == numero) return compte;
    }
    return null;
  }

  DateTime? _debutGrandLivre;
  DateTime? _finGrandLivre;
  String _rechercheGrandLivre = '';

  DateTime? get debutGrandLivre => _debutGrandLivre;
  DateTime? get finGrandLivre => _finGrandLivre;
  String get rechercheGrandLivre => _rechercheGrandLivre;

  void definirPeriodeGrandLivre({DateTime? debut, DateTime? fin}) {
    _debutGrandLivre = debut;
    _finGrandLivre = fin;
    notifyListeners();
  }

  void definirRechercheGrandLivre(String valeur) {
    _rechercheGrandLivre = valeur;
    notifyListeners();
  }

  bool _avantPeriode(Ecriture e) =>
      _debutGrandLivre != null && e.date.isBefore(_debutGrandLivre!);

  bool _dansPeriode(Ecriture e) {
    if (_avantPeriode(e)) return false;
    final fin = _finGrandLivre;
    if (fin != null) {
      // Borne incluse : une écriture du 08/08 doit entrer dans « au 08/08 ».
      final finInclusive = DateTime(fin.year, fin.month, fin.day, 23, 59, 59);
      if (e.date.isAfter(finInclusive)) return false;
    }
    return true;
  }

  /// Solde d'ouverture du compte : reports des exercices antérieurs **plus**
  /// les écritures de l'exercice antérieures à la date de début choisie.
  ///
  /// Sans ce second terme, restreindre la période afficherait un solde
  /// progressif faux — l'erreur classique du grand livre filtré.
  double get soldeOuvertureCompte {
    final compte = compteCourant;
    if (compte == null) return 0;
    final net =
        _ecrituresAnterieures
            .where((e) => e.numeroCompte == compte.numero)
            .fold<double>(0, (s, e) => s + e.debit - e.credit) +
        ecritures
            .where((e) => e.numeroCompte == compte.numero && _avantPeriode(e))
            .fold<double>(0, (s, e) => s + e.debit - e.credit);
    return compte.estDebiteurParNature ? net : -net;
  }

  /// Toutes les lignes de la période, recherche non appliquée.
  ///
  /// Les KPI (« Total Débit **Période** », « Solde Final ») et la colonne
  /// « Solde Progressif » se calculent ici : filtrer les écritures par un terme
  /// de recherche avant de cumuler produirait un solde progressif qui saute et
  /// un solde final faux.
  List<LigneGrandLivre> get _lignesPeriode {
    final compte = compteCourant;
    if (compte == null) return const [];
    return const GrandLivreCalculator().calculer(
      compte: compte,
      soldeOuverture: soldeOuvertureCompte,
      ecritures: ecritures
          .where((e) => e.numeroCompte == compte.numero && _dansPeriode(e))
          .toList(),
    );
  }

  List<LigneGrandLivre> get grandLivre {
    final terme = _rechercheGrandLivre.trim().toLowerCase();
    final lignes = _lignesPeriode;
    if (terme.isEmpty) return lignes;

    return lignes
        .where(
          (l) =>
              l.ecriture.libelle.toLowerCase().contains(terme) ||
              (l.ecriture.numeroPiece?.toLowerCase().contains(terme) ??
                  false) ||
              (l.ecriture.venteRef?.toLowerCase().contains(terme) ?? false) ||
              (l.ecriture.achatRef?.toLowerCase().contains(terme) ?? false),
        )
        .toList();
  }

  double get totalDebitCompte =>
      _lignesPeriode.fold(0, (s, l) => s + l.ecriture.debit);
  double get totalCreditCompte =>
      _lignesPeriode.fold(0, (s, l) => s + l.ecriture.credit);
  double get soldeFinalCompte {
    final lignes = _lignesPeriode;
    return lignes.isEmpty ? soldeOuvertureCompte : lignes.last.soldeProgressif;
  }

  // -------------------------------------------------------------- Balance

  /// `bal-periode-select` de `balance-generale.html` l.67 : « Mois en cours »
  /// ou « Exercice complet ».
  ///
  /// Ce n'est pas un simple filtre d'affichage. Le format 6 colonnes distingue
  /// **Solde Ouverture / Mouvements Période / Solde Final** : restreindre la
  /// période déplace la frontière entre les deux premières. En mois courant,
  /// tout ce qui précède le 1ᵉʳ du mois — exercices antérieurs compris —
  /// bascule dans l'ouverture. Ne filtrer que les lignes affichées produirait
  /// un solde final faux.
  bool _balanceMoisCourant = false;
  bool get balanceMoisCourant => _balanceMoisCourant;

  void definirPerimetreBalance({required bool moisCourant}) {
    _balanceMoisCourant = moisCourant;
    notifyListeners();
  }

  /// Premier jour du mois retenu comme borne, dans l'exercice sélectionné.
  ///
  /// Sur un exercice passé, « mois en cours » n'a pas de sens : on prend alors
  /// décembre, le dernier mois de cet exercice.
  DateTime get _debutMoisBalance {
    final maintenant = DateTime.now();
    final mois = _exercice == maintenant.year ? maintenant.month : 12;
    return DateTime(_exercice, mois);
  }

  /// Libellé exact du sélecteur, mois et année réels.
  String get libelleMoisBalance {
    final debut = _debutMoisBalance;
    return '${_moisFrancais[debut.month - 1]} ${debut.year}';
  }

  static const List<String> _moisFrancais = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];

  List<LigneBalance> get balance {
    if (!_balanceMoisCourant) {
      return const BalanceCalculator().calculer(
        comptes: _plan,
        ecrituresAnterieures: _ecrituresAnterieures,
        ecrituresPeriode: ecritures,
      );
    }

    final borne = _debutMoisBalance;
    return const BalanceCalculator().calculer(
      comptes: _plan,
      ecrituresAnterieures: [
        ..._ecrituresAnterieures,
        ...ecritures.where((e) => e.date.isBefore(borne)),
      ],
      ecrituresPeriode: ecritures
          .where((e) => !e.date.isBefore(borne))
          .toList(),
    );
  }

  double get balanceTotalDebit => balance.fold(0, (s, l) => s + l.finalDebit);
  double get balanceTotalCredit => balance.fold(0, (s, l) => s + l.finalCredit);
  double get balanceEcart => BalanceGeneraleValidator.ecart(balance);
  bool get balanceEstEquilibree =>
      BalanceGeneraleValidator.estEquilibree(balance);

  // ----------------------------------------------------- États financiers

  SoldesComptes get _soldes => SoldesComptes.depuis(ecritures);
  SoldesComptes get _soldesOuverture =>
      SoldesComptes.depuis(_ecrituresAnterieures);

  /// **Source unique du Résultat Net — BR-CPT-005.**
  double get resultatNet => CalculerResultatNet.calculer(_soldes);

  double get totalProduits => CalculerResultatNet.produits(_soldes);
  double get totalCharges => CalculerResultatNet.charges(_soldes);

  Bilan get bilan => const BilanCalculator().calculer(_soldes);

  /// Version lisible du bilan — écran « Bilan de l'Entreprise ».
  ///
  /// Même source d'écritures que [bilan], donc même Résultat Net (BR-CPT-005) :
  /// c'est pourquoi ce getter vit ici et non dans un ViewModel séparé.
  BilanEntreprise get bilanEntreprise =>
      const BilanEntrepriseCalculator().calculer(_soldes);

  CompteDeResultat get compteResultat =>
      const CompteResultatCalculator().calculer(_soldes);

  Tafire get tafire => const TafireCalculator().calculer(
    soldes: _soldes,
    soldesOuverture: _soldesOuverture,
  );

  /// Trésorerie disponible — alimente le KPI du tableau de bord (Doc F2).
  double get tresorerie => _soldes.debiteursParClasse('5');

  // --------------------------------------------------------------- actions

  /// Enregistre une pièce équilibrée (saisie manuelle ou dépense).
  Future<Resultat<void>> enregistrerPiece({
    required DateTime date,
    required String journalCode,
    String? numeroPiece,
    required List<LigneAEcrire> lignes,
  }) async {
    for (final ligne in lignes) {
      final erreur = EcritureValidator.valider(
        debit: ligne.debit,
        credit: ligne.credit,
        libelle: ligne.libelle,
        numeroCompte: ligne.numeroCompte,
      );
      if (erreur != null) return Echec(erreur);
    }

    final erreurLot = EcritureValidator.validerLot([
      for (final l in lignes) (debit: l.debit, credit: l.credit),
    ]);
    if (erreurLot != null) return Echec(erreurLot);

    try {
      await _repository.enregistrerPiece(
        date: date,
        journalCode: journalCode,
        numeroPiece: numeroPiece,
        lignes: lignes,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } on StateError catch (e) {
      // Message métier du double verrouillage — il doit remonter tel quel.
      return Echec(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec ecriture: $e');
      return const Echec('L\'écriture n\'a pas pu être enregistrée.');
    }
  }

  /// Numéro de pièce suivant pour un préfixe donné — « OD-2026-0003 ».
  ///
  /// Le prototype code ses numéros en dur (`'OD-2026-0' + (143 + n)`). Ici la
  /// séquence est déduite des pièces réellement enregistrées sur l'exercice :
  /// deux pièces ne peuvent pas porter le même numéro, et la numérotation
  /// repart proprement à 1 sur un nouvel exercice.
  String prochainNumeroPiece(String prefixe) {
    final debut = '$prefixe-$_exercice-';
    var maximum = 0;
    for (final ecriture in ecritures) {
      final numero = ecriture.numeroPiece;
      if (numero == null || !numero.startsWith(debut)) continue;
      final sequence = int.tryParse(numero.substring(debut.length));
      if (sequence != null && sequence > maximum) maximum = sequence;
    }
    return '$debut${(maximum + 1).toString().padLeft(4, '0')}';
  }

  /// Réécrit une pièce existante sous son propre numéro.
  ///
  /// Les mêmes contrôles que [enregistrerPiece] s'appliquent : partie double
  /// ligne par ligne, puis équilibre du lot. Une modification ne peut pas
  /// produire une pièce déséquilibrée (BR-CPT-001).
  Future<Resultat<void>> remplacerPiece({
    required String numeroPiece,
    required DateTime date,
    required String journalCode,
    required List<LigneAEcrire> lignes,
  }) async {
    for (final ligne in lignes) {
      final erreur = EcritureValidator.valider(
        debit: ligne.debit,
        credit: ligne.credit,
        libelle: ligne.libelle,
        numeroCompte: ligne.numeroCompte,
      );
      if (erreur != null) return Echec(erreur);
    }

    final erreurLot = EcritureValidator.validerLot([
      for (final l in lignes) (debit: l.debit, credit: l.credit),
    ]);
    if (erreurLot != null) return Echec(erreurLot);

    try {
      await _repository.remplacerPiece(
        exerciceAnnee: _exercice,
        numeroPiece: numeroPiece,
        date: date,
        journalCode: journalCode,
        lignes: lignes,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } on StateError catch (e) {
      return Echec(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec modification piece: $e');
      return const Echec('Cette pièce n\'a pas pu être modifiée.');
    }
  }

  Future<Resultat<void>> supprimerPiece(String numeroPiece) async {
    try {
      await _repository.supprimerPiece(
        exerciceAnnee: _exercice,
        numeroPiece: numeroPiece,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } on StateError catch (e) {
      return Echec(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression piece: $e');
      return const Echec('Cette pièce n\'a pas pu être supprimée.');
    }
  }

  Future<Resultat<void>> supprimerEcriture(Ecriture ecriture) async {
    try {
      await _repository.supprimerEcriture(ecriture.id);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } on StateError catch (e) {
      return Echec(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec suppression ecriture: $e');
      return const Echec('Cette écriture n\'a pas pu être supprimée.');
    }
  }

  Future<Resultat<void>> creerCompte({
    required String numero,
    required String libelle,
    required String? classe,
  }) async {
    if (numero.trim().isEmpty) {
      return const Echec('Le numéro de compte est obligatoire.');
    }
    if (!RegExp(r'^[1-7]\d*$').hasMatch(numero.trim())) {
      return const Echec(
        'Un numéro de compte SYSCOHADA commence par un chiffre de 1 à 7.',
      );
    }
    if (libelle.trim().isEmpty) {
      return const Echec('Le libellé est obligatoire.');
    }
    if (classe == null) return const Echec('La classe est obligatoire.');
    if (_plan.any((c) => c.numero == numero.trim())) {
      return const Echec('Ce numéro de compte existe déjà.');
    }
    // La classe doit correspondre au 1er chiffre, sinon toute la logique de
    // regroupement des etats financiers devient fausse.
    if (!numero.trim().startsWith(classe)) {
      return Echec(
        'Le numéro doit commencer par $classe pour appartenir à cette classe.',
      );
    }

    try {
      await _repository.creerCompte(
        CompteComptable(
          numero: numero.trim(),
          libelle: libelle.trim(),
          classe: classe,
        ),
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec creation compte: $e');
      return const Echec('Impossible de créer ce compte.');
    }
  }

  /// Modifie le libellé et la classe d'un compte. Le **numéro est immuable** :
  /// il est la clé étrangère de toutes les écritures déjà passées.
  Future<Resultat<void>> modifierCompte({
    required String numero,
    required String libelle,
    required String? classe,
  }) async {
    if (libelle.trim().isEmpty) {
      return const Echec('Le libellé est obligatoire.');
    }
    if (classe == null) return const Echec('La classe est obligatoire.');
    if (!numero.startsWith(classe)) {
      return Echec(
        'Le numéro $numero ne peut pas appartenir à la classe $classe.',
      );
    }

    // Changer la classe d'un compte deja mouvemente deplacerait retroactivement
    // ses ecritures d'un poste du bilan a un autre.
    final compteExistant = _plan.firstWhere(
      (c) => c.numero == numero,
      orElse: () =>
          CompteComptable(numero: numero, libelle: libelle, classe: classe),
    );
    if (compteExistant.classe != classe) {
      final mouvements = await _repository.nombreEcrituresDuCompte(numero);
      if (mouvements > 0) {
        return Echec(
          'Le compte $numero porte $mouvements écriture(s) : sa classe ne peut '
          'plus changer sans fausser les états financiers déjà publiés. '
          'Archivez-le et créez un nouveau compte.',
        );
      }
    }

    try {
      await _repository.modifierCompte(
        numero: numero,
        libelle: libelle.trim(),
        classe: classe,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec modification compte: $e');
      return const Echec('Impossible de modifier ce compte.');
    }
  }

  Future<Resultat<void>> basculerArchive(CompteComptable compte) async {
    // Un compte mouvementé ne peut pas être archivé sans rendre illisibles les
    // états qui le référencent — on l'autorise, mais l'historique le conserve.
    try {
      await _repository.archiverCompte(compte.numero, archive: !compte.archive);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec archivage compte: $e');
      return const Echec('Impossible de modifier ce compte.');
    }
  }

  // ------------------------------------------------------------- clôtures

  /// **Interdiction structurelle (Doc F6 §3)** : aucune clôture ne peut
  /// s'exécuter sur une balance déséquilibrée.
  Future<Resultat<void>> cloturerMois(int mois) async {
    if (!balanceEstEquilibree) {
      return Echec(
        'Balance déséquilibrée de ${balanceEcart.abs().toStringAsFixed(0)} FCFA. '
        'Corrigez la saisie avant toute clôture (BR-CPT-004).',
      );
    }
    if (_exerciceCloture) {
      return const Echec('L\'exercice est déjà clôturé.');
    }

    try {
      await _repository.cloturerMois(annee: _exercice, mois: mois);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec cloture mois: $e');
      return const Echec('La clôture du mois a échoué.');
    }
  }

  /// BR-CPT-006 — déclôture réservée au rôle `admin`, journalisée.
  Future<Resultat<void>> decloturerMois({
    required int mois,
    required String roleId,
    required String utilisateurId,
  }) async {
    if (roleId != 'admin') {
      return const Echec(
        'Seule une administratrice peut déclôturer un mois (BR-CPT-006).',
      );
    }
    try {
      await _repository.decloturerMois(
        annee: _exercice,
        mois: mois,
        utilisateurId: utilisateurId,
      );
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec decloture: $e');
      return const Echec('La déclôture a échoué.');
    }
  }

  Future<Resultat<void>> cloturerExercice() async {
    if (!balanceEstEquilibree) {
      return Echec(
        'Balance déséquilibrée de ${balanceEcart.abs().toStringAsFixed(0)} FCFA. '
        'Une clôture annuelle est définitive : elle ne peut pas s\'exécuter sur '
        'une comptabilité déséquilibrée (BR-CPT-004).',
      );
    }
    if (_exerciceCloture) {
      return const Echec('Cet exercice est déjà clôturé.');
    }

    try {
      await _repository.cloturerExercice(_exercice);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec cloture exercice: $e');
      return const Echec('La clôture annuelle a échoué.');
    }
  }

  Future<Resultat<void>> enregistrerNote(NoteAnnexe note) async {
    try {
      await _repository.enregistrerNote(_exercice, note);
      await _rafraichir();
      notifyListeners();
      return const Succes(null);
    } catch (e) {
      if (kDebugMode) debugPrint('Echec note annexe: $e');
      return const Echec('La note n\'a pas pu être enregistrée.');
    }
  }

  /// Contenu d'une note, ou chaîne vide si elle n'existe pas encore.
  String contenuNote(int numero) {
    for (final note in _notes) {
      if (note.numero == numero) return note.contenu;
    }
    return '';
  }

  // ------------------------------------------------------------- Dépenses

  /// Une dépense au sens de `saisie-depenses.html` : une charge d'exploitation
  /// saisie à la main, **hors achats d'intrants** (déjà couverts par Achats &
  /// Commandes, qui génèrent leurs écritures sur 601/602/622 avec un
  /// `achatRef`).
  ///
  /// Le critère est donc structurel, pas une convention de libellé : ligne au
  /// débit d'un compte de classe 6, sans `achatRef`.
  List<Depense> get depenses {
    final chargesParPiece = <String, List<Ecriture>>{};
    for (final e in ecritures) {
      if (e.achatRef != null || e.venteRef != null) continue;
      final piece = e.numeroPiece;
      if (piece == null) continue;
      final compte = _compte(e.numeroCompte);
      if (compte == null || compte.classe != '6') continue;
      if (e.debit <= 0) continue;
      chargesParPiece.putIfAbsent(piece, () => []).add(e);
    }

    final resultat = <Depense>[];
    chargesParPiece.forEach((piece, lignes) {
      // La contrepartie porte le même numéro de pièce, au crédit.
      final contreparties = ecritures.where(
        (e) => e.numeroPiece == piece && e.credit > 0,
      );
      final compteCredite = contreparties.isEmpty
          ? '—'
          : contreparties.first.numeroCompte;

      resultat.add(
        Depense(
          numeroPiece: piece,
          date: lignes.first.date,
          libelle: lignes.first.libelle,
          numeroCompteCharge: lignes.first.numeroCompte,
          libelleCompteCharge:
              _compte(lignes.first.numeroCompte)?.libelle ?? '',
          montant: lignes.fold<double>(0, (s, e) => s + e.debit),
          compteRegle: compteCredite,
          centreAnalytique: lignes.first.axeAnalytique,
          // Une charge soldée par 401 n'est pas décaissée : elle reste due.
          payee: !compteCredite.startsWith('40'),
        ),
      );
    });

    resultat.sort((a, b) => b.date.compareTo(a.date));
    return resultat;
  }

  CompteComptable? _compte(String numero) {
    for (final c in _plan) {
      if (c.numero == numero) return c;
    }
    return null;
  }

  String _rechercheDepenses = '';
  bool? _filtrePayee;
  String get rechercheDepenses => _rechercheDepenses;
  bool? get filtrePayee => _filtrePayee;

  void definirRechercheDepenses(String valeur) {
    _rechercheDepenses = valeur;
    notifyListeners();
  }

  void definirFiltrePayee(bool? valeur) {
    _filtrePayee = valeur;
    notifyListeners();
  }

  void reinitialiserFiltresDepenses() {
    _rechercheDepenses = '';
    _filtrePayee = null;
    notifyListeners();
  }

  List<Depense> get depensesFiltrees {
    final terme = _rechercheDepenses.trim().toLowerCase();
    return depenses.where((d) {
      if (_filtrePayee != null && d.payee != _filtrePayee) return false;
      if (terme.isEmpty) return true;
      return d.libelle.toLowerCase().contains(terme) ||
          d.libelleCompteCharge.toLowerCase().contains(terme) ||
          d.numeroCompteCharge.contains(terme) ||
          d.numeroPiece.toLowerCase().contains(terme);
    }).toList();
  }

  /// KPI « Dépenses du Mois » — mois civil en cours, comme le prototype.
  double get depensesDuMois {
    final maintenant = DateTime.now();
    return depenses
        .where(
          (d) =>
              d.date.year == maintenant.year &&
              d.date.month == maintenant.month,
        )
        .fold<double>(0, (s, d) => s + d.montant);
  }

  double get chargesFixes => depenses
      .where((d) => ComptesDepenses.fixes.contains(d.numeroCompteCharge))
      .fold<double>(0, (s, d) => s + d.montant);

  double get chargesVariables => depenses
      .where((d) => !ComptesDepenses.fixes.contains(d.numeroCompteCharge))
      .fold<double>(0, (s, d) => s + d.montant);

  /// Comptes proposés à l'imputation d'une dépense : classe 6, hors comptes
  /// d'achats alimentés automatiquement par le module Approvisionnement.
  List<CompteComptable> get comptesDeCharge => planActif
      .where(
        (c) =>
            c.classe == '6' &&
            !c.numero.startsWith('601') &&
            !c.numero.startsWith('602'),
      )
      .toList();

  /// Comptes de trésorerie proposés au règlement — classe 5 uniquement.
  List<CompteComptable> get comptesDeTresorerie =>
      planActif.where((c) => c.classe == '5').toList();

  // ----------------------------------------------------------- analytique

  /// Ventilation analytique — Doc F6 §7.
  ///
  /// ⚠️ **Limite réelle, signalée** : `ECRITURE_COMPTABLE` (Doc D1) ne porte
  /// **aucun axe analytique** — ni centre de coût, ni espèce. Le prototype
  /// (`comptabilite-analytique.html`) affiche trois centres « Goliaths /
  /// Pintades / Commerce Annexe » avec des montants écrits en dur : aucune
  /// écriture du système ne permet de rattacher un franc à une filière
  /// précise, et un sac de maïs nourrit plusieurs espèces à la fois.
  ///
  /// Ce qui est **réellement** dérivable du grand livre : la ventilation par
  /// activité que les comptes distinguent déjà — Avicole (701 / 601 / 622) et
  /// Commerce Annexe (707 / 602). C'est la même que celle du KPI « Chiffre
  /// d'Affaires » du tableau de bord, donc cohérente avec le reste de
  /// l'application. L'écran l'affiche et énonce la limite plutôt que d'inventer
  /// trois filières.
  /// Centres analytiques proposés à la saisie.
  ///
  /// Volontairement une **constante du module Comptabilité** et non une
  /// lecture de `ConfigurationsEspeces` : la comptabilité ne lit pas les
  /// tables de l'élevage (Doc C1 §7). Les noms sont ceux que les écritures de
  /// vente écrivent déjà, plus les filières désactivables — une charge peut
  /// concerner une filière avant que sa première vente n'ait eu lieu.
  static const List<String> centresAnalytiquesConnus = [
    'Goliaths',
    'Pintades',
    'Lapins',
    'Poissons-Chats',
    'Poulets',
    'Pondeuses',
    'Commerce Annexe',
  ];

  /// Centres de profit, ventilés depuis l'**axe analytique** des écritures.
  ///
  /// ## Deux sources, dans cet ordre
  ///
  /// 1. `ECRITURE_COMPTABLE.axeAnalytique` quand il est renseigné — imputation
  ///    **explicite**, elle prime toujours ;
  /// 2. à défaut, l'heuristique du numéro de compte, tout ce dont on disposait
  ///    avant la v19 : 701/601/622 pour l'avicole, 707/602 pour le commerce.
  ///
  /// Une ligne comptée par l'axe n'est **jamais recomptée** par l'heuristique,
  /// sans quoi une charge d'aliment imputée aux Pintades pèserait deux fois.
  ///
  /// ⚠️ Avant la v19, tout l'avicole formait un bloc unique alors que
  /// `comptabilite-analytique.html` l.146-149 ventile bien **Goliaths** et
  /// **Pintades** séparément.
  ///
  /// **Invariant** : Σ marges + [produitsNonAffectes] − [chargesNonAffectees]
  /// = [resultatNet]. Rien ne se perd en route, et un test le vérifie.
  List<CentreAnalytique> get centresAnalytiques {
    final parAxe = _montantsParAxe;

    // Ce que le numero de compte laisse deviner, hors lignes deja imputees.
    final avicoleRevenus = -_soldeNonImpute('701');
    final avicoleCouts = _soldeNonImpute('601') + _soldeNonImpute('622');
    final commerceRevenus = -_soldeNonImpute('707');
    final commerceCouts = _soldeNonImpute('602');

    final centres = <CentreAnalytique>[];

    for (final nom in parAxe.keys.toList()..sort()) {
      final part = parAxe[nom]!;
      final estCommerce = nom == 'Commerce Annexe';
      centres.add(
        CentreAnalytique(
          nom: nom,
          detail: estCommerce && (commerceRevenus.abs() + commerceCouts.abs()) >= 0.01
              ? 'Imputation analytique + comptes 707 et 602'
              : 'Imputation analytique',
          revenus: part.revenus + (estCommerce ? commerceRevenus : 0),
          couts: part.couts + (estCommerce ? commerceCouts : 0),
        ),
      );
    }

    // Le commerce annexe existe par son compte meme sans aucune imputation.
    if (!parAxe.containsKey('Commerce Annexe') &&
        (commerceRevenus.abs() >= 0.01 || commerceCouts.abs() >= 0.01)) {
      centres.add(
        CentreAnalytique(
          nom: 'Commerce Annexe',
          detail: 'Comptes 707 et 602',
          revenus: commerceRevenus,
          couts: commerceCouts,
        ),
      );
    }

    // L'avicole non impute ne se rattache a aucune filiere precise : il forme
    // son propre centre plutot que d'etre reparti au prorata — une cle de
    // repartition que personne n'a fixee donnerait des marges fausses avec
    // l'air d'etre exactes.
    if (avicoleRevenus.abs() >= 0.01 || avicoleCouts.abs() >= 0.01) {
      centres.add(
        CentreAnalytique(
          nom: 'Avicole — filière non précisée',
          detail: 'Comptes 701, 601 et 622 sans imputation analytique',
          revenus: avicoleRevenus,
          couts: avicoleCouts,
        ),
      );
    }

    return centres;
  }

  /// Revenus et coûts cumulés par centre, depuis les écritures imputées.
  Map<String, ({double revenus, double couts})> get _montantsParAxe {
    final parAxe = <String, ({double revenus, double couts})>{};
    for (final e in ecritures) {
      final axe = e.axeAnalytique?.trim();
      if (axe == null || axe.isEmpty) continue;

      final courant = parAxe[axe] ?? (revenus: 0.0, couts: 0.0);
      if (e.numeroCompte.startsWith('7')) {
        parAxe[axe] = (
          revenus: courant.revenus + e.credit - e.debit,
          couts: courant.couts,
        );
      } else if (e.numeroCompte.startsWith('6')) {
        parAxe[axe] = (
          revenus: courant.revenus,
          couts: courant.couts + e.debit - e.credit,
        );
      }
    }
    return parAxe;
  }

  /// Solde d'un préfixe de compte, **hors lignes déjà imputées** à un axe.
  double _soldeNonImpute(String prefixe) => ecritures
      .where(
        (e) =>
            e.numeroCompte.startsWith(prefixe) &&
            (e.axeAnalytique?.trim().isEmpty ?? true),
      )
      .fold<double>(0, (s, e) => s + e.debit - e.credit);

  /// Somme d'une classe entière, hors lignes imputées à un axe.
  double _classeNonImputee(String classe) => ecritures
      .where(
        (e) =>
            e.numeroCompte.startsWith(classe) &&
            (e.axeAnalytique?.trim().isEmpty ?? true),
      )
      .fold<double>(0, (s, e) => s + e.debit - e.credit);

  /// Charges de structure — celles qu'aucun axe ni aucun compte ne rattache.
  ///
  /// Électricité, transport, assurances : elles servent toute l'exploitation.
  /// Elles restent affichées à part, **jamais réparties au prorata** : une clé
  /// de répartition que personne n'a fixée produirait des marges par filière
  /// fausses avec l'air d'être exactes.
  double get chargesNonAffectees =>
      _classeNonImputee('6') -
      _soldeNonImpute('601') -
      _soldeNonImpute('602') -
      _soldeNonImpute('622');

  /// Produits qu'aucun axe ni aucun compte ne rattache — subventions (75),
  /// produits financiers (77), produits HAO (78).
  ///
  /// Sans eux, l'invariant « Σ marges − charges non affectées = résultat net »
  /// serait faux dès la première subvention encaissée.
  double get produitsNonAffectes =>
      -(_classeNonImputee('7') - _soldeNonImpute('701') - _soldeNonImpute('707'));
}

/// Numéros de comptes de charges à comportement particulier.
class ComptesDepenses {
  ComptesDepenses._();

  /// `saisie-depenses.html` : 613 (Locations) et 616 (Assurances) alimentent le
  /// KPI « Charges Fixes », tout le reste les « Charges Variables ».
  static const Set<String> fixes = {'613', '616'};
}

/// Une dépense reconstruite depuis ses écritures — Doc F6 Écran « Saisie des
/// Dépenses ».
class Depense {
  const Depense({
    required this.numeroPiece,
    required this.date,
    required this.libelle,
    required this.numeroCompteCharge,
    required this.libelleCompteCharge,
    required this.montant,
    required this.compteRegle,
    required this.payee,
    this.centreAnalytique,
  });

  final String numeroPiece;
  final DateTime date;
  final String libelle;
  final String numeroCompteCharge;
  final String libelleCompteCharge;
  final double montant;
  final String compteRegle;
  final bool payee;

  /// Centre analytique de la ligne de charge, `null` si non imputée.
  final String? centreAnalytique;

  String get categorie => '$numeroCompteCharge - $libelleCompteCharge';
}

/// Un centre de coût / profit de la comptabilité analytique.
class CentreAnalytique {
  const CentreAnalytique({
    required this.nom,
    required this.detail,
    required this.revenus,
    required this.couts,
  });

  final String nom;
  final String detail;
  final double revenus;
  final double couts;

  double get marge => revenus - couts;

  /// Taux de marge — indéfini si le centre n'a produit aucun revenu.
  double? get tauxMarge => revenus.abs() < 0.01 ? null : marge / revenus * 100;
}
