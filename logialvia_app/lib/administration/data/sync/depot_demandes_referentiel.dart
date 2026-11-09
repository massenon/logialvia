import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../repositories/preferences_poste_repository.dart';

/// La file des demandes de modification de référentiel (voir
/// `DemandesReferentiel`). Écrite par les dépôts qui modifient un module ou les
/// paramètres, lue par le moteur de synchronisation.
class DepotDemandesReferentiel {
  const DepotDemandesReferentiel(this._db);

  final AppDatabase _db;

  /// Émet à chaque changement de la file (dépôt, accusé, abandon).
  Stream<void> get modifications => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.demandesReferentiel))
      .map((_) {});

  static const String typeModule = 'module_actif';
  static const String typeParametres = 'parametres_entreprise';
  static const String cleParametres = 'parametres';
  static const String typeProduit = 'produit_vendable';
  static const String typeIntrant = 'intrant';

  /// Champs d'un intrant proposes au serveur. JAMAIS le stock ni le PMP : propres a
  /// chaque poste (« stock propre a chaque poste + journal partage »).
  static Map<String, Object?> champsIntrant(IntrantRow i) => {
    'code': i.code,
    'name': i.name,
    'cat': i.cat,
    'unit': i.unit,
    'threshold': i.threshold,
  };

  /// Champs d'un produit proposes au serveur. JAMAIS le stock : donnee derivee
  /// (ventes, achats), propre a chaque poste.
  static Map<String, Object?> champsProduit(ProduitVendableRow p) => {
    'id': p.id,
    'sku': p.sku,
    'name': p.name,
    'cat': p.cat,
    'price': p.price,
    'price_max': p.priceMax,
    'unit': p.unit,
    'icon': p.icon,
    'cout_revient': p.coutRevient,
    'groupe_taxe': p.groupeTaxe,
    'threshold': p.threshold,
    'espece': p.espece,
  };

  /// Champs de `parametres_entreprise` que le poste propose. Jamais les chemins
  /// du logo et du favicon (propres à cette machine), ni `mode_donnees_test`
  /// (verrou de sécurité local) : le serveur les refuserait de toute façon.
  static Map<String, Object?> champsParametres(ParametresEntrepriseRow p) => {
    'raison_sociale': p.raisonSociale,
    'nom_promoteur': p.nomPromoteur,
    'adresse_siege': p.adresseSiege,
    'telephone': p.telephone,
    'email': p.email,
    'ifu': p.ifu,
    'rccm': p.rccm,
    'mecef_actif': p.mecefActif,
    'mecef_url': p.mecefUrl,
    'mecef_nim': p.mecefNim,
    'smtp_serveur': p.smtpServeur,
    'smtp_port': p.smtpPort,
    'smtp_securite': p.smtpSecurite,
    'delai_paiement_jours': p.delaiPaiementJours,
    'prefixe_enclos': p.prefixeEnclos,
    'prefixe_cage': p.prefixeCage,
    'prefixe_bande': p.prefixeBande,
    'prefixe_bassin': p.prefixeBassin,
    'prefixe_bac': p.prefixeBac,
    'prefixe_parc': p.prefixeParc,
  };

  /// Dépose une demande. Remplace toute demande **non envoyée ou refusée** de la
  /// même clé ; une demande déjà acceptée est conservée comme historique jusqu'à
  /// la suivante.
  Future<void> proposer({
    required String type,
    required String cle,
    required Map<String, Object?> donnees,
  }) async {
    await (_db.delete(_db.demandesReferentiel)..where(
          (d) =>
              d.type.equals(type) &
              d.cle.equals(cle) &
              d.syncStatus.isNotValue('synced'),
        ))
        .go();
    await _db
        .into(_db.demandesReferentiel)
        .insert(
          DemandesReferentielCompanion.insert(
            id: Value(nouvelUuid()),
            type: type,
            cle: cle,
            donnees: jsonEncode(donnees),
            saisiLe: Value(instantSaisie()),
          ),
        );
  }

  Future<void> proposerModule(String moduleId, {required bool actif}) =>
      proposer(
        type: typeModule,
        cle: moduleId,
        donnees: {'module_id': moduleId, 'is_actif': actif},
      );

  /// Propose l'état ACTUEL des paramètres (relu en base : la demande reflète ce
  /// qui est réellement enregistré, pas ce qu'un écran croyait avoir écrit).
  Future<void> proposerParametres() async {
    final ligne = await (_db.select(
      _db.parametresEntreprise,
    )..where((p) => p.id.equals(1))).getSingleOrNull();
    if (ligne == null) return;
    await proposer(
      type: typeParametres,
      cle: cleParametres,
      donnees: champsParametres(ligne),
    );
  }

  /// Propose l'état ACTUEL d'un produit (relu en base).
  Future<void> proposerProduit(String produitId) async {
    final ligne = await (_db.select(
      _db.produitsVendables,
    )..where((p) => p.id.equals(produitId))).getSingleOrNull();
    if (ligne == null) return;
    await proposer(
      type: typeProduit,
      cle: produitId,
      donnees: champsProduit(ligne),
    );
  }

  /// Suppression d'un produit : le serveur ne l'efface jamais (des ventes ou un autre
  /// poste peuvent encore le citer), il le marque archivé (pierre tombale) et le
  /// redistribue. [ligne] est l'état du produit AVANT sa suppression locale.
  Future<void> proposerArchivageProduit(ProduitVendableRow ligne) => proposer(
    type: typeProduit,
    cle: ligne.id,
    donnees: {...champsProduit(ligne), 'archive': true},
  );

  /// Une seule fois : propose TOUT le catalogue local au serveur. Les produits
  /// semés ont le même UUID sur tous les postes et le serveur accepte sans conflit
  /// ce qu'il connaît déjà à l'identique ; ceux que ce poste a créés seuls sont ainsi
  /// connus du serveur AVANT que leurs ventes n'arrivent (sinon elles seraient
  /// refusées : « produit inconnu »).
  Future<void> adopterCatalogueSiBesoin(
    PreferencesPosteRepository preferences,
  ) async {
    if (await preferences.catalogueAdopte()) return;
    for (final p in await _db.select(_db.produitsVendables).get()) {
      await proposer(type: typeProduit, cle: p.id, donnees: champsProduit(p));
    }
    await preferences.definirCatalogueAdopte();
  }

  /// Propose l'état ACTUEL d'un intrant (relu en base), sans son stock ni son PMP.
  Future<void> proposerIntrant(String code) async {
    final ligne = await (_db.select(
      _db.intrants,
    )..where((i) => i.code.equals(code))).getSingleOrNull();
    if (ligne == null) return;
    await proposer(type: typeIntrant, cle: code, donnees: champsIntrant(ligne));
  }

  /// Une seule fois : propose TOUS les intrants locaux. Les intrants semés ont les
  /// mêmes codes sur tous les postes (le serveur accepte sans conflit ce qu'il connaît
  /// à l'identique) ; ceux que ce poste a créés seuls sont ainsi connus AVANT que les
  /// achats et mouvements qui les portent n'arrivent.
  Future<void> adopterIntrantsSiBesoin(
    PreferencesPosteRepository preferences,
  ) async {
    if (await preferences.intrantsAdoptes()) return;
    for (final i in await _db.select(_db.intrants).get()) {
      await proposer(type: typeIntrant, cle: i.code, donnees: champsIntrant(i));
    }
    await preferences.definirIntrantsAdoptes();
  }

  /// La demande **en attente** de cette clé, s'il y en a une.
  Future<DemandeReferentielRow?> enAttente(String type, String cle) =>
      (_db.select(_db.demandesReferentiel)..where(
            (d) =>
                d.type.equals(type) &
                d.cle.equals(cle) &
                d.syncStatus.equals('pending'),
          ))
          .getSingleOrNull();

  Future<List<DemandeReferentielRow>> aEnvoyer() =>
      (_db.select(_db.demandesReferentiel)
            ..where((d) => d.syncStatus.equals('pending'))
            ..orderBy([(d) => OrderingTerm.asc(d.saisiLe)]))
          .get();

  /// Accusé : seulement si la demande n'a pas été REMPLACÉE depuis l'envoi.
  Future<void> marquerSynchronisee(String id, String saisiLeEnvoye) async {
    await (_db.update(
      _db.demandesReferentiel,
    )..where((d) => d.id.equals(id) & d.saisiLe.equals(saisiLeEnvoye))).write(
      const DemandesReferentielCompanion(
        syncStatus: Value('synced'),
        syncMotif: Value(null),
      ),
    );
  }

  Future<void> marquerRefusee(String id, String motif) async {
    await (_db.update(
      _db.demandesReferentiel,
    )..where((d) => d.id.equals(id))).write(
      DemandesReferentielCompanion(
        syncStatus: const Value('conflict'),
        syncMotif: Value(motif),
      ),
    );
  }

  /// Le serveur a une version plus récente : la demande est caduque.
  Future<void> abandonner(String id) =>
      (_db.delete(_db.demandesReferentiel)..where((d) => d.id.equals(id))).go();
}
