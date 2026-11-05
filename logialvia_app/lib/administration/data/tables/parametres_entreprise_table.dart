import 'package:drift/drift.dart';

/// Table `PARAMETRES_ENTREPRISE` — **absente de Doc D1**.
///
/// L'onglet « Données de l'Entreprise » de `parametres-generaux.html` saisit
/// la raison sociale, les informations légales (IFU, RCCM) et la configuration
/// SMTP. Aucune table du dictionnaire ne permettait de les stocker : l'écran
/// aurait été un formulaire sans persistance, donc purement décoratif
/// (Master Prompt §2.3).
///
/// **Table à ligne unique** : `id` est contraint à 1. Un `insertOnConflictUpdate`
/// sur cette clé garantit qu'il n'existe jamais deux jeux de paramètres
/// concurrents.
@DataClassName('ParametresEntrepriseRow')
class ParametresEntreprise extends Table {
  /// Toujours 1 — voir la note ci-dessus.
  IntColumn get id => integer().withDefault(const Constant(1))();

  // --- Informations Générales ---

  /// Requis (F8 Onglet 2).
  TextColumn get raisonSociale =>
      text().withDefault(const Constant('ALLMANY ET COMPAGNIE'))();

  TextColumn get nomPromoteur => text().nullable()();
  TextColumn get adresseSiege => text().nullable()();
  TextColumn get telephone => text().nullable()();
  TextColumn get email => text().nullable()();

  // --- Informations Légales & Fiscales ---

  /// Identifiant Fiscal Unique — **chiffres uniquement** (F8 Onglet 2).
  TextColumn get ifu => text().nullable()();

  /// Registre du Commerce, optionnel.
  TextColumn get rccm => text().nullable()();

  /// BR-ADM-004 : le module MeCeF n'est activable que si IFU **et** RCCM sont
  /// renseignes. Cet indicateur ne peut donc pas etre vrai sans eux.
  BoolColumn get mecefActif => boolean().withDefault(const Constant(false))();

  /// URL du service e-MECeF de la DGI.
  TextColumn get mecefUrl => text().nullable()();

  /// Numero d'Identification de la Machine, tel que la DGI l'a attribue.
  /// Public : il s'imprime sur chaque facture normalisee.
  TextColumn get mecefNim => text().nullable()();

  // NOTE SECURITE : le **jeton** e-MECeF n'est volontairement pas stocke ici,
  // pour la meme raison que le mot de passe SMTP ci-dessous -- un secret n'a
  // pas sa place en clair dans un fichier SQLite que n'importe quelle
  // sauvegarde recopie. Voir `DepotJetonMecef`.

  // --- Configuration Email (SMTP) ---

  TextColumn get smtpServeur => text().nullable()();
  IntColumn get smtpPort => integer().nullable()();

  /// 'TLS', 'SSL' ou 'Aucun'.
  TextColumn get smtpSecurite => text().nullable()();

  // NOTE SECURITE (Doc I3 §3, Strict Avoid §13) : le mot de passe SMTP n'est
  // volontairement PAS stocke ici. Un secret n'a pas sa place dans la base
  // SQLite en clair — il devra passer par `flutter_secure_storage` le jour ou
  // l'envoi d'e-mails sera reellement implemente.

  /// Chemins des fichiers copies dans le dossier applicatif (Doc I3 §2 :
  /// nom genere, jamais le nom d'origine fourni par l'utilisateur).
  TextColumn get cheminLogo => text().nullable()();
  TextColumn get cheminFavicon => text().nullable()();

  // --- Numerotation des bandes et sujets (parametres-elevage.html Onglet 4) ---
  //
  // Le prototype les range dans `localStorage.logialvia_numerotation_config`.
  // Ce sont des parametres d'entreprise au meme titre que la raison sociale :
  // ils vivent dans la meme ligne unique plutot que dans une table dediee.

  /// Prefixe des enclos — Aviculture (Goliaths & Pintades). Apercu « E1, E2 ».
  /// Délai de paiement accordé par défaut, en jours.
  ///
  /// Pré-remplit « Payable le » au point de vente et sur les achats à crédit ;
  /// la caissière peut l'écraser au cas par cas.
  ///
  /// `null` tant que la Gérante ne l'a pas fixé — et c'est volontaire : aucune
  /// valeur n'a été communiquée, en inventer une (« 30 jours ») produirait des
  /// retards fictifs et des lettres de relance injustifiées.
  IntColumn get delaiPaiementJours => integer().nullable()();

  /// Autorise l'onglet « Données de Test » des Paramètres Généraux.
  ///
  /// **Faux par defaut, et c'est le point.** L'onglet donne acces a une remise
  /// a zero de toute l'activite ; le laisser accessible en permanence sur un
  /// poste partage entre trois roles, c'est attendre l'accident. Le mode se
  /// bascule volontairement pendant la periode d'essai, puis se referme le
  /// jour ou l'exploitation demarre pour de bon.
  BoolColumn get modeDonneesTest =>
      boolean().withDefault(const Constant(false))();

  TextColumn get prefixeEnclos =>
      text().withDefault(const Constant('E')).withLength(max: 4)();

  /// Prefixe des cages — Cuniculture (Lapins). Apercu « C1, C2, C5, C12 ».
  TextColumn get prefixeCage =>
      text().withDefault(const Constant('C')).withLength(max: 4)();

  /// Prefixe des bandes — Cuniculture. Apercu « B1, B2 ».
  TextColumn get prefixeBande =>
      text().withDefault(const Constant('B')).withLength(max: 4)();

  /// Prefixe des bassins — Pisciculture (Poissons-Chats). Apercu « B1, B2, B3 ».
  TextColumn get prefixeBassin =>
      text().withDefault(const Constant('B')).withLength(max: 4)();

  @override
  Set<Column> get primaryKey => {id};
}
