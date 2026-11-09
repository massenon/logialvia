import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../../domain/entities/vente.dart';

/// `ventes` + `lignes_vente` — **faits** saisis au poste, jamais fusionnés (`46_` §2.3).
///
/// ## Une vente et ses lignes ne se séparent jamais
///
/// Elles partent dans un même corps (`lignes: [...]`) et arrivent de même : une
/// vente sans ses lignes fausserait le chiffre d'affaires, des lignes sans vente
/// n'ont aucun sens. Absorbées dans UNE transaction (celle de la page).
///
/// ## Ce qu'absorber une vente d'un autre poste ne fait PAS
///
/// Pas de décrément de stock, pas d'écriture comptable, pas de compteur de fiche
/// d'élevage, pas d'événement : ces effets appartiennent au poste qui a vendu (le
/// stock est une donnée dérivée propre à chaque poste, `46_` §2.2 ; la comptabilité
/// est une demande, §2.5). La vente est simplement **connue** ici.
///
/// Les lignes sont **immuables** après création : seul l'entête (statut, montant
/// payé, annulation…) suit « dernier écrivain gagne ».
class TableVentesPoste implements TablePoste {
  const TableVentesPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// `V-P2-2026-001` (poste appairé), `V-WEB-2026-001` (vente saisie au web, code
  /// `WEB` comme pour ses pièces comptables) ou `V-2026-001` (avant l'appairage).
  static final RegExp _reference = RegExp(r'^V-((P\d+|WEB)-)?\d{4}-\d{3,}$');

  @override
  String get nom => 'ventes';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.ventes)).map((_) {});

  static const _modes = {
    ModeReglement.especes,
    ModeReglement.mobileMoney,
    ModeReglement.nonPrecise,
  };
  static const _statuts = {
    StatutVente.payee,
    StatutVente.avance,
    StatutVente.annulee,
  };

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  /// Valide une vente reçue ; `null` si elle est cohérente.
  bool _valide(Map<String, dynamic> l) {
    final lignes = l['lignes'];
    if (l['id'] is! String ||
        !_uuid.hasMatch(l['id'] as String) ||
        l['reference'] is! String ||
        !_reference.hasMatch(l['reference'] as String) ||
        _texte(l['client']) == null ||
        l['date_vente'] is! String ||
        DateTime.tryParse(l['date_vente'] as String) == null ||
        l['updated_at'] is! String ||
        DateTime.tryParse(l['updated_at'] as String) == null ||
        !_modes.contains(l['mode']) ||
        !_statuts.contains(l['status']) ||
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
          x['produit_id'] is! String ||
          !_uuid.hasMatch(x['produit_id'] as String) ||
          _texte(x['name']) == null ||
          x['qte'] is! num ||
          (x['qte'] as num) <= 0 ||
          x['pu'] is! num ||
          (x['pu'] as num) < 0) {
        return false;
      }
    }
    return true;
  }

  DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  bool _memeInstant(DateTime? a, DateTime? b) =>
      a == null || b == null ? a == b : a.isAtSameMomentAs(b);

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
        final lignesVente = (l['lignes'] as List).cast<Map<String, dynamic>>();

        final locale = await (_db.select(
          _db.ventes,
        )..where((v) => v.id.equals(id))).getSingleOrNull();

        if (locale == null) {
          // Les produits arrivent AVANT les ventes (référentiels d'abord) : un
          // produit toujours inconnu rend la vente inexploitable ici.
          var produitsConnus = true;
          for (final x in lignesVente) {
            final p =
                await (_db.select(_db.produitsVendables)
                      ..where((p) => p.id.equals(x['produit_id'] as String)))
                    .getSingleOrNull();
            if (p == null) produitsConnus = false;
          }
          // `ref` est la clé primaire locale : une ancienne référence sans code déjà
          // prise par une AUTRE vente de ce poste ne peut pas coexister ici.
          final prise = await (_db.select(
            _db.ventes,
          )..where((v) => v.ref.equals(reference))).getSingleOrNull();
          if (!produitsConnus || prise != null) {
            refusees++;
            continue;
          }

          await _db
              .into(_db.ventes)
              .insert(
                VentesCompanion.insert(
                  id: Value(id),
                  ref: reference,
                  client: (l['client'] as String).trim(),
                  clientId: Value(_texte(l['client_id'])),
                  dateVente: DateTime.parse(
                    l['date_vente'] as String,
                  ).toLocal(),
                  mode: l['mode'] as String,
                  status: l['status'] as String,
                  total: (l['total'] as num).toDouble(),
                  paye: (l['paye'] as num).toDouble(),
                  motifAnnulation: Value(_texte(l['motif_annulation'])),
                  livraisonMode: Value(_texte(l['livraison_mode'])),
                  livraisonFrais: Value(
                    (l['livraison_frais'] as num?)?.toDouble(),
                  ),
                  livraisonAdresse: Value(_texte(l['livraison_adresse'])),
                  livraisonContact: Value(_texte(l['livraison_contact'])),
                  echeance: Value(_date(l['echeance'])),
                  ligneMobileMoney: Value(_texte(l['ligne_mobile_money'])),
                  syncStatus: const Value('synced'),
                  updatedAt: Value(instant.toUtc().toIso8601String()),
                ),
              );
          for (final x in lignesVente) {
            await _db
                .into(_db.lignesVente)
                .insert(
                  LignesVenteCompanion.insert(
                    id: Value(x['id'] as String),
                    venteRef: reference,
                    produitId: x['produit_id'] as String,
                    name: (x['name'] as String).trim(),
                    qte: (x['qte'] as num).toDouble(),
                    pu: (x['pu'] as num).toDouble(),
                    espece: Value(_texte(x['espece'])),
                  ),
                );
          }
          absorbees++;
          continue;
        }

        // Vente déjà connue : règle du plus récent, comme le serveur.
        if (locale.syncStatus != 'synced') {
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null && !instant.isAfter(saisieLocale)) {
            conservees++; // la saisie locale est plus récente : elle partira
            continue;
          }
          supplantees++; // le serveur a une version strictement plus récente
        }

        final identique =
            locale.status == l['status'] &&
            locale.paye == (l['paye'] as num).toDouble() &&
            locale.total == (l['total'] as num).toDouble() &&
            locale.motifAnnulation == _texte(l['motif_annulation']) &&
            locale.clientId == _texte(l['client_id']) &&
            locale.client == (l['client'] as String).trim() &&
            locale.livraisonAdresse == _texte(l['livraison_adresse']) &&
            locale.livraisonContact == _texte(l['livraison_contact']) &&
            _memeInstant(locale.echeance, _date(l['echeance'])) &&
            locale.syncStatus == 'synced';
        if (identique) continue;

        await (_db.update(_db.ventes)..where((v) => v.id.equals(id))).write(
          VentesCompanion(
            client: Value((l['client'] as String).trim()),
            clientId: Value(_texte(l['client_id'])),
            mode: Value(l['mode'] as String),
            status: Value(l['status'] as String),
            total: Value((l['total'] as num).toDouble()),
            paye: Value((l['paye'] as num).toDouble()),
            motifAnnulation: Value(_texte(l['motif_annulation'])),
            echeance: Value(_date(l['echeance'])),
            // Corrigés au web (adresse ou contact de livraison) : sans eux, la
            // modification arrivait « identique » et se perdait en silence.
            livraisonAdresse: Value(_texte(l['livraison_adresse'])),
            livraisonContact: Value(_texte(l['livraison_contact'])),
            syncStatus: const Value('synced'),
            syncMotif: const Value(null),
            updatedAt: Value(instant.toUtc().toIso8601String()),
          ),
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

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    final ventes =
        await (_db.select(_db.ventes)
              ..where((v) => v.syncStatus.equals('pending'))
              ..orderBy([(v) => OrderingTerm.asc(v.updatedAt)]))
            .get();
    final envoi = <LigneAEnvoyer>[];
    for (final v in ventes) {
      final lignes = await (_db.select(
        _db.lignesVente,
      )..where((x) => x.venteRef.equals(v.ref))).get();
      envoi.add(
        LigneAEnvoyer(
          id: v.id,
          instantSaisie: v.updatedAt,
          corps: {
            'id': v.id,
            'reference': v.ref,
            'client': v.client,
            'client_id': v.clientId,
            'date_vente': v.dateVente.toUtc().toIso8601String(),
            'mode': v.mode,
            'status': v.status,
            'total': v.total,
            'paye': v.paye,
            'motif_annulation': v.motifAnnulation,
            'livraison_mode': v.livraisonMode,
            'livraison_frais': v.livraisonFrais,
            'livraison_adresse': v.livraisonAdresse,
            'livraison_contact': v.livraisonContact,
            'echeance': v.echeance?.toUtc().toIso8601String(),
            'ligne_mobile_money': v.ligneMobileMoney,
            'updated_at': v.updatedAt,
            'lignes': [
              for (final x in lignes)
                {
                  'id': x.id,
                  'produit_id': x.produitId,
                  'name': x.name,
                  'qte': x.qte,
                  'pu': x.pu,
                  'espece': x.espece,
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
      _db.ventes,
    )..where((v) => v.id.equals(id) & v.updatedAt.equals(instantEnvoye))).write(
      const VentesCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.ventes)..where((v) => v.id.equals(id))).write(
      VentesCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur : les ventes (et leurs lignes) partent avec lui.
  ///
  /// ⚠️ La comptabilité et le stock du poste ne sont PAS synchronisés (autres
  /// paliers) : leurs écritures et compteurs restent. C'est la limite connue d'une
  /// synchronisation partielle (`45_` §6h).
  @override
  Future<int> purger() async {
    final nonEnvoyees = await (_db.select(
      _db.ventes,
    )..where((v) => v.syncStatus.isNotValue('synced'))).get();
    await _db.delete(_db.lignesVente).go();
    await _db.delete(_db.ventes).go();
    return nonEnvoyees.length;
  }
}
