import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../domain/plan_syscohada.dart';

/// Rapport d'une renumérotation.
class RapportMigrationPlan {
  const RapportMigrationPlan({
    required this.lignesRenumerotees,
    required this.debitTotal,
    required this.creditTotal,
    required this.comptesAjoutes,
    required this.demandesRenumerotees,
    required this.piecesRemisesAEnvoyer,
  });

  final int lignesRenumerotees;
  final double debitTotal;
  final double creditTotal;
  final int comptesAjoutes;
  final int demandesRenumerotees;
  final int piecesRemisesAEnvoyer;
}

/// Renumérotation de l'historique vers le plan SYSCOHADA révisé (schéma v48, `47p_` §8).
///
/// ## Garanties
///
/// - **UNE transaction** : tout ou rien ; une interruption ne laisse aucune base à moitié
///   renumérotée.
/// - **Idempotente, rejouable** : le marqueur [marqueurPlan] (`PRAGMA application_id`, dans
///   l'en-tête du fichier SQLite, donc recopié avec la base lors d'une sauvegarde) dit que le
///   plan est déjà migré ; [executer] ne fait alors rien. (Une table dédiée aurait obligé à
///   regénérer `app_database.g.dart`, partagé entre agents.)
/// - **Croisement 601↔602 et 613→622** : toutes les lignes passent d'abord par des numéros
///   **temporaires** (`~M<n>`), puis aux numéros définitifs.
/// - **Jamais de perte** : après l'opération, le nombre de lignes, le débit total, le crédit
///   total et le solde de chaque compte (à la table de correspondance près, recalculée par
///   [nouveauNumero] indépendamment du SQL) sont vérifiés ; sinon l'exception annule tout.
/// - Les identifiants (UUID) des lignes et des pièces ne changent pas : l'identité de
///   synchronisation est stable (les pièces `CL`/`AN` gardent leurs UUID déterministes).
class MigrationPlanSyscohada {
  const MigrationPlanSyscohada(this._db);

  final AppDatabase _db;

  /// Étiquette de l'en-tête SQLite : `'AVL'` suivi de la version du plan.
  static const int baseMarqueur = 0x41564C00;
  static const int marqueurPlan = baseMarqueur + PlanSyscohada.version;

  /// Le nouveau numéro d'une ligne de l'ANCIEN plan (fonction pure, source de vérité de la
  /// vérification) : [axe] et [venteRef] distinguent les frais de livraison (707 sans centre,
  /// pièce de vente) des ventes de marchandises (707 au centre « Commerce Annexe »).
  ///
  /// Les **sous-comptes** suivent leur compte : `6011` (sous-compte de l'ancien 601) devient
  /// `6021` (sous-compte du nouveau 602). Seul l'exact `707` est départagé par la ligne.
  static String nouveauNumero(
    String ancien, {
    String? axe,
    String? venteRef,
    List<RegleRenumerotation> regles = PlanSyscohada.correspondance,
  }) {
    for (final r in regles) {
      if (r.ancien != ancien) continue;
      if (r.fraisLivraisonSeulement && !(axe == null && venteRef != null)) {
        continue;
      }
      return r.nouveau;
    }
    for (final r in regles) {
      if (r.fraisLivraisonSeulement) continue;
      if (ancien.length > r.ancien.length && ancien.startsWith(r.ancien)) {
        return r.nouveau + ancien.substring(r.ancien.length);
      }
    }
    return ancien;
  }

  /// Les renumérotations à faire : un triplet (ancien, nouveau, frais de livraison seulement) par
  /// compte du plan ou des écritures dont le numéro change (la règle des frais de livraison avant
  /// la règle générale du même compte).
  static List<({String ancien, String nouveau, bool livraison})> _triplets(
    Set<String> anciens,
    List<RegleRenumerotation> regles,
  ) {
    final triplets = <({String ancien, String nouveau, bool livraison})>[];
    for (final ancien in (anciens.toList()..sort())) {
      for (final r in regles) {
        if (r.fraisLivraisonSeulement && r.ancien == ancien) {
          triplets.add((ancien: ancien, nouveau: r.nouveau, livraison: true));
        }
      }
      final general = nouveauNumero(ancien, regles: regles);
      if (general != ancien) {
        triplets.add((ancien: ancien, nouveau: general, livraison: false));
      }
    }
    return triplets;
  }

  Future<int> _marqueur() async {
    final l = await _db.customSelect('PRAGMA application_id').getSingle();
    return l.read<int>('application_id');
  }

  /// Le plan de cette base est-il déjà celui de SYSCOHADA ?
  Future<bool> dejaMigre() async => await _marqueur() == marqueurPlan;

  /// Pose le marqueur sans toucher aux données : base NEUVE (aucun ancien numéro à convertir).
  Future<void> marquerMigre() =>
      _db.customStatement('PRAGMA application_id = $marqueurPlan');

  /// Exécute la migration. `null` si elle a déjà été faite.
  ///
  /// [regles] permet aux tests de MUTATION de casser une règle et de constater que la
  /// vérification rougit.
  Future<RapportMigrationPlan?> executer({
    List<RegleRenumerotation> regles = PlanSyscohada.correspondance,
  }) async {
    if (await dejaMigre()) return null;
    return _db.transaction(() => _renumeroter(regles));
  }

  Future<Map<String, ({double debit, double credit})>> _soldes() async {
    final lignes = await _db
        .customSelect(
          'SELECT numero_compte AS c, SUM(debit) AS d, SUM(credit) AS k '
          'FROM ecriture_comptable GROUP BY numero_compte',
        )
        .get();
    return {
      for (final l in lignes)
        l.read<String>('c'): (
          debit: l.read<double?>('d') ?? 0.0,
          credit: l.read<double?>('k') ?? 0.0,
        ),
    };
  }

  Future<RapportMigrationPlan> _renumeroter(
    List<RegleRenumerotation> regles,
  ) async {
    // ---- État AVANT : attendu, calculé par la fonction pure, ligne par ligne.
    final avant = await _db
        .customSelect(
          'SELECT numero_compte AS c, debit AS d, credit AS k, axe_analytique AS a, '
          'vente_ref AS v FROM ecriture_comptable',
        )
        .get();
    final attendu = <String, ({double debit, double credit})>{};
    var debitAvant = 0.0;
    var creditAvant = 0.0;
    var renumerotees = 0;
    for (final l in avant) {
      final ancien = l.read<String>('c');
      final d = l.read<double>('d');
      final k = l.read<double>('k');
      final nouveau = nouveauNumero(
        ancien,
        axe: l.read<String?>('a'),
        venteRef: l.read<String?>('v'),
        regles: regles,
      );
      if (nouveau != ancien) renumerotees++;
      final cumul = attendu[nouveau];
      attendu[nouveau] = (
        debit: (cumul?.debit ?? 0) + d,
        credit: (cumul?.credit ?? 0) + k,
      );
      debitAvant += d;
      creditAvant += k;
    }

    // ---- Plan existant (pour reporter libellés personnalisés et archivage).
    final planAvant = <String, ({String libelle, String classe, bool archive})>{
      for (final c
          in await _db.customSelect('SELECT * FROM plan_comptable').get())
        c.read<String>('numero_compte'): (
          libelle: c.read<String>('libelle'),
          classe: c.read<String>('classe'),
          archive: c.read<bool>('archive'),
        ),
    };
    final officiel = {for (final c in PlanSyscohada.comptes) c.numero: c};

    // ---- Les comptes à renuméroter : ceux du plan ET ceux des écritures.
    final anciens = <String>{
      ...planAvant.keys,
      for (final l in avant) l.read<String>('c'),
    };
    final triplets = _triplets(anciens, regles);
    final sources = {for (final t in triplets) t.ancien};
    final cibles = {for (final t in triplets) t.nouveau};

    // ---- Phase A : lignes vers des numéros temporaires.
    for (var i = 0; i < triplets.length; i++) {
      final t = triplets[i];
      await _db.customStatement(
        'INSERT OR IGNORE INTO plan_comptable (numero_compte, libelle, classe, archive) '
        "VALUES (?, 'temporaire', ?, 0)",
        ['~M$i', t.nouveau.substring(0, 1)],
      );
      await _db.customStatement(
        'UPDATE ecriture_comptable SET numero_compte = ? WHERE numero_compte = ?'
        '${t.livraison ? ' AND axe_analytique IS NULL AND vente_ref IS NOT NULL' : ''}',
        ['~M$i', t.ancien],
      );
    }

    // ---- Phase B : numéros définitifs. Le plan reçoit la cible : libellé PERSONNALISÉ de l'ancien
    // compte reporté (y compris sur un sous-compte), sinon libellé officiel.
    var ajoutes = 0;
    final traitees = <String>{};
    for (var i = 0; i < triplets.length; i++) {
      final t = triplets[i];
      final existe = await _db
          .customSelect(
            'SELECT 1 AS x FROM plan_comptable WHERE numero_compte = ?',
            variables: [Variable<String>(t.nouveau)],
          )
          .get();
      final rang = planAvant[t.ancien];
      final defaut = PlanSyscohada.libellesAnciens[t.ancien];
      final personnalise =
          !t.livraison &&
          rang != null &&
          (defaut == null || rang.libelle != defaut);
      final libelle = personnalise
          ? rang.libelle
          : (officiel[t.nouveau]?.libelle ?? rang?.libelle ?? t.nouveau);
      final archive = !t.livraison && (rang?.archive ?? false);
      if (existe.isEmpty) {
        await _db.customStatement(
          'INSERT INTO plan_comptable (numero_compte, libelle, classe, archive) VALUES (?, ?, ?, ?)',
          [t.nouveau, libelle, t.nouveau.substring(0, 1), archive ? 1 : 0],
        );
        ajoutes++;
      } else if (!traitees.contains(t.nouveau) &&
          sources.contains(t.nouveau) &&
          !t.livraison) {
        // La cible était un ancien compte (601↔602, 613→622) : elle change de sens, donc de
        // libellé (celui de l'ancien compte source, personnalisé ou officiel).
        await _db.customStatement(
          'UPDATE plan_comptable SET libelle = ?, archive = ? WHERE numero_compte = ?',
          [libelle, archive ? 1 : 0, t.nouveau],
        );
      }
      traitees.add(t.nouveau);
      await _db.customStatement(
        'UPDATE ecriture_comptable SET numero_compte = ? WHERE numero_compte = ?',
        [t.nouveau, '~M$i'],
      );
      await _db.customStatement(
        'DELETE FROM plan_comptable WHERE numero_compte = ?',
        ['~M$i'],
      );
    }

    // ---- Anciens comptes devenus sans objet (531, 512, 613, 616, 624, 628…) : retirés du plan
    // s'ils ne sont la cible d'aucune règle ; le plan ne garde jamais un compte à l'ancien sens.
    for (final ancien in sources) {
      if (cibles.contains(ancien)) continue;
      final reste = await _db
          .customSelect(
            'SELECT COUNT(*) AS n FROM ecriture_comptable WHERE numero_compte = ?',
            variables: [Variable<String>(ancien)],
          )
          .getSingle();
      if (reste.read<int>('n') == 0) {
        await _db.customStatement(
          'DELETE FROM plan_comptable WHERE numero_compte = ?',
          [ancien],
        );
      }
    }

    // ---- Libellés par défaut de l'ancien plan → libellés officiels (31, 32, 401, 411…).
    for (final c in PlanSyscohada.comptes) {
      final ligne = await _db
          .customSelect(
            'SELECT libelle FROM plan_comptable WHERE numero_compte = ?',
            variables: [Variable<String>(c.numero)],
          )
          .getSingleOrNull();
      if (ligne == null) {
        await _db.customStatement(
          'INSERT INTO plan_comptable (numero_compte, libelle, classe, archive) VALUES (?, ?, ?, 0)',
          [c.numero, c.libelle, c.classe],
        );
        ajoutes++;
      } else if (ligne.read<String>('libelle') ==
              PlanSyscohada.libellesAnciens[c.numero] &&
          !sources.contains(c.numero) &&
          !cibles.contains(c.numero)) {
        await _db.customStatement(
          'UPDATE plan_comptable SET libelle = ? WHERE numero_compte = ?',
          [c.libelle, c.numero],
        );
      }
    }

    // ---- Demandes de plan en attente (clé = numéro de compte) : renumérotées, version portée.
    var demandes = 0;
    final enAttente = await _db
        .customSelect(
          "SELECT id, cle, donnees FROM demandes_referentiel WHERE type = 'compte_comptable'",
        )
        .get();
    for (final d in enAttente) {
      final cle = d.read<String>('cle');
      final nouveau = nouveauNumero(cle, regles: regles);
      final donnees =
          jsonDecode(d.read<String>('donnees')) as Map<String, dynamic>;
      donnees['numero_compte'] = nouveau;
      donnees['classe'] = nouveau.substring(0, 1);
      donnees['plan_version'] = PlanSyscohada.version;
      await _db.customStatement(
        'UPDATE demandes_referentiel SET cle = ?, donnees = ? WHERE id = ?',
        [nouveau, jsonEncode(donnees), d.read<String>('id')],
      );
      if (nouveau != cle) demandes++;
    }

    // ---- Pièces refusées par un serveur déjà migré (« ancien plan comptable ») : elles sont
    // maintenant dans le bon plan, elles repartent.
    final remises = await _db
        .customSelect(
          "SELECT COUNT(DISTINCT piece_id) AS n FROM ecriture_comptable "
          "WHERE sync_status = 'conflict' AND sync_motif LIKE '%ancien plan comptable%'",
        )
        .getSingle();
    await _db.customStatement(
      "UPDATE ecriture_comptable SET sync_status = 'pending', sync_motif = NULL "
      "WHERE sync_status = 'conflict' AND sync_motif LIKE '%ancien plan comptable%'",
    );

    // ---- Vérification APRÈS : rien perdu, équilibre et soldes identiques à la
    // renumérotation près.
    final apres = await _soldes();
    final nbApres =
        (await _db
                .customSelect('SELECT COUNT(*) AS n FROM ecriture_comptable')
                .getSingle())
            .read<int>('n');
    var debitApres = 0.0;
    var creditApres = 0.0;
    for (final s in apres.values) {
      debitApres += s.debit;
      creditApres += s.credit;
    }
    void exiger(bool ok, String message) {
      if (!ok) {
        throw StateError('Migration du plan comptable annulée : $message');
      }
    }

    exiger(nbApres == avant.length, 'nombre de lignes modifié.');
    exiger(
      (debitApres - debitAvant).abs() < 0.005 &&
          (creditApres - creditAvant).abs() < 0.005,
      'totaux débit/crédit modifiés.',
    );
    for (final entree in attendu.entries) {
      final reel = apres[entree.key];
      exiger(
        reel != null &&
            (reel.debit - entree.value.debit).abs() < 0.005 &&
            (reel.credit - entree.value.credit).abs() < 0.005,
        'solde du compte ${entree.key} différent de l\'attendu.',
      );
    }
    exiger(apres.length == attendu.length, 'comptes mouvementés différents.');
    final orphelines = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM ecriture_comptable e '
          'LEFT JOIN plan_comptable p ON p.numero_compte = e.numero_compte '
          'WHERE p.numero_compte IS NULL',
        )
        .getSingle();
    exiger(orphelines.read<int>('n') == 0, 'écriture sans compte au plan.');

    await marquerMigre();
    return RapportMigrationPlan(
      lignesRenumerotees: renumerotees,
      debitTotal: debitApres,
      creditTotal: creditApres,
      comptesAjoutes: ajoutes,
      demandesRenumerotees: demandes,
      piecesRemisesAEnvoyer: remises.read<int>('n'),
    );
  }
}
