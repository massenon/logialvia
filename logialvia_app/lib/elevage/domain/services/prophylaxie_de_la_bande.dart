import '../entities/bande.dart';
import '../entities/parametres_elevage.dart';
import '../entities/soin.dart';

/// Une échéance de prophylaxie projetée sur une date réelle.
class EcheanceProjetee {
  const EcheanceProjetee({
    required this.echeance,
    required this.datePrevue,
    required this.jourDeCycle,
    this.soin,
  });

  final EcheanceProphylaxie echeance;

  /// Date réelle, calculée depuis la mise en bande.
  final DateTime datePrevue;

  final int jourDeCycle;

  /// Soin déjà créé depuis cette échéance pour cette bande, s'il existe.
  ///
  /// C'est ce qui distingue « à planifier » de « déjà planifié » et empêche de
  /// programmer deux fois le même rappel.
  final Soin? soin;

  bool get estPlanifie => soin != null;
  bool get estEffectue => soin?.estEffectue ?? false;

  /// Fin du délai d'attente, `null` si l'échéance n'en impose aucun.
  DateTime? get finRemanence => echeance.remanenceJours <= 0
      ? null
      : datePrevue.add(Duration(days: echeance.remanenceJours));
}

/// Projette le calendrier de prophylaxie sur les dates réelles d'une bande.
///
/// ## Ce que ce service débloque
///
/// `CALENDRIER_PROPHYLAXIE` indexe ses échéances sur le **jour du cycle**
/// (J1, J5, J15…) — arbitrage tranché par les preuves du contenu : une cure
/// « Jour 1/4 → 4/4 », un anti-stress « post-éclosion », un rappel Newcastle
/// qui se programme sur l'âge du sujet (Doc INDEX 11-untricies-novies). Lire ce
/// calendrier avec le jour du **mois** ferait rejouer le déparasitage tous les
/// 1ᵉʳ à des sujets d'âges quelconques.
///
/// Restait à savoir quand le cycle commence. `BANDES.dateMiseEnBande` le dit :
/// la projection devient possible, et « J5 » se convertit enfin en une date.
///
/// ⚠️ **Rien n'est projeté sans bande.** Sans date de mise en place, aucune
/// date n'est calculable — l'écran le dit et propose d'en déclarer une, plutôt
/// que de supposer que le cycle a commencé le 1ᵉʳ du mois.
class ProphylaxieDeLaBande {
  const ProphylaxieDeLaBande({
    required this.bande,
    required this.echeances,
    required this.soins,
  });

  final Bande bande;

  /// Échéances de la filière de la bande, toutes espèces confondues acceptées
  /// — le filtre est appliqué ici.
  final List<EcheanceProphylaxie> echeances;

  /// Soins existants, pour retrouver ceux déjà créés depuis une échéance.
  final List<Soin> soins;

  List<EcheanceProphylaxie> get _duCycle =>
      echeances.where((e) => e.espece == bande.espece).toList()
        ..sort((a, b) => a.jourCycle.compareTo(b.jourCycle));

  /// Toutes les échéances de la bande, datées.
  List<EcheanceProjetee> toutes() => [
    for (final e in _duCycle)
      EcheanceProjetee(
        echeance: e,
        jourDeCycle: e.jourCycle,
        datePrevue: bande.dateDuJourDeCycle(e.jourCycle),
        soin: _soinDe(e),
      ),
  ];

  /// Les échéances qui tombent ce jour-là — le contenu de la section
  /// « Traitements & Prophylaxie » de la fiche journalière.
  List<EcheanceProjetee> duJour(DateTime date) {
    final jour = bande.jourDeCycle(date);
    return toutes().where((p) => p.jourDeCycle == jour).toList();
  }

  Soin? _soinDe(EcheanceProphylaxie echeance) {
    for (final soin in soins) {
      if (soin.bandeId == bande.id &&
          soin.echeanceProphylaxieId == echeance.id) {
        return soin;
      }
    }
    return null;
  }
}
