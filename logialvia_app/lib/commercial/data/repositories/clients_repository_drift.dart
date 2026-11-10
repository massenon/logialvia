import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../domain/entities/client.dart';
import '../../domain/entities/vente.dart';

/// Dépôt des clients et créances — Doc F4 Écran 3.
abstract class ClientsRepository {
  Future<List<Client>> chargerClients();
  Future<List<Creance>> chargerCreances();
  Future<Client> creerClient({
    required String nom,
    String? telephone,
    DateTime? dateNaissance,
  });
  Future<void> enregistrerContact(String clientId);
}

class ClientsRepositoryDrift implements ClientsRepository {
  const ClientsRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<Client>> chargerClients() async {
    final lignes = await (_db.select(
      _db.clients,
    )..orderBy([(c) => OrderingTerm.asc(c.nom)])).get();
    final ventes = await _db.select(_db.ventes).get();

    return [
      for (final c in lignes)
        () {
          // Agregats RECALCULES depuis VENTES, jamais lus depuis un cumul
          // stocke : un cumul derive finit toujours par diverger de sa source.
          final siennes = ventes.where(
            (v) => v.client == c.nom && v.status != StatutVente.annulee,
          );
          return Client(
            id: c.id,
            nom: c.nom,
            telephone: c.telephone,
            dateNaissance: c.dateNaissance,
            dernierContact: c.dernierContact,
            totalAchats: siennes.fold<double>(0, (s, v) => s + v.total),
            soldeActuel: siennes
                .where((v) => v.status == StatutVente.avance)
                .fold<double>(0, (s, v) => s + (v.total - v.paye)),
          );
        }(),
    ];
  }

  @override
  Future<List<Creance>> chargerCreances() async {
    final ventes =
        await (_db.select(_db.ventes)
              ..where((v) => v.status.equals(StatutVente.avance))
              ..orderBy([(v) => OrderingTerm.asc(v.dateVente)]))
            .get();

    return [
      for (final v in ventes)
        Creance(
          client: v.client,
          referenceVente: v.ref,
          montantTotal: v.total,
          dejaRegle: v.paye,
          dateVente: v.dateVente,
        ),
    ];
  }

  @override
  Future<Client> creerClient({
    required String nom,
    String? telephone,
    DateTime? dateNaissance,
  }) async {
    final id = nouvelUuid();
    await _db
        .into(_db.clients)
        .insert(
          ClientsCompanion.insert(
            id: Value(id),
            nom: nom,
            telephone: Value(telephone),
            dateNaissance: Value(dateNaissance),
          ),
        );
    return Client(
      id: id,
      nom: nom,
      telephone: telephone,
      dateNaissance: dateNaissance,
    );
  }

  @override
  Future<void> enregistrerContact(String clientId) async {
    // Toute modification locale repasse la ligne a envoyer, avec un nouvel
    // instant de saisie : sans cela, le serveur ne la recevrait jamais.
    await (_db.update(_db.clients)..where((c) => c.id.equals(clientId))).write(
      ClientsCompanion(
        dernierContact: Value(DateTime.now()),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
  }
}
