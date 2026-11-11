/// Paramètres généraux de l'exploitation — Doc F8 Onglet 2.
class ParametresEntrepriseModele {
  const ParametresEntrepriseModele({
    required this.raisonSociale,
    this.nomPromoteur,
    this.adresseSiege,
    this.telephone,
    this.email,
    this.ifu,
    this.rccm,
    this.mecefActif = false,
    this.mecefUrl,
    this.mecefNim,
    this.smtpServeur,
    this.smtpPort,
    this.smtpSecurite,
    this.delaiPaiementJours,
    this.modeDonneesTest = false,
    this.cheminLogo,
    this.cheminFavicon,
  });

  final String raisonSociale;
  final String? nomPromoteur;
  final String? adresseSiege;
  final String? telephone;
  final String? email;
  final String? ifu;
  final String? rccm;
  final bool mecefActif;

  /// URL du service e-MECeF de la DGI.
  final String? mecefUrl;

  /// Numero d'Identification de la Machine. Public : il s'imprime sur chaque
  /// facture normalisee. Le **jeton**, lui, n'est pas ici -- voir
  /// `DepotJetonMecef`.
  final String? mecefNim;
  final String? smtpServeur;
  final int? smtpPort;
  final String? smtpSecurite;

  /// Délai de paiement accordé par défaut, en jours.
  ///
  /// Pré-remplit « Payable le » au point de vente et sur les achats à crédit.
  /// `null` tant qu'il n'est pas fixé — et dans ce cas **aucune échéance n'est
  /// proposée** : une valeur inventée produirait des retards fictifs et des
  /// lettres de relance injustifiées.
  final int? delaiPaiementJours;

  /// Autorise l'onglet « Données de Test ». Faux par défaut — voir la table.
  final bool modeDonneesTest;

  /// Logo et favicon : des chemins de fichiers **de ce poste** (copies faites par
  /// `ServiceImagesEntreprise`), jamais synchronisés.
  final String? cheminLogo;
  final String? cheminFavicon;

  /// **BR-ADM-004** : le module MeCeF (Machine Électronique Certifiée
  /// Fiscalement, dispositif réglementaire béninois) n'est activable que si
  /// l'IFU **et** le RCCM sont renseignés — Doc F8 Onglet 2, Doc B6.
  bool get mecefActivable =>
      (ifu?.trim().isNotEmpty ?? false) && (rccm?.trim().isNotEmpty ?? false);

  /// Niveaux de sécurité SMTP proposés par le prototype.
  static const List<String> securitesSmtp = ['TLS', 'SSL', 'Aucun'];

  ParametresEntrepriseModele copyWith({
    String? raisonSociale,
    String? nomPromoteur,
    String? adresseSiege,
    String? telephone,
    String? email,
    String? ifu,
    String? rccm,
    bool? mecefActif,
    String? mecefUrl,
    String? mecefNim,
    String? smtpServeur,
    int? smtpPort,
    String? smtpSecurite,
    int? delaiPaiementJours,
    bool? modeDonneesTest,
    Object? cheminLogo = _inchange,
    Object? cheminFavicon = _inchange,
  }) {
    return ParametresEntrepriseModele(
      raisonSociale: raisonSociale ?? this.raisonSociale,
      nomPromoteur: nomPromoteur ?? this.nomPromoteur,
      adresseSiege: adresseSiege ?? this.adresseSiege,
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      ifu: ifu ?? this.ifu,
      rccm: rccm ?? this.rccm,
      mecefActif: mecefActif ?? this.mecefActif,
      mecefUrl: mecefUrl ?? this.mecefUrl,
      mecefNim: mecefNim ?? this.mecefNim,
      smtpServeur: smtpServeur ?? this.smtpServeur,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpSecurite: smtpSecurite ?? this.smtpSecurite,
      delaiPaiementJours: delaiPaiementJours ?? this.delaiPaiementJours,
      modeDonneesTest: modeDonneesTest ?? this.modeDonneesTest,
      // `null` explicite = retirer l'image ; absent = inchangé.
      cheminLogo: identical(cheminLogo, _inchange)
          ? this.cheminLogo
          : cheminLogo as String?,
      cheminFavicon: identical(cheminFavicon, _inchange)
          ? this.cheminFavicon
          : cheminFavicon as String?,
    );
  }
}

const Object _inchange = Object();
