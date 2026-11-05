/// La transmission d'une facture au service e-MECeF de la DGI.
///
/// ## Ce qui est écrit ici, et ce qui reste à confirmer
///
/// Le contrat retenu est celui d'une API REST authentifiée par jeton porteur :
/// un POST du corps de la facture, une réponse portant le code de
/// normalisation, le NIM, le compteur et un lien de vérification.
///
/// ⚠️ **Ce contrat n'a pas été éprouvé contre le service réel.** Ni jeton ni
/// accès réseau n'étaient disponibles à l'écriture. Les noms de champs de
/// [_corps] et de [ReponseMecef.depuisJson] doivent être confrontés à la
/// documentation de la DGI avant la première transmission en production —
/// c'est une correspondance à vérifier, pas une devinette à laisser vivre.
///
/// Le reste du module ne dépend pas de ce détail : la facture existe, se
/// numérote, se calcule et s'imprime sans lui. Seul le passage de « à
/// transmettre » à « normalisée » traverse ce fichier.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../entities/facture_mecef.dart';

/// Ce que la DGI renvoie quand elle accepte une facture.
class ReponseMecef {
  const ReponseMecef({
    required this.codeMecef,
    required this.nim,
    this.compteur,
    this.lienVerification,
    this.dateNormalisation,
  });

  final String codeMecef;
  final String nim;
  final String? compteur;
  final String? lienVerification;
  final DateTime? dateNormalisation;

  /// ⚠️ Noms de champs à confirmer contre la documentation DGI.
  static ReponseMecef depuisJson(Map<String, dynamic> json) {
    String? texte(List<String> cles) {
      for (final c in cles) {
        final v = json[c];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final code = texte(['codeMECeFDGI', 'code_mecef', 'codeMecef', 'code']);
    final nim = texte(['nim', 'NIM']);
    if (code == null || nim == null) {
      throw const FormatException(
        'Réponse e-MECeF sans code de normalisation ni NIM : la facture ne '
        'peut pas être déclarée normalisée.',
      );
    }
    final date = texte(['dateTime', 'date_normalisation', 'horodatage']);
    return ReponseMecef(
      codeMecef: code,
      nim: nim,
      compteur: texte(['counters', 'compteur']),
      lienVerification: texte(['qrCode', 'lien_verification', 'lien']),
      dateNormalisation: date == null ? null : DateTime.tryParse(date),
    );
  }
}

/// L'échec d'une transmission, avec de quoi l'expliquer à l'utilisatrice.
class EchecTransmission implements Exception {
  const EchecTransmission(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Le jeton e-MECeF, hors de la base.
///
/// La base SQLite se recopie à chaque sauvegarde, et une sauvegarde se
/// transporte sur une clé USB. Un secret fiscal n'y a pas sa place : il vit
/// dans le magasin sécurisé du système, comme le veut déjà la note de
/// `PARAMETRES_ENTREPRISE` pour le mot de passe SMTP.
class DepotJetonMecef {
  const DepotJetonMecef([this._stockage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _stockage;

  static const String _cle = 'mecef_jeton';

  /// Lit le jeton, ou `null` si le magasin est indisponible.
  ///
  /// Le magasin securise est un plugin de plateforme : il n'existe pas dans un
  /// test, et il peut echouer sur un poste ou le service de credentials est
  /// desactive. Une exception remonterait jusqu'a faire ecran blanc sur la
  /// Facturation. Un jeton illisible **est** un jeton absent : la facture
  /// reste « A transmettre », ce qui est exactement le comportement voulu.
  Future<String?> lire() async {
    try {
      return await _stockage.read(key: _cle);
    } on Exception {
      return null;
    }
  }

  Future<void> ecrire(String jeton) =>
      _stockage.write(key: _cle, value: jeton.trim());

  Future<void> effacer() async {
    try {
      await _stockage.delete(key: _cle);
    } on Exception {
      // Rien a effacer si le magasin ne repond pas.
    }
  }

  Future<bool> get renseigne async => (await lire())?.isNotEmpty ?? false;
}

/// Le client e-MECeF.
abstract class ClientMecef {
  /// Transmet une facture et renvoie ce que la DGI a rendu.
  ///
  /// Lève [EchecTransmission] si la transmission échoue, pour quelque raison
  /// que ce soit — y compris l'absence de connexion.
  Future<ReponseMecef> transmettre(FactureMecef facture);
}

/// Le client HTTP réel.
class ClientMecefHttp implements ClientMecef {
  const ClientMecefHttp({
    required this.urlBase,
    required this.jeton,
    this.ifuEmetteur,
    // Injectable pour les tests : ils ne doivent pas ouvrir de socket.
    this.clientInjecte,
  });

  final String urlBase;
  final String jeton;
  final String? ifuEmetteur;
  final http.Client? clientInjecte;

  @override
  Future<ReponseMecef> transmettre(FactureMecef facture) async {
    final client = clientInjecte ?? http.Client();
    try {
      final reponse = await client
          .post(
            Uri.parse('${urlBase.replaceAll(RegExp(r'/+$'), '')}/invoice'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jeton',
            },
            body: jsonEncode(_corps(facture)),
          )
          .timeout(const Duration(seconds: 20));

      if (reponse.statusCode < 200 || reponse.statusCode >= 300) {
        throw EchecTransmission(
          'e-MECeF a refusé la facture ${facture.reference} '
          '(HTTP ${reponse.statusCode}) : ${_extraitLisible(reponse.body)}',
        );
      }
      final json = jsonDecode(reponse.body);
      if (json is! Map<String, dynamic>) {
        throw const EchecTransmission(
          'Réponse e-MECeF illisible : un objet JSON était attendu.',
        );
      }
      return ReponseMecef.depuisJson(json);
    } on EchecTransmission {
      rethrow;
    } on FormatException catch (e) {
      throw EchecTransmission(e.message);
    } catch (e) {
      // Coupure reseau, DNS, delai depasse : la facture reste a transmettre.
      throw EchecTransmission(
        'Transmission impossible : $e. La facture reste « À transmettre ».',
      );
    } finally {
      if (clientInjecte == null) client.close();
    }
  }

  /// ⚠️ Noms de champs à confirmer contre la documentation DGI.
  Map<String, dynamic> _corps(FactureMecef facture) => {
    'ifu': ifuEmetteur,
    'type': facture.type.code,
    'reference': facture.reference,
    'dateTime': facture.date.toIso8601String(),
    if (facture.origineRef != null) 'reference_origine': facture.origineRef,
    if (facture.motif != null) 'motif': facture.motif,
    'client': {
      'nom': facture.client,
      if (facture.clientIfu != null) 'ifu': facture.clientIfu,
      if (facture.clientAdresse != null) 'adresse': facture.clientAdresse,
    },
    'items': [
      for (final l in facture.lignes)
        {
          'name': l.designation,
          'quantity': l.quantite,
          'price': l.prixUnitaireHt,
          'taxGroup': l.groupeTaxe,
        },
    ],
  };

  static String _extraitLisible(String corps) {
    final nettoye = corps.trim();
    if (nettoye.isEmpty) return 'aucun détail fourni';
    return nettoye.length > 300 ? '${nettoye.substring(0, 300)}…' : nettoye;
  }
}
