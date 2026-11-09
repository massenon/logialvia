import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/table_poste.dart';
import 'regle_referentiel.dart';

/// `parametres_entreprise` — référentiel : le serveur gagne (`46_` §2.2).
///
/// ## Ce qui n'est PAS absorbé, et pourquoi
///
/// - `chemin_logo`, `chemin_favicon` : des chemins de fichiers **de cette
///   machine** ; ceux du serveur ne veulent rien dire ici.
/// - `mode_donnees_test` : le **verrou de sécurité** de l'onglet Données de Test
///   (remise à zéro de l'activité). Un serveur ne doit jamais pouvoir le lever.
/// - L'identifiant : la ligne du poste est toujours la n° 1.
///
/// ## Deux garde-fous contre l'effacement
///
/// - une ligne que le serveur n'a **jamais modifiée** (valeurs de semis) n'est
///   pas absorbée : voir [serveurADecide] ;
/// - une valeur `null` du serveur **n'efface jamais** une valeur locale : le web
///   est installé vide alors que le poste tient l'IFU et le RCCM de l'entreprise.
///
/// Les jetons e-MECeF et le mot de passe SMTP ne sont pas dans cette table :
/// ils restent au coffre du système, jamais synchronisés.
class TableParametresEntreprisePoste implements TablePoste {
  const TableParametresEntreprisePoste(this._db);

  final AppDatabase _db;

  @override
  String get nom => 'parametres_entreprise';

  @override
  bool get referentiel => true;

  @override
  Stream<void> get modifications => const Stream<void>.empty();

  static String? _texte(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  static int? _entier(Object? v) =>
      v is num && v == v.toInt() ? v.toInt() : null;

  @override
  Future<ResultatAbsorption> absorber(List<Map<String, dynamic>> lignes) {
    return _db.transaction(() async {
      var absorbees = 0;
      var refusees = 0;
      var conservees = 0;

      for (final l in lignes) {
        // La ligne n'existe qu'après un premier enregistrement au poste.
        var actuel = await (_db.select(
          _db.parametresEntreprise,
        )..where((p) => p.id.equals(1))).getSingleOrNull();

        final mecefActif = l['mecef_actif'] == null
            ? (actuel?.mecefActif ?? false)
            : lireBool(l['mecef_actif']);
        final prefixes = {
          for (final k in const [
            'prefixe_enclos',
            'prefixe_cage',
            'prefixe_bande',
            'prefixe_bassin',
            'prefixe_bac',
            'prefixe_parc',
          ])
            k: l[k],
        };
        final prefixeInvalide = prefixes.values.any(
          (v) =>
              v != null && (v is! String || v.trim().isEmpty || v.length > 4),
        );
        final raison = l['raison_sociale'];
        if (mecefActif == null ||
            prefixeInvalide ||
            (raison != null && _texte(raison) == null) ||
            (l['smtp_port'] != null && _entier(l['smtp_port']) == null) ||
            (l['delai_paiement_jours'] != null &&
                _entier(l['delai_paiement_jours']) == null)) {
          refusees++;
          continue;
        }

        if (!serveurADecide(l)) {
          conservees++;
          continue;
        }

        if (actuel == null) {
          await _db
              .into(_db.parametresEntreprise)
              .insert(const ParametresEntrepriseCompanion());
          actuel = await (_db.select(
            _db.parametresEntreprise,
          )..where((p) => p.id.equals(1))).getSingle();
        }

        // Une valeur null du serveur n'efface rien : `??` garde l'existant.
        String? gardeTexte(String cle, String? local) =>
            _texte(l[cle]) ?? local;
        String garde(String cle, String local) => _texte(l[cle]) ?? local;

        final nouveau = actuel.copyWith(
          raisonSociale: garde('raison_sociale', actuel.raisonSociale),
          nomPromoteur: Value(gardeTexte('nom_promoteur', actuel.nomPromoteur)),
          adresseSiege: Value(gardeTexte('adresse_siege', actuel.adresseSiege)),
          telephone: Value(gardeTexte('telephone', actuel.telephone)),
          email: Value(gardeTexte('email', actuel.email)),
          ifu: Value(gardeTexte('ifu', actuel.ifu)),
          rccm: Value(gardeTexte('rccm', actuel.rccm)),
          mecefActif: mecefActif,
          mecefUrl: Value(gardeTexte('mecef_url', actuel.mecefUrl)),
          mecefNim: Value(gardeTexte('mecef_nim', actuel.mecefNim)),
          smtpServeur: Value(gardeTexte('smtp_serveur', actuel.smtpServeur)),
          smtpPort: Value(_entier(l['smtp_port']) ?? actuel.smtpPort),
          smtpSecurite: Value(gardeTexte('smtp_securite', actuel.smtpSecurite)),
          delaiPaiementJours: Value(
            _entier(l['delai_paiement_jours']) ?? actuel.delaiPaiementJours,
          ),
          prefixeEnclos: garde('prefixe_enclos', actuel.prefixeEnclos),
          prefixeCage: garde('prefixe_cage', actuel.prefixeCage),
          prefixeBande: garde('prefixe_bande', actuel.prefixeBande),
          prefixeBassin: garde('prefixe_bassin', actuel.prefixeBassin),
          prefixeBac: garde('prefixe_bac', actuel.prefixeBac),
          prefixeParc: garde('prefixe_parc', actuel.prefixeParc),
        );
        if (nouveau != actuel) {
          await _db.update(_db.parametresEntreprise).replace(nouveau);
          absorbees++;
        }
      }
      return ResultatAbsorption(
        absorbees: absorbees,
        refusees: refusees,
        conservees: conservees,
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
