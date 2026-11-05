import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../../../core/widgets/icone_symbole.dart';
import '../../../domain/entities/tableau_bord_principal.dart';

const TextStyle _texteXs = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

/// Panneau « Alertes Critiques » — dashboard.html l.196-204.
class PanneauAlertes extends StatelessWidget {
  const PanneauAlertes({super.key, required this.alertes});

  final List<AlerteCritique> alertes;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Alertes Critiques',
      child: alertes.isEmpty
          ? const EtatVide(
              message:
                  'Aucune alerte en cours : aucun article sous son seuil, '
                  'aucune éclosion imminente, aucun solde client en attente.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final alerte in alertes) ...[
                  _LigneAlerte(alerte: alerte),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class _LigneAlerte extends StatelessWidget {
  const _LigneAlerte({required this.alerte});

  final AlerteCritique alerte;

  @override
  Widget build(BuildContext context) {
    final critique = alerte.severite == SeveriteAlerte.critique;
    // `bg-error-container` pour le critique, `bg-brand-gold/20` pour l'avertissement.
    final fond = critique
        ? AppColors.errorContainer
        : AppColors.brandGold.withValues(alpha: 0.2);
    final couleurTexte = critique ? AppColors.errorDeep : AppColors.brandNavy;

    return InkWell(
      onTap: () => context.go(alerte.route),
      borderRadius: AppRadius.cardRadius,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              IconeSymbole.depuisNom(alerte.icone),
              size: 18,
              color: couleurTexte,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                alerte.message,
                style: _texteXs.copyWith(color: couleurTexte),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartes de recensement par filiere — dashboard.html l.207-235 et cartes
/// principales de elevage-dashboard.html l.98-125.
class CarteFiliere extends StatelessWidget {
  const CarteFiliere({super.key, required this.filiere, this.cliquable = true});

  final RecensementFiliere filiere;
  final bool cliquable;

  @override
  Widget build(BuildContext context) {
    final contenu = CarteSection(
      titre: filiere.libelle,
      icone: IconeSymbole.depuisNom(filiere.icone),
      child: filiere.aDesDonnees
          ? _grilleChiffres()
          : const EtatVide(
              message:
                  'Aucune journée saisie pour cette filière. Les effectifs '
                  'apparaîtront dès la première saisie sur sa fiche.',
            ),
    );

    if (!cliquable) return contenu;
    return InkWell(
      onTap: () => context.go(filiere.route),
      borderRadius: AppRadius.cardRadius,
      child: contenu,
    );
  }

  Widget _grilleChiffres() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Chiffre(
                libelle: 'Effectif',
                valeur: '${filiere.effectif}',
              ),
            ),
            Expanded(
              child: _Chiffre(
                libelle: 'Matures',
                valeur: '${filiere.effectifMatures}',
                couleur: AppColors.successDeep,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _Chiffre(
                libelle: filiere.libelleJeunes,
                valeur: '${filiere.effectifJeunes}',
              ),
            ),
            Expanded(
              child: _Chiffre(
                libelle: 'Mortalité',
                valeur: Formats.pourcentage(filiere.tauxMortalite),
                couleur: filiere.tauxMortalite >= 2
                    ? AppColors.errorDeep
                    : AppColors.successDeep,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Carte « Couveuse » du bloc de recensement.
class CarteCouveuse extends StatelessWidget {
  const CarteCouveuse({super.key, required this.couveuse});

  final RecensementCouveuse couveuse;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/elevage/couveuse'),
      borderRadius: AppRadius.cardRadius,
      child: CarteSection(
        titre: 'Couveuse',
        icone: Symbols.egg,
        couleurIcone: AppColors.brandGold,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _Chiffre(
                    libelle: 'Cycles en cours',
                    valeur: '${couveuse.cyclesEnCours}',
                  ),
                ),
                Expanded(
                  child: _Chiffre(
                    libelle: 'Œufs chargés',
                    valeur: '${couveuse.oeufsCharges}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _Chiffre(
                    libelle: 'Taux éclosion moy.',
                    // « — » et non « 0 % » : une moyenne sur zero eclosion
                    // n'existe pas, elle ne vaut pas zero (Doc E7 §1).
                    valeur: couveuse.tauxEclosionMoyen == null
                        ? '—'
                        : Formats.pourcentage(couveuse.tauxEclosionMoyen!),
                  ),
                ),
                Expanded(
                  child: _Chiffre(
                    libelle: 'Taux perte moy.',
                    valeur: couveuse.tauxPerteMoyen == null
                        ? '—'
                        : Formats.pourcentage(couveuse.tauxPerteMoyen!),
                    couleur: AppColors.errorDeep,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.libelle, required this.valeur, this.couleur});

  final String libelle;
  final String valeur;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(libelle, style: _texteXs.copyWith(color: AppColors.outline)),
        Text(
          valeur,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 18, // `text-lg`
            fontWeight: FontWeight.w700,
            color: couleur ?? AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Onglets « Transactions Récentes » — dashboard.html l.267-290.
class TransactionsRecentes extends StatefulWidget {
  const TransactionsRecentes({super.key, required this.ventes});

  final List<TransactionRecente> ventes;

  @override
  State<TransactionsRecentes> createState() => _TransactionsRecentesState();
}

class _TransactionsRecentesState extends State<TransactionsRecentes> {
  int _ongletActif = 0;

  static const List<String> _onglets = ['Vente', 'Achat', 'Dépenses'];

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Transactions Récentes',
      icone: Symbols.receipt_long,
      action: TextButton(
        onPressed: () => context.go('/ventes'),
        child: const Text(
          'Voir tout',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.brandNavy,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                for (var i = 0; i < _onglets.length; i++)
                  _BoutonOnglet(
                    libelle: _onglets[i],
                    actif: i == _ongletActif,
                    onTap: () => setState(() => _ongletActif = i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          switch (_ongletActif) {
            0 => _listeVentes(),
            // Les modules Achats (Doc F5) et Saisie des Dépenses (Doc F6) ne
            // sont pas encore implementes : afficher des lignes ici serait de
            // la donnee inventee (Master Prompt §2.3). L'onglet dit pourquoi il
            // est vide plutot que de rester muet.
            1 => const EtatVide(
              message:
                  'Le module Achats & Commandes n\'est pas encore disponible.',
            ),
            _ => const EtatVide(
              message:
                  'Le module Saisie des Dépenses n\'est pas encore disponible.',
            ),
          },
        ],
      ),
    );
  }

  Widget _listeVentes() {
    if (widget.ventes.isEmpty) {
      return const EtatVide(
        message: 'Aucune vente enregistrée pour le moment.',
      );
    }
    return Column(
      children: [
        for (final transaction in widget.ventes)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text(transaction.libelle, style: _texteXs)),
                Text(
                  transaction.enAvance
                      ? '${Formats.nombre(transaction.montant)} F (avance)'
                      : '${Formats.nombre(transaction.montant)} F',
                  style: _texteXs.copyWith(
                    fontWeight: FontWeight.w700,
                    color: transaction.enAvance
                        ? AppColors.brandGold
                        : AppColors.brandNavy,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BoutonOnglet extends StatelessWidget {
  const _BoutonOnglet({
    required this.libelle,
    required this.actif,
    required this.onTap,
  });

  final String libelle;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: actif ? AppColors.brandNavy : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          libelle,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: actif ? AppColors.brandNavy : AppColors.outline,
          ),
        ),
      ),
    );
  }
}

/// Fil « Activités du Jour » — dashboard.html l.294-301.
class FilActivites extends StatelessWidget {
  const FilActivites({super.key, required this.activites});

  final List<ActiviteJournal> activites;

  static Color _couleur(AccentKpi accent) => switch (accent) {
    AccentKpi.navy => AccentCouleurs.navy,
    AccentKpi.info => AccentCouleurs.info,
    AccentKpi.or => AccentCouleurs.or,
    AccentKpi.succes => AccentCouleurs.succes,
    AccentKpi.erreur => AccentCouleurs.erreur,
  };

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Activités du Jour',
      child: activites.isEmpty
          ? const EtatVide(message: 'Aucune activité enregistrée aujourd\'hui.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final activite in activites) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: _couleur(activite.accent),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activite.libelle,
                              style: _texteXs.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${Formats.heure(activite.horodatage)} — ${activite.auteur}',
                              style: _texteXs.copyWith(
                                color: AppColors.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
    );
  }
}

/// Tableau « Meilleures Ventes du Mois » — dashboard.html l.302-314.
class TableauMeilleuresVentes extends StatelessWidget {
  const TableauMeilleuresVentes({super.key, required this.lignes});

  final List<MeilleureVente> lignes;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Meilleures Ventes du Mois',
      child: lignes.isEmpty
          ? const EtatVide(
              message:
                  'Aucune vente sur la période sélectionnée. Le classement '
                  'se remplira dès les premières ventes enregistrées.',
            )
          : Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.4),
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.outlineVariant),
                    ),
                  ),
                  children: [
                    _CelluleEntete('Produit'),
                    _CelluleEntete('Qté', aDroite: true),
                    _CelluleEntete('CA', aDroite: true),
                    _CelluleEntete('Activité', aDroite: true),
                  ],
                ),
                for (var i = 0; i < lignes.length; i++)
                  TableRow(
                    // Zebrage : lignes paires sur `surface-zebra`.
                    decoration: BoxDecoration(
                      color: i.isEven ? AppColors.surfaceZebra : null,
                      border: const Border(
                        bottom: BorderSide(color: AppColors.outlineVariant),
                      ),
                    ),
                    children: [
                      _Cellule(lignes[i].produit),
                      _Cellule(
                        Formats.nombre(lignes[i].quantite),
                        aDroite: true,
                      ),
                      _Cellule(
                        Formats.nombre(lignes[i].chiffreAffaires),
                        aDroite: true,
                      ),
                      _Cellule(
                        lignes[i].activite,
                        aDroite: true,
                        couleur: lignes[i].activite == 'Commerce'
                            ? AppColors.brandGold
                            : AppColors.brandNavy,
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}

class _CelluleEntete extends StatelessWidget {
  const _CelluleEntete(this.libelle, {this.aDroite = false});

  final String libelle;
  final bool aDroite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Text(
        libelle,
        textAlign: aDroite ? TextAlign.right : TextAlign.left,
        style: _texteXs.copyWith(color: AppColors.outline),
      ),
    );
  }
}

class _Cellule extends StatelessWidget {
  const _Cellule(this.libelle, {this.aDroite = false, this.couleur});

  final String libelle;
  final bool aDroite;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Text(
        libelle,
        textAlign: aDroite ? TextAlign.right : TextAlign.left,
        style: _texteXs.copyWith(color: couleur),
      ),
    );
  }
}
