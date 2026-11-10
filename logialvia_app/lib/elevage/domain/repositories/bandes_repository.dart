import '../entities/bande.dart';

/// Dépôt des bandes — la mise en place qui donne son J1 au cycle.
abstract class BandesRepository {
  /// Toutes les bandes d'une filière, la plus récente d'abord.
  Future<List<Bande>> chargerBandes(String espece);

  /// La bande qui couvre cette date, s'il y en a une.
  ///
  /// Renvoie `null` plutôt que la dernière bande connue : afficher le cycle
  /// d'une bande clôturée sur un jour qu'elle ne couvre pas donnerait un jour
  /// de cycle faux, et donc une prophylaxie fausse.
  Future<Bande?> bandeCouvrant({
    required String espece,
    required DateTime date,
  });

  Future<Bande> creerBande({
    required String espece,
    required String code,
    required DateTime dateMiseEnBande,
    int? effectifInitial,
    String? observations,
  });

  Future<void> cloturerBande({required String id, required DateTime dateCloture});

  /// Recode une bande (code unique par filière) et trace le changement dans ses
  /// observations. Refuse un code déjà pris. Déclenche un tirage complet au prochain
  /// cycle : la bande de l'autre poste, refusée tant que ce code était pris, revient.
  Future<void> recoderBande({required String id, required String nouveauCode});

  /// Code attribué à ce poste (`P2`), `null` tant qu'il n'est pas appairé.
  Future<String?> codePoste();
}
