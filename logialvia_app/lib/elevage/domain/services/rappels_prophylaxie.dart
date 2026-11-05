import '../entities/bande.dart';
import '../entities/parametres_elevage.dart';
import '../entities/soin.dart';
import 'prophylaxie_de_la_bande.dart';

/// Une échéance de prophylaxie **échue et jamais planifiée**.
class RappelProphylaxie {
  const RappelProphylaxie({
    required this.espece,
    required this.bande,
    required this.projetee,
    required this.joursDeRetard,
  });

  final String espece;
  final Bande bande;
  final EcheanceProjetee projetee;

  /// 0 le jour même, positif ensuite.
  final int joursDeRetard;

  bool get enRetard => joursDeRetard > 0;

  EcheanceProphylaxie get echeance => projetee.echeance;
  DateTime get datePrevue => projetee.datePrevue;
}

/// Les échéances du calendrier de prophylaxie qui sont dues et qu'on a oubliées
/// de planifier.
///
/// ## Le trou que ce service ferme
///
/// Le rappel « Prophylaxie du Jour » du tableau de bord ne connaît que les
/// soins **datés** du registre : ceux qu'on a explicitement planifiés. Or le
/// calendrier de prophylaxie, lui, vit en **jours de cycle** (J1, J5, J15) et
/// ne devient une date qu'une fois la bande déclarée.
///
/// Conséquence, avant ce service : une échéance J5 dont la date réelle était
/// hier ne déclenchait rien du tout, parce que personne n'était allé la
/// planifier depuis la fiche. Le rappel se taisait précisément dans le cas où
/// il aurait été le plus utile — celui de l'oubli.
///
/// ## Ce qu'il ne fait pas
///
/// Il ne planifie rien tout seul. Créer le soin exige un **type d'action**
/// (Vaccination, Traitement curatif, Vermifuge, Vitamines) que le calendrier
/// ne porte pas : le déduire du libellé marcherait pour « Vaccin Newcastle » et
/// se tromperait sur « Contrôle Oxygénation ». Le choix reste à l'éleveur, sur
/// la fiche. Ce service dit **qu'il faut y aller**, pas ce qu'il faut y mettre.
class RappelsProphylaxie {
  const RappelsProphylaxie({
    required this.bandes,
    required this.echeances,
    required this.soins,
  });

  /// Les bandes **ouvertes**. Une bande clôturée n'attend plus rien.
  final List<Bande> bandes;
  final List<EcheanceProphylaxie> echeances;
  final List<Soin> soins;

  /// Les échéances dues à [date] ou avant, non planifiées, bande par bande.
  ///
  /// Les retards viennent en premier : un traitement oublié il y a trois jours
  /// est plus urgent que celui du matin.
  List<RappelProphylaxie> dues(DateTime date) {
    final jour = DateTime(date.year, date.month, date.day);
    final rappels = <RappelProphylaxie>[];

    for (final bande in bandes) {
      if (bande.dateCloture != null) continue;

      final projection = ProphylaxieDeLaBande(
        bande: bande,
        echeances: echeances,
        soins: soins,
      );

      for (final projetee in projection.toutes()) {
        if (projetee.estPlanifie) continue;
        final prevue = DateTime(
          projetee.datePrevue.year,
          projetee.datePrevue.month,
          projetee.datePrevue.day,
        );
        if (prevue.isAfter(jour)) continue;

        rappels.add(
          RappelProphylaxie(
            espece: bande.espece,
            bande: bande,
            projetee: projetee,
            joursDeRetard: jour.difference(prevue).inDays,
          ),
        );
      }
    }

    rappels.sort((a, b) {
      final parDate = a.datePrevue.compareTo(b.datePrevue);
      if (parDate != 0) return parDate;
      return a.espece.compareTo(b.espece);
    });
    return rappels;
  }

  /// Le nombre d'espèces concernées — ce que l'alerte annonce, parce que c'est
  /// le nombre de fiches à ouvrir.
  static Set<String> especesConcernees(List<RappelProphylaxie> rappels) => {
    for (final r in rappels) r.espece,
  };
}
