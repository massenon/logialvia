/// Livraison d'une vente — `#modal-livraison` de `ventes.html`.
///
/// ## ⚠️ Le prototype n'enregistre rien de cette modale
///
/// `validateSale()` ne lit **aucun** de ses champs : ni le mode, ni les frais,
/// ni l'adresse ne survivent au clic sur « Valider ». Même « Livraison facturée
/// séparément » avec un montant saisi n'affecte pas le total encaissé. C'est
/// l'anti-patron que le Master Prompt §2.3 interdit.
///
/// Ici la livraison est persistée sur la vente (schéma v14) et les frais
/// **entrent réellement dans le total** quand le mode l'indique — c'est la
/// seule lecture cohérente de « facturée séparément ».
class Livraison {
  const Livraison({required this.mode, this.frais, this.adresse, this.contact});

  final ModeLivraison mode;

  /// Uniquement en [ModeLivraison.facturee].
  final double? frais;

  final String? adresse;
  final String? contact;

  /// Montant à ajouter au total de la vente.
  ///
  /// Les 3 autres modes n'ajoutent rien : offerte, assurée par le client, ou
  /// déjà comprise dans le montant négocié.
  double get supplementFacture =>
      mode == ModeLivraison.facturee ? (frais ?? 0) : 0;

  String? valider() {
    if (mode == ModeLivraison.facturee && (frais == null || frais! <= 0)) {
      return 'Une livraison facturée séparément exige un montant de frais.';
    }
    if (frais != null && frais! < 0) {
      return 'Les frais de livraison ne peuvent pas être négatifs.';
    }
    return null;
  }
}

/// Les 4 options du sélecteur, dans l'ordre du prototype.
enum ModeLivraison {
  gratuite('gratuite', 'Livraison gratuite (offerte)'),
  client('client', 'Livraison assurée par le client'),
  incluse('incluse', 'Prix de livraison inclus dans le montant'),
  facturee('facturee', 'Livraison facturée séparément');

  const ModeLivraison(this.code, this.libelle);

  final String code;
  final String libelle;

  static ModeLivraison? depuisCode(String? code) {
    if (code == null) return null;
    for (final m in ModeLivraison.values) {
      if (m.code == code) return m;
    }
    return null;
  }
}
