import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../domain/repositories/tableau_bord_repository.dart';

/// # Popup « Alertes Critiques de Stock »
///
/// S'ouvre au chargement du tableau de bord dès qu'un article est passé sous
/// son seuil d'alerte.
///
/// ## Pourquoi une popup alors que la cloche existe déjà
///
/// La cloche et le panneau « Alertes Critiques » affichent la même liste, mais
/// tous deux **attendent qu'on les regarde**. Une rupture de provende ne se
/// rattrape pas : les animaux mangent tous les jours, et le fournisseur est à
/// Natitingou. L'information doit venir chercher la Gérante, pas l'inverse.
///
/// ## Ce qu'elle ne fait pas
///
/// Elle ne commande rien et ne modifie aucun stock. Passer commande engage de
/// l'argent : ce geste reste explicite, dans Achats & Commandes. La popup
/// informe et ouvre le bon écran, rien de plus.
///
/// ## Report
///
/// « Plus tard » vaut pour la session, comme pour la Prophylaxie du Jour.
/// Rouvrir la même popup à chaque retour au tableau de bord la transformerait
/// en obstacle, et un obstacle finit par se cliquer sans se lire. Rien n'est
/// écrit en base : elle revient au prochain démarrage tant que le stock est
/// sous le seuil.
class AlertesStockCritique {
  AlertesStockCritique._();

  static bool _reportee = false;

  /// Remet le report à zéro — utile aux tests, qui ne doivent pas dépendre
  /// de ce qu'un test précédent a fermé.
  @visibleForTesting
  static void reinitialiserReport() => _reportee = false;

  /// Ouvre la popup s'il y a lieu.
  static Future<void> ouvrirSiNecessaire(
    BuildContext context,
    List<ArticleEnAlerte> articles,
  ) async {
    if (_reportee) return;
    if (articles.isEmpty) return;
    if (!context.mounted) return;
    await afficher(context, articles);
    _reportee = true;
  }

  static Future<void> afficher(
    BuildContext context,
    List<ArticleEnAlerte> articles,
  ) {
    // Les intrants d'abord : une rupture de provende arrete l'elevage, une
    // rupture de produit fini ne fait perdre qu'une vente.
    final ordonnes = [...articles]
      ..sort((a, b) {
        if (a.estIntrant != b.estIntrant) return a.estIntrant ? -1 : 1;
        return (a.stock - a.seuil).compareTo(b.stock - b.seuil);
      });

    return AppModal.show<void>(
      context,
      title: 'Alertes Critiques de Stock',
      maxWidth: 560,
      child: _Corps(articles: ordonnes),
      actions: [
        Builder(
          builder: (ctx) => AppButton(
            label: 'Plus tard',
            variant: AppButtonVariant.outline,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ),
        Builder(
          builder: (ctx) => AppButton(
            label: 'Ouvrir la Gestion des Stocks',
            icon: Symbols.inventory_2,
            onPressed: () {
              Navigator.of(ctx).pop();
              ctx.go('/stocks');
            },
          ),
        ),
      ],
    );
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.articles});

  final List<ArticleEnAlerte> articles;

  @override
  Widget build(BuildContext context) {
    final intrants = articles.where((a) => a.estIntrant).length;
    final produits = articles.length - intrants;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.errorContainer,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Symbols.warning, size: 20, color: AppColors.errorDeep),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _resume(intrants, produits),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.errorDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final a in articles) _Ligne(article: a)],
            ),
          ),
        ),
      ],
    );
  }

  /// Le résumé nomme les deux natures de stock séparément : elles ne se
  /// réapprovisionnent pas de la même façon ni au même endroit.
  static String _resume(int intrants, int produits) {
    final morceaux = <String>[
      if (intrants > 0)
        '$intrants intrant${intrants > 1 ? "s" : ""} sous le seuil',
      if (produits > 0)
        '$produits produit${produits > 1 ? "s" : ""} fini${produits > 1 ? "s" : ""} '
            'sous le seuil',
    ];
    return '${morceaux.join(" et ")}. Un réapprovisionnement est à prévoir.';
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.article});

  final ArticleEnAlerte article;

  static const TextStyle _texte = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 12,
    color: AppColors.onSurface,
  );

  @override
  Widget build(BuildContext context) {
    final manque = article.seuil - article.stock;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            article.estIntrant ? Symbols.inventory_2 : Symbols.sell,
            size: 18,
            color: AppColors.outline,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  article.libelle,
                  style: _texte.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  article.estIntrant ? 'Intrant' : 'Produit fini',
                  style: _texte.copyWith(
                    fontSize: 10,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${article.stock} / ${article.seuil} ${article.unite}',
            style: _texte,
          ),
          const SizedBox(width: AppSpacing.md),
          // Le manque est la seule information qui dise quoi faire : c'est la
          // quantite a commander pour repasser au-dessus du seuil.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: AppRadius.pill,
            ),
            child: Text(
              manque > 0 ? 'manque $manque' : 'au seuil',
              style: _texte.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.errorDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
