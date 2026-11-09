import '../../../elevage/domain/services/rappels_prophylaxie.dart';
import '../../../elevage/domain/services/reperes_zootechniques.dart';
import '../entities/tableau_bord_principal.dart';

/// Article dont le stock est passe sous son seuil d'alerte.
class ArticleEnAlerte {
  const ArticleEnAlerte({
    required this.libelle,
    required this.stock,
    required this.seuil,
    required this.unite,
    required this.estIntrant,
  });

  final String libelle;
  final int stock;
  final int seuil;
  final String unite;

  /// `true` : contexte Approvisionnement (`INTRANTS`).
  /// `false` : contexte Commercial (`PRODUITS_VENDABLES`).
  final bool estIntrant;
}

/// Chiffre d'affaires d'une periode, ventile par activite.
class VentilationChiffreAffaires {
  const VentilationChiffreAffaires({
    required this.total,
    required this.avicole,
    required this.commerceAnnexe,
  });

  final double total;
  final double avicole;
  final double commerceAnnexe;
}

/// Encours client : reste a payer sur les ventes en statut 'Avance'.
class EncoursClients {
  const EncoursClients({required this.montant, required this.nombreVentes});

  final double montant;
  final int nombreVentes;
}

/// Statistiques agregees du couvoir.
class StatistiquesCouveuse {
  const StatistiquesCouveuse({
    required this.cyclesEnCours,
    required this.oeufsCharges,
    required this.tauxEclosionMoyen,
    required this.poussinsAttendus,
    required this.eclosionImminente,
  });

  final int cyclesEnCours;
  final int oeufsCharges;
  final double? tauxEclosionMoyen;
  final int poussinsAttendus;

  /// Code d'incubation dont l'eclosion (J+21) tombe sous 3 jours, si elle existe.
  final String? eclosionImminente;
}

/// Couche de **lecture seule** transverse aux Bounded Contexts — Doc F2.
///
/// Justification DDD explicite : Doc C1 §4 interdit a un `usecase` d'un
/// contexte d'appeler le `Repository` d'un autre. Cette regle vise le **chemin
/// d'ecriture** (le couplage comportemental entre contextes, qui doit passer
/// par des evenements de domaine). Un tableau de bord est un **modele de
/// lecture** : il n'ecrit rien, ne declenche aucune regle metier, et n'a de
/// sens que transverse — un dashboard qui ne verrait qu'un seul contexte ne
/// serait pas un dashboard. Il est donc isole ici, dans son propre contexte
/// `pilotage/`, plutot que dissemine en dependances croisees entre Commercial,
/// Elevage et Approvisionnement.
abstract class TableauBordRepository {
  Future<VentilationChiffreAffaires> chiffreAffaires({
    required DateTime debut,
    required DateTime fin,
  });

  Future<EncoursClients> encoursClients();

  /// Articles sous seuil, intrants et produits vendables confondus.
  Future<List<ArticleEnAlerte>> articlesSousSeuil();

  /// Les echeances de prophylaxie echues et jamais planifiees, a [date].
  ///
  /// Le rappel du tableau de bord ne voyait que les soins deja dates. Une
  /// echeance J5 tombee hier et oubliee ne declenchait donc rien -- le silence
  /// exact du cas ou l'alerte servait le plus.
  Future<List<RappelProphylaxie>> rappelsProphylaxie(DateTime date);

  /// Somme des effectifs du dernier jour saisi de chaque filiere active.
  Future<int> effectifCheptel(Set<String> especesActives);

  Future<StatistiquesCouveuse> statistiquesCouveuse();

  /// `null` si aucune journee n'a encore ete saisie pour cette espece.
  Future<RecensementFiliere?> recensementFiliere(String espece);

  /// Gain moyen quotidien (g/j/sujet) de chaque filiere sur les [jours] derniers jours,
  /// d'apres les pesees de la fiche (`poids_general_g`). Une filiere sans deux pesees n'a
  /// pas de GMQ (`47e_`).
  Future<Map<String, ResultatGmq>> gmqParFiliere(
    Set<String> especes, {
    int jours = 28,
  });

  Future<List<MeilleureVente>> meilleuresVentes({
    required DateTime debut,
    required DateTime fin,
    int limite = 5,
  });

  Future<List<ActiviteJournal>> activitesDuJour({int limite = 10});

  Future<List<TransactionRecente>> ventesRecentes({int limite = 3});

  Future<List<PointMensuel>> evolutionMensuelle({int nombreMois = 6});

  Future<List<PointJournalier>> evolutionJournaliere({int nombreJours = 6});

  /// Soins dont l'echeance est passee ou proche, tries par date.
  Future<List<ProchainSoin>> prochainsSoins({int limite = 5});

  /// Nombre de soins en statut 'En retard'.
  Future<int> nombreAlertesSanitaires();
}

/// Echeance veterinaire affichee sur le Dashboard Élevage.
class ProchainSoin {
  const ProchainSoin({
    required this.espece,
    required this.typeSoin,
    required this.datePrevue,
    required this.statut,
    required this.observations,
  });

  final String espece;
  final String typeSoin;
  final DateTime datePrevue;
  final String statut;
  final String? observations;

  bool get estEnRetard => statut == 'En retard';
}
