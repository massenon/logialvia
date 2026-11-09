import 'package:drift/drift.dart';

import '../../../administration/data/sync/depot_demandes_referentiel.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';

/// `produits_vendables` — **référentiel** : le serveur gagne (`46_` §2.2).
///
/// - Le poste ne l'envoie jamais ; il le **propose** (`DepotDemandesReferentiel`).
/// - **Le stock n'est JAMAIS absorbé** : c'est une donnée dérivée (ventes, achats),
///   propre à chaque poste. Un produit créé par un autre poste arrive avec un
///   stock de 0 ; un produit connu garde le sien.
/// - Règle du plus récent, comme partout : une demande locale en attente n'est
///   supplantée que par une décision du serveur **postérieure** à la saisie.
/// - Une remise à zéro préserve le catalogue (blueprint §6).
class TableProduitsPoste implements TablePoste {
  const TableProduitsPoste(this._db);

  final AppDatabase _db;

  DepotDemandesReferentiel get _depot => DepotDemandesReferentiel(_db);

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  String get nom => 'produits_vendables';

  @override
  bool get referentiel => true;

  @override
  Stream<void> get modifications => const Stream<void>.empty();

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;
      var supplantees = 0;

      for (final l in lignes) {
        final id = l['id'];
        final nomProduit = _texte(l['name']);
        final cat = _texte(l['cat']);
        final unite = _texte(l['unit']);
        final icone = _texte(l['icon']);
        final prix = l['price'];
        final prixMax = l['price_max'];
        final cout = l['cout_revient'];
        final seuil = l['threshold'];
        // Strict : une ligne incohérente est refusée, jamais lissée.
        if (id is! String ||
            !_uuid.hasMatch(id) ||
            nomProduit == null ||
            cat == null ||
            unite == null ||
            icone == null ||
            prix is! num ||
            prix <= 0 ||
            (prixMax != null && (prixMax is! num || prixMax < prix)) ||
            (cout != null && (cout is! num || cout < 0)) ||
            (seuil != null && (seuil is! num || seuil < 0))) {
          refusees++;
          continue;
        }

        final demande = await _depot.enAttente(
          DepotDemandesReferentiel.typeProduit,
          id,
        );
        if (demande != null) {
          final serveur = DateTime.tryParse('${l['saisi_le']}');
          if (serveur == null ||
              !serveur.isAfter(DateTime.parse(demande.saisiLe))) {
            conservees++; // la saisie locale est plus récente : elle partira
            continue;
          }
        }

        final locale = await (_db.select(
          _db.produitsVendables,
        )..where((p) => p.id.equals(id))).getSingleOrNull();

        if (locale == null) {
          await _db
              .into(_db.produitsVendables)
              .insert(
                ProduitsVendablesCompanion.insert(
                  id: Value(id),
                  sku: Value(_texte(l['sku'])),
                  name: nomProduit,
                  cat: cat,
                  price: prix.toDouble(),
                  priceMax: Value((prixMax as num?)?.toDouble()),
                  unit: unite,
                  icon: icone,
                  coutRevient: Value((cout as num?)?.toDouble()),
                  groupeTaxe: Value(_texte(l['groupe_taxe']) ?? 'A'),
                  stock: 0, // jamais synchronisé : propre à ce poste
                  threshold: (seuil as num?)?.toInt() ?? 0,
                  espece: Value(_texte(l['espece'])),
                ),
              );
          absorbees++;
        } else {
          final nouveau = locale.copyWith(
            sku: Value(_texte(l['sku'])),
            name: nomProduit,
            cat: cat,
            price: prix.toDouble(),
            priceMax: Value((prixMax as num?)?.toDouble()),
            unit: unite,
            icon: icone,
            coutRevient: Value((cout as num?)?.toDouble()),
            groupeTaxe: _texte(l['groupe_taxe']) ?? locale.groupeTaxe,
            threshold: (seuil as num?)?.toInt() ?? locale.threshold,
            espece: Value(_texte(l['espece'])),
            // `stock` : volontairement absent.
          );
          if (nouveau != locale) {
            await _db.update(_db.produitsVendables).replace(nouveau);
            absorbees++;
            if (demande != null) supplantees++;
          }
        }
        if (demande != null) await _depot.abandonner(demande.id);
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
  Future<List<LigneAEnvoyer>> aEnvoyer() async => const [];

  @override
  Future<void> marquerSynchronise(String id, String instantEnvoye) async {}

  @override
  Future<void> marquerConflit(String id, String motif) async {}

  @override
  Future<int> purger() async => 0;
}
