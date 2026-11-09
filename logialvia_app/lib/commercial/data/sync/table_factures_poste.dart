import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import '../../domain/entities/facture_mecef.dart';

/// `factures` + `lignes_facture` — **faits** saisis au poste, jamais fusionnés
/// (`46_` §2.5, `46e_`).
///
/// ## Une facture et ses lignes ne se séparent jamais
///
/// Elles partent dans un même corps (`lignes: [...]`) et arrivent de même, dans
/// UNE transaction. Les lignes sont **immuables** : une facture émise ne se
/// réécrit pas (corriger, c'est émettre un avoir).
///
/// ## Ce qui voyage, et ce qui ne voyage JAMAIS
///
/// Voyagent : la facture, ses lignes, son statut et ce que la DGI a rendu (code de
/// normalisation, NIM de la machine **imprimé sur la facture**, compteur, lien de
/// vérification, date, message d'erreur). Ne voyagent jamais : le **jeton**
/// e-MECeF (coffre du système) ni l'URL du service. **La transmission à la DGI
/// reste au poste** : le serveur n'appelle jamais e-MECeF.
///
/// ## Qui l'emporte quand deux postes divergent sur le statut
///
/// Le **rang**, pas l'horloge : `à transmettre` < `rejetée` < `normalisée`
/// (`StatutFacture.rang`). Un statut ne régresse jamais ; une facture normalisée est
/// immuable. Deux normalisations **différentes** de la même facture (double
/// transmission à la DGI) ne sont jamais départagées en silence : la saisie locale
/// est conservée et marquée `conflict` avec son motif, pour que la comptable
/// l'instruise (avoir). Voir `46e_` §2.
///
/// ## Ce qu'absorber la facture d'un autre poste ne fait PAS
///
/// Ni écriture comptable, ni lien forcé avec la vente, ni compteur de
/// numérotation, ni événement, ni transmission : la facture est **connue**, pas
/// rejouée. Elle porte `origine` (le poste émetteur) et n'offre ici ni
/// transmission ni saisie du code : un seul poste normalise une facture.
class TableFacturesPoste implements TablePoste {
  const TableFacturesPoste(this._db);

  final AppDatabase _db;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _reference = RegExp(r'^(FV|FA)-(P\d+-)?\d{4}-\d{3,}$');
  static final RegExp _lettre = RegExp(r'^[A-Z]$');

  /// Tolérance d'arrondi entre un total et la somme de ses lignes (en FCFA).
  static const double _tolerance = 0.01;

  @override
  String get nom => 'factures';

  @override
  bool get referentiel => false;

  @override
  Stream<void> get modifications =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.factures)).map((_) {});

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  static const _statuts = {'a_transmettre', 'normalisee', 'rejetee'};

  /// Valide une facture reçue (strict : incohérente = refusée, jamais lissée).
  bool _valide(Map<String, dynamic> l) {
    final lignes = l['lignes'];
    final type = l['type'];
    final statut = l['statut'];
    final reference = l['reference'];
    if (l['id'] is! String ||
        !_uuid.hasMatch(l['id'] as String) ||
        reference is! String ||
        !_reference.hasMatch(reference) ||
        (type != 'FV' && type != 'FA') ||
        !reference.startsWith('$type-') ||
        _texte(l['client']) == null ||
        _date(l['date_facture']) == null ||
        l['updated_at'] is! String ||
        DateTime.tryParse(l['updated_at'] as String) == null ||
        l['total_ht'] is! num ||
        l['total_taxe'] is! num ||
        l['total_ttc'] is! num ||
        (l['total_ht'] as num) < 0 ||
        (l['total_taxe'] as num) < 0 ||
        ((l['total_ht'] as num) +
                    (l['total_taxe'] as num) -
                    (l['total_ttc'] as num))
                .abs() >
            _tolerance ||
        !_statuts.contains(statut) ||
        lignes is! List ||
        lignes.isEmpty) {
      return false;
    }
    // Un avoir désigne la facture qu'il corrige, et dit pourquoi ; une facture de
    // vente ne désigne rien.
    if (type == 'FA' &&
        (_texte(l['origine_ref']) == null || _texte(l['motif']) == null)) {
      return false;
    }
    if (type == 'FV' && l['origine_ref'] != null) return false;
    // Normalisée = code ET NIM réels, jamais l'un sans l'autre ; sinon aucun.
    final code = _texte(l['code_mecef']);
    final nim = _texte(l['nim']);
    if (statut == 'normalisee') {
      if (code == null ||
          nim == null ||
          _date(l['date_normalisation']) == null) {
        return false;
      }
    } else if (code != null || nim != null) {
      return false;
    }

    var ht = 0.0;
    var taxe = 0.0;
    for (final x in lignes) {
      if (x is! Map ||
          x['id'] is! String ||
          !_uuid.hasMatch(x['id'] as String) ||
          _texte(x['designation']) == null ||
          x['quantite'] is! num ||
          (x['quantite'] as num) <= 0 ||
          x['prix_unitaire_ht'] is! num ||
          (x['prix_unitaire_ht'] as num) < 0 ||
          x['groupe_taxe'] is! String ||
          !_lettre.hasMatch(x['groupe_taxe'] as String) ||
          x['taux_taxe'] is! num ||
          (x['taux_taxe'] as num) < 0 ||
          (x['taux_taxe'] as num) > 100 ||
          x['montant_ht'] is! num ||
          x['montant_taxe'] is! num) {
        return false;
      }
      ht += (x['montant_ht'] as num).toDouble();
      taxe += (x['montant_taxe'] as num).toDouble();
    }
    // Les totaux sont ceux des lignes : une facture dont l'entête ment est refusée.
    return (ht - (l['total_ht'] as num)).abs() <= _tolerance * lignes.length &&
        (taxe - (l['total_taxe'] as num)).abs() <= _tolerance * lignes.length;
  }

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
        final statut = StatutFacture.depuis(l['statut'] as String);

        final locale = await (_db.select(
          _db.factures,
        )..where((f) => f.id.equals(id))).getSingleOrNull();

        if (locale == null) {
          // `ref` est la clé primaire locale : une référence déjà prise par une
          // AUTRE facture de ce poste ne peut pas coexister ici (jamais écrasée).
          final prise = await (_db.select(
            _db.factures,
          )..where((f) => f.ref.equals(reference))).getSingleOrNull();
          if (prise != null) {
            refusees++;
            continue;
          }
          await _inserer(l, id, reference, instant);
          absorbees++;
          continue;
        }

        // Facture déjà connue : son contenu est IMMUABLE. Une référence ou un type
        // différents pour le même UUID n'est pas une mise à jour, c'est une anomalie.
        if (locale.ref != reference || locale.type != l['type']) {
          refusees++;
          continue;
        }

        final locaux = StatutFacture.depuis(locale.statut);
        final nonEnvoyee = locale.syncStatus != 'synced';

        if (statut.rang > locaux.rang) {
          // Le serveur est plus avancé (le statut ne régresse jamais) : il l'emporte,
          // même sur une saisie locale non envoyée.
          await _appliquerStatut(l, instant);
          absorbees++;
          if (nonEnvoyee) supplantees++;
          continue;
        }
        if (statut.rang < locaux.rang) {
          // Le poste est plus avancé : sa saisie partira ; rien à reprendre.
          if (nonEnvoyee) conservees++;
          continue;
        }

        // Même rang.
        if (statut == StatutFacture.normalisee) {
          final memeNormalisation =
              locale.codeMecef == _texte(l['code_mecef']) &&
              locale.nim == _texte(l['nim']);
          if (memeNormalisation) {
            if (nonEnvoyee) {
              // Le serveur connaît déjà exactement cette normalisation.
              await (_db.update(
                _db.factures,
              )..where((f) => f.id.equals(id))).write(
                const FacturesCompanion(
                  syncStatus: Value('synced'),
                  syncMotif: Value(null),
                ),
              );
              absorbees++;
            }
            continue;
          }
          // Double normalisation : jamais départagée en silence.
          await (_db.update(_db.factures)..where((f) => f.id.equals(id))).write(
            FacturesCompanion(
              syncStatus: const Value('conflict'),
              syncMotif: Value(
                'Cette facture a été normalisée deux fois, avec deux codes '
                'différents (le serveur : ${_texte(l['code_mecef'])}). '
                'Aucun n\'a été écrasé : signalez-le à la DGI et émettez un '
                'avoir si besoin.',
              ),
            ),
          );
          refusees++;
          continue;
        }
        if (statut == StatutFacture.rejetee) {
          // Deux rejets : le plus récent des deux (dernier écrivain gagne).
          final saisieLocale = DateTime.tryParse(locale.updatedAt);
          if (saisieLocale != null &&
              !instant.isAfter(saisieLocale) &&
              nonEnvoyee) {
            conservees++;
            continue;
          }
          if (locale.erreurTransmission == _texte(l['erreur_transmission']) &&
              !nonEnvoyee) {
            continue;
          }
          await _appliquerStatut(l, instant);
          absorbees++;
          if (nonEnvoyee) supplantees++;
        }
        // `à transmettre` des deux côtés : rien ne change (la saisie locale part
        // à l'envoi si elle n'est pas encore connue du serveur).
      }
      return ResultatAbsorption(
        absorbees: absorbees,
        refusees: refusees,
        conservees: conservees,
        supplantees: supplantees,
      );
    });
  }

  Future<void> _inserer(
    Map<String, dynamic> l,
    String id,
    String reference,
    DateTime instant,
  ) async {
    final lignes = (l['lignes'] as List).cast<Map<String, dynamic>>();
    await _db
        .into(_db.factures)
        .insert(
          FacturesCompanion.insert(
            id: Value(id),
            ref: reference,
            type: l['type'] as String,
            venteRef: Value(_texte(l['vente_ref'])),
            origineRef: Value(_texte(l['origine_ref'])),
            dateFacture: _date(l['date_facture'])!,
            client: (l['client'] as String).trim(),
            clientIfu: Value(_texte(l['client_ifu'])),
            clientAdresse: Value(_texte(l['client_adresse'])),
            totalHt: (l['total_ht'] as num).toDouble(),
            totalTaxe: (l['total_taxe'] as num).toDouble(),
            totalTtc: (l['total_ttc'] as num).toDouble(),
            motif: Value(_texte(l['motif'])),
            statut: l['statut'] as String,
            codeMecef: Value(_texte(l['code_mecef'])),
            nim: Value(_texte(l['nim'])),
            compteur: Value(_texte(l['compteur'])),
            lienVerification: Value(_texte(l['lien_verification'])),
            dateNormalisation: Value(_date(l['date_normalisation'])),
            erreurTransmission: Value(_texte(l['erreur_transmission'])),
            origine: Value(_texte(l['device_id']) ?? 'autre-poste'),
            syncStatus: const Value('synced'),
            updatedAt: Value(instant.toUtc().toIso8601String()),
          ),
        );
    for (final x in lignes) {
      await _db
          .into(_db.lignesFacture)
          .insert(
            LignesFactureCompanion.insert(
              id: Value(x['id'] as String),
              factureRef: reference,
              designation: (x['designation'] as String).trim(),
              quantite: (x['quantite'] as num).toDouble(),
              unite: Value(_texte(x['unite'])),
              prixUnitaireHt: (x['prix_unitaire_ht'] as num).toDouble(),
              groupeTaxe: x['groupe_taxe'] as String,
              tauxTaxe: (x['taux_taxe'] as num).toDouble(),
              montantHt: (x['montant_ht'] as num).toDouble(),
              montantTaxe: (x['montant_taxe'] as num).toDouble(),
            ),
          );
    }
  }

  /// Reprend du serveur le STATUT et ce que la DGI a rendu ; jamais le contenu.
  Future<void> _appliquerStatut(Map<String, dynamic> l, DateTime instant) {
    return (_db.update(
      _db.factures,
    )..where((f) => f.id.equals(l['id'] as String))).write(
      FacturesCompanion(
        statut: Value(l['statut'] as String),
        codeMecef: Value(_texte(l['code_mecef'])),
        nim: Value(_texte(l['nim'])),
        compteur: Value(_texte(l['compteur'])),
        lienVerification: Value(_texte(l['lien_verification'])),
        dateNormalisation: Value(_date(l['date_normalisation'])),
        erreurTransmission: Value(_texte(l['erreur_transmission'])),
        syncStatus: const Value('synced'),
        syncMotif: const Value(null),
        updatedAt: Value(instant.toUtc().toIso8601String()),
      ),
    );
  }

  @override
  Future<List<LigneAEnvoyer>> aEnvoyer() async {
    // Seules les factures émises ICI partent : une facture absorbée d'un autre
    // poste appartient à son émetteur.
    final factures =
        await (_db.select(_db.factures)
              ..where(
                (f) => f.syncStatus.equals('pending') & f.origine.isNull(),
              )
              ..orderBy([(f) => OrderingTerm.asc(f.updatedAt)]))
            .get();
    // Les factures de vente AVANT les avoirs : un avoir désigne sa facture, que le
    // serveur doit connaître (une facture normalisée tard a un `updated_at` plus
    // récent que son avoir).
    factures.sort((a, b) {
      final ta = a.type == TypeFacture.vente.code ? 0 : 1;
      final tb = b.type == TypeFacture.vente.code ? 0 : 1;
      return ta != tb ? ta.compareTo(tb) : a.updatedAt.compareTo(b.updatedAt);
    });

    final envoi = <LigneAEnvoyer>[];
    for (final f in factures) {
      final lignes = await (_db.select(
        _db.lignesFacture,
      )..where((x) => x.factureRef.equals(f.ref))).get();
      envoi.add(
        LigneAEnvoyer(
          id: f.id,
          instantSaisie: f.updatedAt,
          corps: {
            'id': f.id,
            'reference': f.ref,
            'type': f.type,
            'vente_ref': f.venteRef,
            'origine_ref': f.origineRef,
            'date_facture': f.dateFacture.toUtc().toIso8601String(),
            'client': f.client,
            'client_ifu': f.clientIfu,
            'client_adresse': f.clientAdresse,
            'total_ht': f.totalHt,
            'total_taxe': f.totalTaxe,
            'total_ttc': f.totalTtc,
            'motif': f.motif,
            'statut': f.statut,
            // Ce que la DGI a rendu. JAMAIS le jeton ni l'URL du service.
            'code_mecef': f.codeMecef,
            'nim': f.nim,
            'compteur': f.compteur,
            'lien_verification': f.lienVerification,
            'date_normalisation': f.dateNormalisation
                ?.toUtc()
                .toIso8601String(),
            'erreur_transmission': f.erreurTransmission,
            'updated_at': f.updatedAt,
            'lignes': [
              for (final x in lignes)
                {
                  'id': x.id,
                  'designation': x.designation,
                  'quantite': x.quantite,
                  'unite': x.unite,
                  'prix_unitaire_ht': x.prixUnitaireHt,
                  'groupe_taxe': x.groupeTaxe,
                  'taux_taxe': x.tauxTaxe,
                  'montant_ht': x.montantHt,
                  'montant_taxe': x.montantTaxe,
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
      _db.factures,
    )..where((f) => f.id.equals(id) & f.updatedAt.equals(instantEnvoye))).write(
      const FacturesCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  @override
  Future<void> marquerConflit(String id, String motif) async {
    await (_db.update(_db.factures)..where((f) => f.id.equals(id))).write(
      FacturesCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Remise à zéro du serveur.
  ///
  /// ⚠️ **Une facture normalisée n'est jamais détruite sur ordre du serveur** : c'est
  /// une pièce fiscale, que la loi oblige à conserver. Elle reste ici et repart au
  /// prochain envoi (`pending`), le serveur remis à zéro la reçoit de nouveau. Les
  /// autres factures (à transmettre, rejetées) partent avec leurs lignes.
  /// Renvoie le nombre de factures **non envoyées** perdues.
  @override
  Future<int> purger() async {
    final normalisee = StatutFacture.normalisee.code;
    final aSupprimer = await (_db.select(
      _db.factures,
    )..where((f) => f.statut.isNotValue(normalisee))).get();
    final perdues = aSupprimer.where((f) => f.syncStatus != 'synced').length;
    for (final f in aSupprimer) {
      await (_db.delete(
        _db.lignesFacture,
      )..where((x) => x.factureRef.equals(f.ref))).go();
    }
    await (_db.delete(
      _db.factures,
    )..where((f) => f.statut.isNotValue(normalisee))).go();
    await (_db.update(_db.factures)..where((f) => f.origine.isNull())).write(
      const FacturesCompanion(
        syncStatus: Value('pending'),
        syncMotif: Value(null),
      ),
    );
    return perdues;
  }
}
