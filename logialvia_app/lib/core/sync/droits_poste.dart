/// Droits du compte appairé et horloge du poste (`47g_`).
///
/// Deux choses que le serveur apprend au poste, et que le poste ne devine pas :
///
/// - **ce que son compte a le droit d'écrire** ([DroitsPoste]) : le poste ne PROPOSE et ne PUSHE
///   que cela, le reste attend (« en attente de droit ») au lieu d'être refusé pour toujours ;
/// - **de combien son horloge s'écarte de celle du serveur** ([AnalyseHorloge]) : une horloge en
///   avance écrit des instants de saisie dans le futur et gagnerait toutes les comparaisons
///   « dernier écrivain gagne » ; le serveur les refuse (`horloge_en_avance`), le poste suspend
///   donc l'envoi tant que l'horloge n'est pas corrigée.
library;

/// Codes de refus stables du serveur : le poste les reconnaît, jamais le texte.
const String codeDroitInsuffisant = 'droit_insuffisant';
const String codeHorlogeEnAvance = 'horloge_en_avance';

/// Tolérance du serveur (`GardeHorloge::TOLERANCE_SECONDES`) : au-delà, l'envoi est refusé.
const Duration toleranceHorloge = Duration(minutes: 5);

/// Au-delà, le poste AVERTIT (modale de synchronisation, onglet Appairage).
const Duration seuilAvertissementHorloge = Duration(minutes: 2);

/// Cles de ligne qui sont des instants de saisie ecrits par le poste (`GardeHorloge::CLES_INSTANT`).
const List<String> clesInstantSaisie = [
  'updated_at',
  'horodatage',
  'saisi_le',
  'supprime_le',
  'archive_le',
];

/// Ce que le compte appairé a le droit de faire, tel que le serveur l'annonce
/// (connexion, `GET /api/auth/me`, chaque tirage). Jamais de secret.
class DroitsPoste {
  const DroitsPoste({
    required this.compte,
    this.nom = '',
    this.roles = const [],
    this.permissions = const [],
    this.tablesEcrites = const {},
    this.tablesLues = const {},
    this.demandes = const {},
  });

  /// Identifiant du compte web (`username`).
  final String compte;
  final String nom;
  final List<String> roles;
  final List<String> permissions;

  /// Tables de FAITS que le compte peut pousser (`TableSync::peutEcrire`).
  final Set<String> tablesEcrites;
  final Set<String> tablesLues;

  /// Types de demandes de référentiel que le compte peut proposer.
  final Set<String> demandes;

  bool peutEcrireTable(String table) => tablesEcrites.contains(table);

  bool peutProposer(String type) => demandes.contains(type);

  /// `null` si la réponse ne porte pas de droits exploitables (ancien serveur).
  static DroitsPoste? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    Set<String> ensemble(Object? v) =>
        v is List ? v.whereType<String>().toSet() : <String>{};
    final compte = brut['compte'];
    if (compte is! String) return null;
    return DroitsPoste(
      compte: compte,
      nom: brut['nom'] is String ? brut['nom'] as String : '',
      roles: brut['roles'] is List
          ? (brut['roles'] as List).whereType<String>().toList()
          : const [],
      permissions: brut['permissions'] is List
          ? (brut['permissions'] as List).whereType<String>().toList()
          : const [],
      tablesEcrites: ensemble(brut['tables_ecrites']),
      tablesLues: ensemble(brut['tables_lues']),
      demandes: ensemble(brut['demandes']),
    );
  }

  Map<String, Object?> versJson() => {
    'compte': compte,
    'nom': nom,
    'roles': roles,
    'permissions': permissions,
    'tables_ecrites': tablesEcrites.toList()..sort(),
    'tables_lues': tablesLues.toList()..sort(),
    'demandes': demandes.toList()..sort(),
  };
}

/// Jugement du poste sur l'écart de son horloge.
enum EtatHorloge {
  /// Écart ordinaire (moins de 2 minutes, ou retard modéré).
  juste,

  /// En avance de plus de 2 minutes mais dans la tolérance : avertissement.
  avanceAvertissement,

  /// En avance de plus de la tolérance : le serveur refuserait les saisies, l'envoi est suspendu.
  avanceBloquante,

  /// En retard de plus de la tolérance : les saisies perdraient contre celles des autres postes.
  /// Avertissement, pas de blocage.
  retard,
}

class AnalyseHorloge {
  const AnalyseHorloge(this.ecart, this.etat);

  /// Positif : le poste est EN AVANCE sur le serveur.
  final Duration ecart;
  final EtatHorloge etat;

  /// L'envoi des saisies est suspendu (elles restent en attente, rien n'est perdu).
  bool get suspendEnvoi => etat == EtatHorloge.avanceBloquante;

  /// Faut-il le dire à l'utilisatrice ?
  bool get aAvertir => etat != EtatHorloge.juste;

  /// Message français, `null` quand l'horloge est juste.
  String? get message {
    switch (etat) {
      case EtatHorloge.juste:
        return null;
      case EtatHorloge.avanceAvertissement:
        return 'L\'horloge de ce poste avance de ${formaterDuree(ecart)} : '
            'corrigez la date et l\'heure du poste avant que l\'écart ne '
            'bloque l\'envoi de vos saisies.';
      case EtatHorloge.avanceBloquante:
        return 'L\'horloge de ce poste avance de ${formaterDuree(ecart)} : '
            'corrigez la date et l\'heure du poste. L\'envoi de vos saisies '
            'est suspendu (elles sont conservées et partiront dès que '
            'l\'horloge sera juste).';
      case EtatHorloge.retard:
        return 'L\'horloge de ce poste retarde de ${formaterDuree(-ecart)} : '
            'vos saisies risquent de perdre contre celles des autres postes. '
            'Corrigez la date et l\'heure du poste.';
    }
  }
}

/// Juge un écart (poste − serveur). Égalité à la tolérance : acceptée, comme le serveur.
AnalyseHorloge analyserHorloge(Duration ecart) {
  final EtatHorloge etat;
  if (ecart > toleranceHorloge) {
    etat = EtatHorloge.avanceBloquante;
  } else if (ecart > seuilAvertissementHorloge) {
    etat = EtatHorloge.avanceAvertissement;
  } else if (ecart < -toleranceHorloge) {
    etat = EtatHorloge.retard;
  } else {
    etat = EtatHorloge.juste;
  }
  return AnalyseHorloge(ecart, etat);
}

/// Écart de l'horloge du poste : le poste a demandé à [avant], reçu la réponse à [apres] ; le
/// serveur a daté sa réponse [serveur] (au milieu de l'échange, à la louche). Positif : en avance.
Duration mesurerDecalage({
  required DateTime avant,
  required DateTime apres,
  required DateTime serveur,
}) {
  final milieu = avant.add(apres.difference(avant) ~/ 2);
  return milieu.difference(serveur);
}

/// « 2 ans », « 2 jours », « 1 h 05 », « 7 min » : même rendu que `GardeHorloge::duree`.
///
/// Au-delà d'une minute la durée est arrondie à la minute la plus proche : un écart mesuré est
/// toujours entaché de la latence du réseau (« 1 h 59 min 59 s » se lit « 2 h »).
String formaterDuree(Duration d) {
  var s = (d.inMilliseconds.abs() / 1000).round();
  if (s >= 60) s = (s / 60).round() * 60;
  if (s >= 365 * 86400) {
    final n = s ~/ (365 * 86400);
    return '$n ${n > 1 ? 'ans' : 'an'}';
  }
  if (s >= 86400) {
    final n = s ~/ 86400;
    return '$n ${n > 1 ? 'jours' : 'jour'}';
  }
  if (s >= 3600) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }
  if (s >= 60) return '${s ~/ 60} min';
  return '$s s';
}
