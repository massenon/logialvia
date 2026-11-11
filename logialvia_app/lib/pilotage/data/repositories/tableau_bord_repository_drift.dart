import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../elevage/data/repositories/bandes_repository_drift.dart';
import '../../../elevage/data/repositories/parametres_elevage_repository_drift.dart';
import '../../../elevage/data/repositories/soins_repository_drift.dart';
import '../../../elevage/domain/entities/cycle_incubation.dart';
import '../../../elevage/domain/services/rappels_prophylaxie.dart';
import '../../../elevage/domain/services/reperes_zootechniques.dart';
import '../../domain/entities/tableau_bord_principal.dart';
import '../../domain/repositories/tableau_bord_repository.dart';

/// Implementation Drift du modele de lecture des tableaux de bord.
///
/// Uniquement l'API typee de Drift — aucune requete construite par
/// concatenation de chaine (Doc I3 §1, Strict Avoid §1).
class TableauBordRepositoryDrift implements TableauBordRepository {
  const TableauBordRepositoryDrift(this._db);

  final AppDatabase _db;

  /// Libelle de la categorie « jeune » affichee sur la carte de recensement.
  /// Valeurs relevees dans les fiches reelles (`fiche-goliaths.html` l.125 :
  /// « Goliathaux (Immatures) »), pas inventees.
  static const Map<String, String> _libelleJeunesParEspece = {
    'goliaths': 'Goliathaux',
    'pintades': 'Pintadaux',
    'lapins': 'Lapereaux',
    'escargots': 'Naissains',
    'ovins': 'Agneaux',
    'poulets': 'Poulettes',
    'pondeuses': 'Poulettes',
    'poissons-chats': 'Juvéniles',
  };

  static const Map<String, String> _libelleEspece = {
    'goliaths': 'Goliaths',
    'pintades': 'Pintades',
    'lapins': 'Lapins',
    'escargots': 'Escargots',
    'ovins': 'Ovins',
    'poulets': 'Poulets',
    'pondeuses': 'Pondeuses',
    'poissons-chats': 'Poissons-Chats',
  };

  /// Route de la fiche d'elevage de chaque filiere.
  ///
  /// ⚠️ Le chemin ne se deduit PAS du code espece : poulets et pondeuses
  /// partagent un seul ecran a deux onglets (`/elevage/poulets-pondeuses`,
  /// Doc H2). Construire `'/elevage/$espece'` produisait `/elevage/poulets`
  /// et `/elevage/pondeuses`, qu'aucune route ne declare — d'ou
  /// « GoException: no routes for location: /elevage/poulets » au clic sur
  /// la carte de la filiere.
  static const Map<String, String> _routeEspece = {
    'goliaths': '/elevage/goliaths',
    'pintades': '/elevage/pintades',
    'lapins': '/elevage/lapins',
    'escargots': '/elevage/escargots',
    'ovins': '/elevage/ovins',
    'poulets': '/elevage/poulets-pondeuses',
    'pondeuses': '/elevage/poulets-pondeuses',
    'poissons-chats': '/elevage/poissons-chats',
  };

  /// Repli sur le tableau de bord Elevage pour une espece inconnue, plutot
  /// qu'une route inexistante.
  static String _route(String espece) =>
      _routeEspece[espece] ?? '/elevage/dashboard';

  static const Map<String, String> _iconeEspece = {
    'goliaths': 'pets',
    'pintades': 'pets',
    'lapins': 'cruelty_free',
    'escargots': 'eco',
    'ovins': 'grass',
    'poulets': 'egg_alt',
    'pondeuses': 'egg_alt',
    'poissons-chats': 'set_meal',
  };

  @override
  Future<VentilationChiffreAffaires> chiffreAffaires({
    required DateTime debut,
    required DateTime fin,
  }) async {
    final lignes = _db.lignesVente;
    final ventes = _db.ventes;
    final produits = _db.produitsVendables;

    final requete = _db.select(lignes).join([
      innerJoin(ventes, ventes.ref.equalsExp(lignes.venteRef)),
      innerJoin(produits, produits.id.equalsExp(lignes.produitId)),
    ]);
    // ⚠️ CORRECTION de K4 §2, verifiee a la compilation sur la version
    // reellement utilisee ici (Drift 2.34.3) : K4 prescrivait le chainage
    // `.and(...)` et declarait l'operateur `&` absent (constat fait sur Drift
    // 2.31). C'est l'inverse sur 2.34 — `Expression.and()` y est une methode
    // **statique** prenant un `Iterable`, donc `a.and(b)` ne compile pas, alors
    // que `a & b` fonctionne. Toujours verifier la version avant de choisir le
    // pattern, comme K4 §2 le recommandait deja.
    requete.where(
      ventes.dateVente.isBetweenValues(debut, fin) &
          ventes.status.equals('Annulée').not(),
    );

    var total = 0.0;
    var avicole = 0.0;
    var commerce = 0.0;

    for (final ligne in await requete.get()) {
      final l = ligne.readTable(lignes);
      final montant = l.qte * l.pu;
      total += montant;
      if (ligne.readTable(produits).cat == 'Commerce Annexe') {
        commerce += montant;
      } else {
        avicole += montant;
      }
    }

    return VentilationChiffreAffaires(
      total: total,
      avicole: avicole,
      commerceAnnexe: commerce,
    );
  }

  @override
  Future<EncoursClients> encoursClients() async {
    final lignes = await (_db.select(
      _db.ventes,
    )..where((v) => v.status.equals('Avance'))).get();

    final montant = lignes.fold<double>(
      0,
      (somme, v) => somme + (v.total - v.paye),
    );
    return EncoursClients(montant: montant, nombreVentes: lignes.length);
  }

  @override
  Future<List<RappelProphylaxie>> rappelsProphylaxie(DateTime date) async {
    // Lecture seule d'un contexte voisin : c'est l'exception accordee au
    // contexte Pilotage, dont le role est precisement d'agreger les autres.
    final bandes = await BandesRepositoryDrift(_db).chargerToutes();
    if (bandes.isEmpty) return const [];

    final echeances = await ParametresElevageRepositoryDrift(
      _db,
    ).chargerProphylaxie();
    if (echeances.isEmpty) return const [];

    final soins = await SoinsRepositoryDrift(_db).chargerSoins();

    return RappelsProphylaxie(
      bandes: bandes,
      echeances: echeances,
      soins: soins,
    ).dues(date);
  }

  @override
  Future<List<ArticleEnAlerte>> articlesSousSeuil() async {
    // Comparaison colonne-a-colonne. K4 §2 Bug #3b annoncait un echec de
    // `isSmallerOrEqual` sur Drift 2.31 et prescrivait un `CustomExpression`.
    // Verifie sur la version reellement utilisee ici (Drift 2.34) : l'API typee
    // fonctionne. Elle est donc preferee au SQL brut (Strict Avoid §1).
    final intrants = await (_db.select(
      _db.intrants,
    )..where((i) => i.stock.isSmallerOrEqual(i.threshold))).get();

    final produits = await (_db.select(
      _db.produitsVendables,
    )..where((p) => p.stock.isSmallerOrEqual(p.threshold))).get();

    return [
      for (final i in intrants)
        ArticleEnAlerte(
          libelle: i.name,
          stock: i.stock,
          seuil: i.threshold,
          unite: i.unit,
          estIntrant: true,
        ),
      for (final p in produits)
        ArticleEnAlerte(
          libelle: p.name,
          stock: p.stock,
          seuil: p.threshold,
          unite: p.unit,
          estIntrant: false,
        ),
    ];
  }

  @override
  Future<int> effectifCheptel(Set<String> especesActives) async {
    var total = 0;
    for (final espece in especesActives) {
      final derniere = await _derniereJourneeSaisie(espece);
      total += derniere?.effectif ?? 0;
    }
    return total;
  }

  @override
  Future<StatistiquesCouveuse> statistiquesCouveuse() async {
    final tous = await _db.select(_db.cycleCouveuse).get();
    final enCours = tous.where((c) => c.statut == 'En Incubation').toList();
    final eclos = tous
        .where((c) => c.poussinsNes != null && c.oeufsCouves > 0)
        .toList();

    final oeufsCharges = enCours.fold<int>(0, (s, c) => s + c.oeufsCouves);

    // Moyenne sur zero echantillon n'a pas de sens : `null` -> affiche « — ».
    final tauxEclosion = eclos.isEmpty
        ? null
        : eclos.fold<double>(
                0,
                (s, c) => s + (c.poussinsNes! / c.oeufsCouves) * 100,
              ) /
              eclos.length;

    // Estimation : oeufs en cours x taux d'eclosion historique. Sans historique
    // d'eclosion, aucune projection n'est possible — 0 plutot qu'un chiffre
    // fabrique.
    final poussinsAttendus = tauxEclosion == null
        ? 0
        : (oeufsCharges * tauxEclosion / 100).round();

    // ⚠️ CORRIGE : Doc F3 enoncait « eclosion attendue = date + 21 jours »
    // comme regle unique. La duree depend en realite de l'espece
    // (`cycle-couveuse.html` l.232-233) : Goliath 21 j, Pintade 27 j.
    // Avec un +21 uniforme, l'alerte « eclosion imminente » se declenchait
    // six jours trop tot sur les pintades.
    final maintenant = DateTime.now();
    String? imminente;
    for (final cycle in enCours) {
      final eclosionPrevue = cycle.dateIncubation.add(
        Duration(days: EspeceCouvable.dureeJours(cycle.espece)),
      );
      final joursRestants = eclosionPrevue.difference(maintenant).inDays;
      if (joursRestants >= 0 && joursRestants <= 3) {
        imminente = cycle.codeIncubation;
        break;
      }
    }

    return StatistiquesCouveuse(
      cyclesEnCours: enCours.length,
      oeufsCharges: oeufsCharges,
      tauxEclosionMoyen: tauxEclosion,
      poussinsAttendus: poussinsAttendus,
      eclosionImminente: imminente,
    );
  }

  @override
  Future<RecensementFiliere?> recensementFiliere(String espece) async {
    final derniere = await _derniereJourneeSaisie(espece);
    if (derniere == null) {
      return RecensementFiliere(
        espece: espece,
        libelle: _libelleEspece[espece] ?? espece,
        icone: _iconeEspece[espece] ?? 'pets',
        route: _route(espece),
        effectif: 0,
        effectifMatures: 0,
        libelleJeunes: _libelleJeunesParEspece[espece] ?? 'Jeunes',
        effectifJeunes: 0,
        tauxMortalite: 0,
        aDesDonnees: false,
      );
    }

    // Structure de categories relevee dans les fiches reelles :
    // cat1 = Poussin, cat2 = Jeune/Immature (Goliathau, Pintadau…),
    // cat3 = Mature (eligible a la vente).
    return RecensementFiliere(
      espece: espece,
      libelle: _libelleEspece[espece] ?? espece,
      icone: _iconeEspece[espece] ?? 'pets',
      route: _route(espece),
      effectif: derniere.effectif,
      effectifMatures: derniere.effCat3Day,
      libelleJeunes: _libelleJeunesParEspece[espece] ?? 'Jeunes',
      effectifJeunes: derniere.effCat2Day,
      tauxMortalite: await _tauxMortaliteDuMois(espece),
      aDesDonnees: true,
    );
  }

  @override
  Future<List<MeilleureVente>> meilleuresVentes({
    required DateTime debut,
    required DateTime fin,
    int limite = 5,
  }) async {
    final lignes = _db.lignesVente;
    final ventes = _db.ventes;
    final produits = _db.produitsVendables;

    final requete = _db.select(lignes).join([
      innerJoin(ventes, ventes.ref.equalsExp(lignes.venteRef)),
      innerJoin(produits, produits.id.equalsExp(lignes.produitId)),
    ]);
    requete.where(
      ventes.dateVente.isBetweenValues(debut, fin) &
          ventes.status.equals('Annulée').not(),
    );

    final cumuls = <String, ({double qte, double ca, String activite})>{};
    for (final ligne in await requete.get()) {
      final l = ligne.readTable(lignes);
      final activite = ligne.readTable(produits).cat == 'Commerce Annexe'
          ? 'Commerce'
          : 'Avicole';
      final precedent = cumuls[l.name];
      cumuls[l.name] = (
        qte: (precedent?.qte ?? 0) + l.qte,
        ca: (precedent?.ca ?? 0) + l.qte * l.pu,
        activite: activite,
      );
    }

    final resultat =
        cumuls.entries
            .map(
              (e) => MeilleureVente(
                produit: e.key,
                quantite: e.value.qte,
                chiffreAffaires: e.value.ca,
                activite: e.value.activite,
              ),
            )
            .toList()
          ..sort((a, b) => b.chiffreAffaires.compareTo(a.chiffreAffaires));

    return resultat.take(limite).toList();
  }

  @override
  Future<List<ActiviteJournal>> activitesDuJour({int limite = 10}) async {
    // Le fil d'activite s'appuie sur AUDIT_LOGS (Doc I3 §6) plutot que sur une
    // table `JournalActivite` dediee : la tracabilite existante porte deja
    // horodatage, auteur, action et entite — dupliquer l'information dans une
    // seconde table creerait deux sources de verite (Strict Avoid §12).
    final debutJour = _minuit(DateTime.now());

    final journal = _db.auditLogs;
    final utilisateurs = _db.utilisateurs;

    final requete =
        _db.select(journal).join([
            leftOuterJoin(
              utilisateurs,
              utilisateurs.id.cast<String>().equalsExp(journal.utilisateurId),
            ),
          ])
          ..where(journal.horodatage.isBiggerOrEqualValue(debutJour))
          ..orderBy([OrderingTerm.desc(journal.horodatage)])
          ..limit(limite);

    return [
      for (final ligne in await requete.get())
        () {
          final log = ligne.readTable(journal);
          return ActiviteJournal(
            libelle: _libelleActivite(
              log.action,
              log.entiteConcernee,
              log.entiteId,
            ),
            horodatage: log.horodatage,
            auteur:
                ligne.readTableOrNull(utilisateurs)?.nom ?? log.utilisateurId,
            accent: _accentActivite(log.action),
          );
        }(),
    ];
  }

  @override
  Future<List<TransactionRecente>> ventesRecentes({int limite = 3}) async {
    final lignes =
        await (_db.select(_db.ventes)
              ..orderBy([(v) => OrderingTerm.desc(v.dateVente)])
              ..limit(limite))
            .get();

    return [
      for (final v in lignes)
        TransactionRecente(
          libelle: '${v.ref} · ${v.client}',
          montant: v.status == 'Avance' ? v.paye : v.total,
          enAvance: v.status == 'Avance',
        ),
    ];
  }

  @override
  Future<List<PointMensuel>> evolutionMensuelle({int nombreMois = 6}) async {
    final maintenant = DateTime.now();
    final points = <PointMensuel>[];

    for (var i = nombreMois - 1; i >= 0; i--) {
      final debut = DateTime(maintenant.year, maintenant.month - i, 1);
      final fin = DateTime(
        maintenant.year,
        maintenant.month - i + 1,
        1,
      ).subtract(const Duration(milliseconds: 1));

      final ca = await chiffreAffaires(debut: debut, fin: fin);
      points.add(
        PointMensuel(
          libelleMois: _abreviationMois[debut.month]!,
          chiffreAffaires: ca.total,
          // Les depenses viennent des modules Achats (Doc F5) et Comptabilite
          // (Doc F6), non encore implementes — 0 tant qu'aucune depense ne peut
          // exister en base. Jamais une valeur simulee.
          depenses: 0,
        ),
      );
    }
    return points;
  }

  @override
  Future<List<PointJournalier>> evolutionJournaliere({
    int nombreJours = 6,
  }) async {
    final aujourdhui = _minuit(DateTime.now());
    final points = <PointJournalier>[];

    for (var i = nombreJours - 1; i >= 0; i--) {
      final debut = aujourdhui.subtract(Duration(days: i));
      final fin = debut
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      final ca = await chiffreAffaires(debut: debut, fin: fin);
      points.add(
        PointJournalier(
          libelleJour:
              '${debut.day.toString().padLeft(2, '0')}/'
              '${debut.month.toString().padLeft(2, '0')}',
          recettes: ca.total,
          depenses: 0,
        ),
      );
    }
    return points;
  }

  @override
  Future<List<ProchainSoin>> prochainsSoins({int limite = 5}) async {
    final lignes =
        await (_db.select(_db.soinsCalendrier)
              ..where((s) => s.statut.isNotIn(const ['Effectué']))
              ..orderBy([(s) => OrderingTerm.asc(s.datePrevue)])
              ..limit(limite))
            .get();

    return [
      for (final s in lignes)
        ProchainSoin(
          espece: _libelleEspece[s.espece] ?? s.espece,
          typeSoin: s.typeSoin,
          datePrevue: s.datePrevue,
          // Planifie dont la date est passee = EN RETARD (`47e_`), sans attendre qu'on le dise.
          statut: _statutEffectif(s.statut, s.datePrevue),
          observations: s.observations,
        ),
    ];
  }

  /// « Planifié » dont la date est passée est en retard ; les autres statuts ne changent pas.
  static String _statutEffectif(String statut, DateTime datePrevue) {
    final maintenant = DateTime.now();
    final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    return statut == 'Planifié' && datePrevue.isBefore(aujourdhui)
        ? 'En retard'
        : statut;
  }

  @override
  Future<int> nombreAlertesSanitaires() async {
    final lignes = await (_db.select(
      _db.soinsCalendrier,
    )..where((s) => s.statut.isIn(const ['En retard', 'Planifié']))).get();
    return lignes
        .where((s) => _statutEffectif(s.statut, s.datePrevue) == 'En retard')
        .length;
  }

  // ---------------------------------------------------------------- internes

  Future<FicheJourneeRow?> _derniereJourneeSaisie(String espece) {
    return (_db.select(_db.ficheJournee)
          ..where((f) => f.espece.equals(espece) & f.isRecorded.equals(true))
          ..orderBy([(f) => OrderingTerm.desc(f.date)])
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<Map<String, ResultatGmq>> gmqParFiliere(
    Set<String> especes, {
    int jours = 28,
  }) async {
    final maintenant = DateTime.now();
    final debut = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    ).subtract(Duration(days: jours));
    final resultat = <String, ResultatGmq>{};
    for (final espece in especes) {
      final lignes =
          await (_db.select(_db.ficheJournee)..where(
                (f) =>
                    f.espece.equals(espece) &
                    f.isRecorded.equals(true) &
                    f.poidsGeneralG.isNotNull() &
                    f.date.isBiggerOrEqualValue(debut),
              ))
              .get();
      final gmq = ReperesZootechniques.gmqSurPesees([
        for (final l in lignes)
          (date: l.date, poidsTotalG: l.poidsGeneralG!, effectif: l.effectif),
      ]);
      if (gmq != null) resultat[espece] = gmq;
    }
    return resultat;
  }

  /// (mortalite du mois / effectif de debut de mois) x 100 — Doc F3 §1.
  Future<double> _tauxMortaliteDuMois(String espece) async {
    final maintenant = DateTime.now();
    final debutMois = DateTime(maintenant.year, maintenant.month);

    final jours =
        await (_db.select(_db.ficheJournee)
              ..where(
                (f) =>
                    f.espece.equals(espece) &
                    f.isRecorded.equals(true) &
                    f.date.isBiggerOrEqualValue(debutMois),
              )
              ..orderBy([(f) => OrderingTerm.asc(f.date)]))
            .get();

    if (jours.isEmpty) return 0;

    final morts = jours.fold<int>(
      0,
      (s, j) => s + j.mortCat1 + j.mortCat2 + j.mortCat3 + (j.mortCat4 ?? 0),
    );

    // Effectif EXPOSE au risque (`47e_`) = effectif de debut de mois (reconstitue depuis
    // le 1er jour saisi : on lui rend ce qu'il a retire et on lui retire ce qu'il a
    // ajoute) + toutes les entrees du mois. Ignorer les entrees faisait depasser 100 %
    // quand une bande arrivait en cours de mois.
    final premier = jours.first;
    final debutDeMois =
        premier.effectif -
        premier.achat -
        premier.ne +
        premier.mortCat1 +
        premier.mortCat2 +
        premier.mortCat3 +
        (premier.mortCat4 ?? 0) +
        premier.vente +
        premier.donCat1 +
        premier.donCat2 +
        premier.donCat3 +
        (premier.donCat4 ?? 0);
    final entrees = jours.fold<int>(0, (s, j) => s + j.achat + j.ne);
    return ReperesZootechniques.tauxMortaliteCumule(
          morts: morts,
          effectifDepart: debutDeMois,
          entrees: entrees,
        ) ??
        0;
  }

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);

  static const Map<int, String> _abreviationMois = {
    1: 'Jan',
    2: 'Fév',
    3: 'Mar',
    4: 'Avr',
    5: 'Mai',
    6: 'Jun',
    7: 'Jul',
    8: 'Aoû',
    9: 'Sep',
    10: 'Oct',
    11: 'Nov',
    12: 'Déc',
  };

  static String _libelleActivite(
    String action,
    String entite,
    String entiteId,
  ) {
    return switch (action) {
      'connexion' => 'Session $entiteId',
      'suppression' => '$entite $entiteId supprimé(e)',
      'modification' => '$entite $entiteId modifié(e)',
      'cloture' => 'Clôture — $entite $entiteId',
      'decloture' => 'Déclôture — $entite $entiteId',
      _ => '$entite $entiteId',
    };
  }

  static AccentKpi _accentActivite(String action) {
    return switch (action) {
      'suppression' => AccentKpi.erreur,
      'cloture' || 'decloture' => AccentKpi.or,
      'modification' => AccentKpi.info,
      _ => AccentKpi.navy,
    };
  }
}
