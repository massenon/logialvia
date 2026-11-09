import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';

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
