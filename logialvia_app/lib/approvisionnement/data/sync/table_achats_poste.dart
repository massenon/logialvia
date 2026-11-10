import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/effets_stock_poste.dart';
import '../../../core/sync/table_poste.dart';
import '../../../commercial/domain/entities/vente.dart';
import '../../domain/entities/approvisionnement.dart';

/// `achats` + `lignes_achat` — **faits** saisis au poste, jamais fusionnés
/// (`46_` §2.3). Mêmes règles que les ventes :
///
/// - un achat et ses lignes ne se séparent jamais (un seul corps, une seule
///   transaction) ;
/// - absorber l'achat d'un autre poste ne produit **aucun effet** : ni entrée de
///   stock, ni recalcul du PMP, ni mouvement journalisé, ni écriture comptable (la
///   réception appartient au poste qui a reçu la marchandise) ;
/// - les lignes sont **immuables** dès que l'achat n'est plus « Commandé » ; tant qu'il
///   l'est, une saisie plus récente (la commande modifiée au web) **remplace** ses
///   lignes ; l'entête (statut, montant payé) suit « dernier écrivain gagne » ; la
///   référence ne change jamais.
///
/// ## Exception à la règle d'or : le poste désigné par le web (`47s_`)
///
/// Un achat saisi au web peut porter `poste_cible` (UUID d'un poste, **immuable** une fois
/// posé ; posé une seule fois, tant que la commande est « Commandé »). Le poste désigné — et
/// lui seul — applique alors, **une fois**, l'effet de stock et de PMP : entrée à la
/// réception (statut « Livré »), sortie inverse à l'annulation d'une commande livrée
/// ([EffetsStockPoste], journal `effets_appliques`). Les autres postes l'absorbent comme
/// aujourd'hui : connu, sans effet. Une commande déjà livrée ou annulée localement n'est
/// jamais réappliquée (« non appliqué », tracé).
class TableAchatsPoste implements TablePoste {
  const TableAchatsPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// `ACH-2026-001` (poste jamais appairé), `ACH-P2-2026-001` (poste appairé) ou
  /// `ACH-WEB-2026-001` (commande saisie au web, qui est un « poste » de code WEB).
  static final RegExp _reference = RegExp(r'^ACH-((P\d+|WEB)-)?\d{4}-\d{3,}$');

  @override
  String get nom => 'achats';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.achats)).map((_) {});

  static const _statuts = {
    StatutAchat.commande,
    StatutAchat.livre,
    StatutAchat.annule,
  };

  /// `Crédit` : le choix de la liste déroulante de la commande. Il manquait ici : un achat
  /// à crédit était refusé en bloc par le serveur (« mode inconnu »).
  static const _modes = {
    ModeReglement.especes,
    ModeReglement.mobileMoney,
    ModeAchat.credit,
    ModeReglement.nonPrecise,
  };

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  bool _valide(Map<String, dynamic> l) {
    final lignes = l['lignes'];
    if (l['id'] is! String ||
        !_uuid.hasMatch(l['id'] as String) ||
        l['reference'] is! String ||
        !_reference.hasMatch(l['reference'] as String) ||
        l['fournisseur_id'] is! String ||
        !_uuid.hasMatch(l['fournisseur_id'] as String) ||
        l['date_achat'] is! String ||
        DateTime.tryParse(l['date_achat'] as String) == null ||
        l['updated_at'] is! String ||
        DateTime.tryParse(l['updated_at'] as String) == null ||
        (l['poste_cible'] != null &&
            (l['poste_cible'] is! String ||
                !_uuid.hasMatch(l['poste_cible'] as String))) ||
        !_statuts.contains(l['statut']) ||
        (l['mode'] != null && !_modes.contains(l['mode'])) ||
        l['total'] is! num ||
        (l['total'] as num) < 0 ||
        l['paye'] is! num ||
        (l['paye'] as num) < 0 ||
        (l['paye'] as num) > (l['total'] as num) + 0.005 ||
        lignes is! List ||
        lignes.isEmpty) {
      return false;
    }
    for (final x in lignes) {
      if (x is! Map ||
          x['id'] is! String ||
          !_uuid.hasMatch(x['id'] as String) ||
          _texte(x['intrant_code']) == null ||
          _texte(x['nom']) == null ||
          x['qte'] is! num ||
          (x['qte'] as num) <= 0 ||
          x['pu_achat'] is! num ||
          (x['pu_achat'] as num) < 0) {
        return false;
      }
    }
    return true;
  }

  DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        if (!_valide(l)) {
          refusees++;
          continue;
        }
        final id = l['id'] as String;
        final reference = l['reference'] as String;
        final instant = DateTime.parse(l['updated_at'] as String);
        final lignesAchat = (l['lignes'] as List).cast<Map<String, dynamic>>();

        final locale = await (_db.select(
          _db.achats,
        )..where((a) => a.id.equals(id))).getSingleOrNull();

        if (locale == null) {
          // Le fournisseur arrive AVANT l'achat ; chaque intrant doit exister ici
          // (la clé étrangère de la ligne le exige).
          final fournisseur =
              await (_db.select(_db.fournisseurs)
                    ..where((f) => f.id.equals(l['fournisseur_id'] as String)))
                  .getSingleOrNull();
          var intrantsConnus = true;
          for (final x in lignesAchat) {
            final i =
                await (_db.select(
                      _db.intrants,
                    )..where((i) => i.code.equals(x['intrant_code'] as String)))
                    .getSingleOrNull();
            if (i == null) intrantsConnus = false;
          }
          // `ref` est la clé primaire locale : une ancienne référence sans code déjà
          // prise par une AUTRE vente de ce poste ne peut pas coexister ici.
          final prise = await (_db.select(
            _db.achats,
          )..where((a) => a.ref.equals(reference))).getSingleOrNull();
          if (fournisseur == null || !intrantsConnus || prise != null) {
            refusees++;
            continue;
          }

          await _db
              .into(_db.achats)
              .insert(
                AchatsCompanion.insert(
                  id: Value(id),
                  ref: reference,
                  fournisseurId: l['fournisseur_id'] as String,
                  dateAchat: DateTime.parse(
                    l['date_achat'] as String,
                  ).toLocal(),
                  statut: l['statut'] as String,
                  total: (l['total'] as num).toDouble(),
                  paye: Value((l['paye'] as num).toDouble()),
                  mode: Value(_texte(l['mode'])),
                  echeance: Value(_date(l['echeance'])),
                  posteCible: Value(_texte(l['poste_cible'])),
                  syncStatus: const Value('synced'),
                  updatedAt: Value(instant.toUtc().toIso8601String()),
                ),
              );
          for (final x in lignesAchat) {
            await _db
                .into(_db.lignesAchat)
                .insert(
                  LignesAchatCompanion.insert(
                    id: Value(x['id'] as String),
                    achatRef: reference,
                    intrantCode: x['intrant_code'] as String,
                    nom: (x['nom'] as String).trim(),
                    qte: (x['qte'] as num).toDouble(),
                    puAchat: (x['pu_achat'] as num).toDouble(),
                  ),
                );
          }
          await _effetsDeStock(
            achatId: id,
            reference: reference,
            posteRecu: _texte(l['poste_cible']),
            posteLie: _texte(l['poste_cible']),
            statutAvant: null,
            statutRecu: l['statut'] as String,
          );
          absorbees++;
          continue;
        }

        // Achat déjà connu : règle du plus récent, comme le serveur. Même une ligne locale
        // déjà synchronisée ne cède pas à une version STRICTEMENT plus ancienne (tirage
        // rejoué dans le désordre) : sinon une commande modifiée reviendrait en arrière.
        if (locale.syncStatus == 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && instant.isBefore(saisieLocale)) {
            conservees++;
            continue;
          }
        }
        if (locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++;
            continue;
          }
          supplantees++;
        }
        // Les lignes ne se remplacent que tant que l'achat LOCAL est « Commandé » (rien
        // n'est entré en stock) ; chaque intrant de la nouvelle composition doit exister.
        final remplacerLignes = locale.statut == StatutAchat.commande;
        if (remplacerLignes) {
          var connus = true;
          for (final x in lignesAchat) {
            final i =
                await (_db.select(
                      _db.intrants,
                    )..where((i) => i.code.equals(x['intrant_code'] as String)))
                    .getSingleOrNull();
            if (i == null) connus = false;
          }
          if (!connus) {
            refusees++;
            continue;
          }
        }
        // Le poste de stock est lié au fait : posé une seule fois, tant que rien n'est
        // livré ; ensuite le web ne peut plus le changer (6).
        final posteRecu = _texte(l['poste_cible']);
        final posteLie =
            locale.posteCible ??
            (locale.statut == StatutAchat.commande ? posteRecu : null);
        final identique =
            !remplacerLignes &&
            posteLie == locale.posteCible &&
            locale.statut == l['statut'] &&
            locale.paye == (l['paye'] as num).toDouble() &&
            locale.total == (l['total'] as num).toDouble() &&
            locale.syncStatus == 'synced';
        if (identique) continue;

        await (_db.update(_db.achats)..where((a) => a.id.equals(id))).write(
          AchatsCompanion(
            statut: Value(l['statut'] as String),
            total: Value((l['total'] as num).toDouble()),
            paye: Value((l['paye'] as num).toDouble()),
            mode: Value(_texte(l['mode'])),
            echeance: Value(_date(l['echeance'])),
            posteCible: Value(posteLie),
            syncStatus: const Value('synced'),
            syncMotif: const Value(null),
            updatedAt: Value(instant.toUtc().toIso8601String()),
          ),
        );
        if (remplacerLignes) {
          await (_db.delete(
            _db.lignesAchat,
          )..where((x) => x.achatRef.equals(locale.ref))).go();
          for (final x in lignesAchat) {
            await _db
                .into(_db.lignesAchat)
                .insert(
                  LignesAchatCompanion.insert(
                    id: Value(x['id'] as String),
                    achatRef: locale.ref,
                    intrantCode: x['intrant_code'] as String,
                    nom: (x['nom'] as String).trim(),
                    qte: (x['qte'] as num).toDouble(),
                    puAchat: (x['pu_achat'] as num).toDouble(),
                  ),
                );
          }
        }
        await _effetsDeStock(
          achatId: id,
          reference: locale.ref,
          posteRecu: posteRecu,
          posteLie: posteLie,
          statutAvant: locale.statut,
          statutRecu: l['statut'] as String,
        );
        absorbees++;
      }
      return ResultatAbsorption(
        absorbees: absorbees,
        refusees: refusees,
        conservees: conservees,
        supplantees: supplantees,
      );
    });
  }

  /// L'effet de stock d'un achat reçu du web, **si ce poste est le poste désigné** (`47s_`).
  ///
  /// - « Livré » : entrée + PMP, une fois. Si la commande n'était plus « Commandé » ici
  ///   (réceptionnée au poste), ou si la désignation est arrivée trop tard, l'effet n'est
  ///   PAS appliqué (sinon double entrée) et la trace le dit ;
  /// - « Annulé » : sortie inverse, seulement si la réception avait été appliquée ici.
  Future<void> _effetsDeStock({
    required String achatId,
    required String reference,
    required String? posteRecu,
    required String? posteLie,
    required String? statutAvant,
    required String statutRecu,
  }) async {
    final effets = EffetsStockPoste(_db);
    // Le LIEN d'origine décide ; le poste reçu ne sert qu'à signaler une désignation
    // tardive ou contradictoire adressée à CE poste.
    final lieAMoi = await effets.estCible(posteLie);
    final designeMoi = await effets.estCible(posteRecu);
    if (!lieAMoi && !designeMoi) return;
    final lignes = [
      for (final x in await (_db.select(
        _db.lignesAchat,
      )..where((x) => x.achatRef.equals(reference))).get())
        LigneEffetIntrant(
          code: x.intrantCode,
          nom: x.nom,
          quantite: x.qte,
          prixUnitaire: x.puAchat,
        ),
    ];
    if (statutRecu == StatutAchat.livre) {
      if (await effets.dejaApplique(achatId, EffetsStockPoste.reception)) {
        return;
      }
      if (lieAMoi &&
          (statutAvant == null || statutAvant == StatutAchat.commande)) {
        await effets.appliquerReception(
          achatId: achatId,
          reference: reference,
          lignes: lignes,
        );
      } else {
        await effets.ignorer(
          faitType: EffetsStockPoste.faitAchat,
          faitId: achatId,
          nature: EffetsStockPoste.reception,
          reference: reference,
          motif: lieAMoi
              ? 'la commande $reference n\'était plus « Commandé » sur ce poste : '
                    'stock inchangé'
              : 'la commande $reference est liée à un autre poste ou était déjà '
                    'livrée ici quand le web l\'a désignée : stock inchangé',
        );
      }
    } else if (statutRecu == StatutAchat.annule && lieAMoi) {
      await effets.annulerReception(
        achatId: achatId,
        reference: reference,
        lignes: lignes,
      );
    }
  }

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final achats =
        await (_db.select(_db.achats)
              ..where((a) => a.syncStatus.equals('pending'))
              ..orderBy([(a) => OrderingTerm.asc(a.updatedAt)]))
            .get();
    final envoi = <LigneAEnvoyer>[];
    for (final a in achats) {
      final lignes = await (_db.select(
        _db.lignesAchat,
      )..where((x) => x.achatRef.equals(a.ref))).get();
      envoi.add(
        LigneAEnvoyer(
          id: a.id,
          instantSaisie: a.updatedAt,
          corps: {
            'id': a.id,
            'reference': a.ref,
            'fournisseur_id': a.fournisseurId,
            'date_achat': a.dateAchat.toUtc().toIso8601String(),
            'statut': a.statut,
            'total': a.total,
            'paye': a.paye,
            'mode': a.mode,
            'echeance': a.echeance?.toUtc().toIso8601String(),
            'poste_cible': a.posteCible,
            'updated_at': a.updatedAt,
            'lignes': [
              for (final x in lignes)
                {
                  'id': x.id,
                  'intrant_code': x.intrantCode,
                  'nom': x.nom,
                  'qte': x.qte,
                  'pu_achat': x.puAchat,
                },
            ],
          },
        ),
      );
    }
    return envoi;
  }

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {
    await (_db.update(
      _db.achats,
    )..where((a) => a.id.equals(id) & a.updatedAt.equals(instantEnvoye))).write(
      const AchatsCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.achats)..where((a) => a.id.equals(id))).write(
      AchatsCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : les achats (et leurs lignes) partent avec lui.
  /// ⚠️ Stock, PMP, mouvements et écritures du poste restent (autres paliers).
  @override
  Future<int> purger() async {
    final nonEnvoyes = await (_db.select(
      _db.achats,
    )..where((a) => a.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.lignesAchat).go();
    await _db.delete(_db.achats).go();
    return nonEnvoyes.length;
  }
}
