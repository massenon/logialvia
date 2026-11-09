import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/configuration_espece.dart';
import '../../../domain/entities/soin.dart';
import '../../../domain/services/rappels_prophylaxie.dart';
import '../../viewmodels/soins_view_model.dart';

/// # Popup « Prophylaxie du Jour » — `assets/js/prophylaxie-popup.js`
///
/// S'ouvre au chargement du tableau de bord quand un traitement est dû, et ne
/// se referme qu'une fois chaque ligne marquée faite.
///
/// ## ⚠️ Le prototype interroge le calendrier avec la mauvaise clé
///
/// `parametres-elevage.html` l.170 intitule la colonne « **Jour du Cycle** » et
/// `PROPHYLAXIE_STORE` y range ses échéances par espèce (goliaths : jours 1, 5,
/// 15). Mais deux consommateurs la lisent comme un **jour du mois** :
///
/// | Fichier | Clé utilisée |
/// |---|---|
/// | `prophylaxie-popup.js` l.25 | `new Date().getDate()` — jour du mois |
/// | `fiche-goliaths.html` l.488 | `PROPHYLAXIE_MULTI_CALENDAR[d]`, `d` parcourant 1→31 d'août 2026 |
///
/// Les deux jeux portent **les mêmes nombres** (1, 5, 8, 15), ce qui explique
/// que la contradiction soit passée inaperçue. Elle est pourtant réelle, et le
/// contenu tranche :
///
/// - « Anti-stress (**post-éclosion**) » au jour 3 — l'éclosion, pas le 3 du mois ;
/// - « Anti-coccidien (Jour 1/4) » au jour 5 et « (Jour 4/4) » au jour 8 — une
///   cure de 4 jours consécutifs, qui n'a de sens qu'à partir d'une date de
///   départ commune ;
/// - « Vaccin Newcastle (**Rappel**) » — un rappel se programme sur l'âge du
///   sujet, jamais sur la date du calendrier ;
/// - la `remanence` (7 j, 5 j) est un délai d'attente avant commercialisation,
///   qui court depuis l'administration.
///
/// **Le jour du cycle est la bonne clé** ; `CALENDRIER_PROPHYLAXIE` l'utilise
/// déjà. Lire le calendrier avec le jour du mois ferait rejouer le déparasitage
/// tous les 1ᵉʳ du mois à des sujets d'âges quelconques.
///
/// ## Ce que cette popup affiche donc réellement
///
/// **Les soins datés du registre**, pas le calendrier de prophylaxie. La
/// projection automatique du calendrier vers des échéances datées suppose une
/// **date de mise en bande** que le modèle de données ne stocke nulle part —
/// c'est le point ouvert 11-sexdecies de l'index maître, inchangé ici. Tant
/// qu'il n'est pas tranché, la popup travaille sur ce qui existe vraiment :
/// `SOINS_CALENDRIER`, alimenté par « Nouveau Soin » et « Planifier une
/// Intervention ».
///
/// L'écran le dit en toutes lettres plutôt que de laisser croire à une
/// injection automatique qui n'a pas lieu.
///
/// ## Deux écarts délibérés
///
/// 1. **Les retards sont inclus**, pas seulement le jour même. Un traitement
///    oublié hier est plus urgent que celui d'aujourd'hui ; l'omettre serait
///    l'enterrer. Ils sont distingués par un badge rouge.
/// 2. **Aucun `localStorage`.** Le prototype mémorise les lignes cochées sous
///    `logialvia_prophylaxie_done_AAAA-MM-JJ` — un état parallèle au registre,
///    qui diverge dès qu'on marque le soin fait depuis l'écran Soins. Ici
///    « Marquer fait » appelle `confirmerAdministration()` : le soin passe à
///    « Effectué » **en base**. La popup ne se rouvre pas parce qu'il ne reste
///    plus rien à faire, pas parce qu'un drapeau le dit.
///
/// `testerPopupProphylaxie()` — l'ouverture forcée en « MODE TEST » avec une
/// ligne d'exemple — n'est pas portée : c'est un utilitaire de démonstration du
/// prototype, qui afficherait un traitement inexistant.
class ProphylaxieDuJour {
  ProphylaxieDuJour._();

  /// Les soins qui justifient l'ouverture : dus aujourd'hui ou en retard, et
  /// pas encore administrés.
  static List<Soin> aTraiter(SoinsViewModel vm, DateTime maintenant) {
    final finDeJournee = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
      23,
      59,
      59,
    );
    final liste =
        vm.soins
            .where((s) => !s.estEffectue && !s.datePrevue.isAfter(finDeJournee))
            .toList()
          ..sort((a, b) => a.datePrevue.compareTo(b.datePrevue));
    return liste;
  }

  /// Vrai dès que la Gérante a répondu « Plus tard ».
  ///
  /// `initProphylaxieReminder()` s'exécute au `DOMContentLoaded` de chaque
  /// page : côté web, revenir au tableau de bord rouvre la popup à l'identique.
  /// Reproduire cela dans une application à navigation instantanée la ferait
  /// resurgir à chaque aller-retour — un rappel qu'on ne peut pas écarter n'est
  /// plus un rappel, c'est un obstacle. Le report vaut donc pour la session.
  ///
  /// Ce n'est pas un état parallèle au registre : rien n'est écrit nulle part,
  /// et la popup revient au prochain démarrage tant que les soins restent dus.
  static bool _reportee = false;

  /// Ouvre la popup s'il y a lieu. Le seul critère est qu'il reste un soin à
  /// administrer — il n'y a pas de drapeau « déjà validé aujourd'hui » à tenir
  /// à jour, puisque valider un soin le fait disparaître de la liste.
  static Future<void> ouvrirSiNecessaire(
    BuildContext context,
    SoinsViewModel vm, {
    List<RappelProphylaxie> rappels = const [],
  }) async {
    if (_reportee) return;
    // Deux motifs d'ouverture : un soin a administrer, ou une echeance du
    // calendrier que personne n'a planifiee. Le second manquait, et c'est
    // precisement celui de l'oubli.
    if (aTraiter(vm, DateTime.now()).isEmpty && rappels.isEmpty) return;
    if (!context.mounted) return;
    await afficher(context, vm, rappels: rappels);
    _reportee = true;
  }

  static Future<void> afficher(
    BuildContext context,
    SoinsViewModel vm, {
    List<RappelProphylaxie> rappels = const [],
  }) => AppModal.show<void>(
    context,
    title: 'Prophylaxie du Jour',
    maxWidth: 560,
    child: _CorpsProphylaxie(vm: vm, rappels: rappels),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Plus tard',
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),
    ],
  );
}

class _CorpsProphylaxie extends StatefulWidget {
  const _CorpsProphylaxie({required this.vm, this.rappels = const []});

  final SoinsViewModel vm;

  /// Les echeances du calendrier echues et jamais planifiees.
  final List<RappelProphylaxie> rappels;

  @override
  State<_CorpsProphylaxie> createState() => _CorpsProphylaxieState();
}

class _CorpsProphylaxieState extends State<_CorpsProphylaxie> {
  String? _enCours;

  @override
  Widget build(BuildContext context) {
    final maintenant = DateTime.now();
    final aTraiter = ProphylaxieDuJour.aTraiter(widget.vm, maintenant);

    final rappels = widget.rappels;

    if (aTraiter.isEmpty && rappels.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Symbols.check_circle,
            size: 40,
            color: AppColors.successDeep,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Prophylaxie du jour entièrement validée. Rendez-vous demain !',
            textAlign: TextAlign.center,
            style: _texte.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.successDeep,
            ),
          ),
        ],
      );
    }

    final dateLisible = Formats.dateLongue(maintenant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (aTraiter.isNotEmpty) ...[
          Text(
            'Traitements dus le $dateLisible selon le registre des soins.',
            style: _texte.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final soin in aTraiter) ...[
            _LigneTraitement(
              soin: soin,
              maintenant: maintenant,
              enCours: _enCours == soin.id,
              onMarquerFait: () => _marquerFait(soin),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
        // Les echeances du calendrier que personne n'a encore planifiees.
        // Elles ne figurent dans aucun registre : sans cette section, elles
        // passaient inapercues jusqu'a ce qu'on ouvre la fiche.
        if (rappels.isNotEmpty) ...[
          if (aTraiter.isNotEmpty) const Divider(height: AppSpacing.lg),
          Text(
            '${rappels.length} échéance(s) du calendrier de prophylaxie sont '
            'échues et ne sont pas encore planifiées.',
            style: _texte.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final rappel in rappels) ...[
            _LigneEcheance(rappel: rappel),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
        const SizedBox(height: AppSpacing.sm),
        // Le prototype laisse croire que le calendrier de prophylaxie alimente
        // seul cette liste. Il ne le fait pas — et ne le peut pas.
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.brandGold.withValues(alpha: 0.1),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Text(
            'Les traitements viennent du registre des soins ; les échéances '
            'viennent du calendrier de prophylaxie (Paramètres Élevage), daté '
            'depuis la mise en bande de chaque filière. Une filière sans bande '
            'déclarée ne produit aucune échéance : sa date de départ est '
            'inconnue.',
            style: _texte.copyWith(
              fontSize: 11,
              height: 1.4,
              color: AppColors.brandNavy,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _marquerFait(Soin soin) async {
    setState(() => _enCours = soin.id);
    final resultat = await widget.vm.confirmerAdministration(soin);
    if (!mounted) return;
    setState(() => _enCours = null);

    switch (resultat) {
      case Echec<void>(message: final message):
        showAppToast(context, message, type: ToastType.error);
      case Succes<void>():
        // Rien à afficher ligne par ligne : la liste se vide d'elle-même.
        if (ProphylaxieDuJour.aTraiter(widget.vm, DateTime.now()).isEmpty) {
          showAppToast(
            context,
            'Prophylaxie du jour entièrement validée. Rendez-vous demain !',
          );
          if (mounted) Navigator.of(context).pop();
        }
    }
  }
}

class _LigneTraitement extends StatelessWidget {
  const _LigneTraitement({
    required this.soin,
    required this.maintenant,
    required this.enCours,
    required this.onMarquerFait,
  });

  final Soin soin;
  final DateTime maintenant;
  final bool enCours;
  final VoidCallback onMarquerFait;

  @override
  Widget build(BuildContext context) {
    final enRetard = soin.datePrevue.isBefore(
      DateTime(maintenant.year, maintenant.month, maintenant.day),
    );
    final espece =
        ConfigurationsEspeces.parIdentifiant[soin.espece]?.libelle ??
        soin.espece;

    final detail = [
      if ((soin.produit ?? '').isNotEmpty) soin.produit!,
      if ((soin.dose ?? '').isNotEmpty) soin.dose!,
    ].join(' — ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$espece — ${soin.typeSoin}',
                        style: _texte.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ),
                    if (enRetard) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.errorContainer,
                          borderRadius: AppRadius.pill,
                        ),
                        child: Text(
                          'En retard — ${Formats.date(soin.datePrevue)}',
                          style: _texte.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.errorDeep,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: _texte.copyWith(
                      fontSize: 11,
                      color: AppColors.outline,
                    ),
                  ),
                // La rémanence n'est pas décorative : elle bloque la vente.
                if (soin.remanenceJours > 0)
                  Text(
                    'Délai d\'attente ${soin.remanenceJours} j — les sujets ne '
                    'seront pas commercialisables avant.',
                    style: _texte.copyWith(
                      fontSize: 11,
                      color: AppColors.errorDeep,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            label: 'Marquer fait',
            icon: Symbols.check,
            onPressed: enCours ? null : onMarquerFait,
          ),
        ],
      ),
    );
  }
}

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
);

/// Une échéance échue que personne n'a planifiée.
///
/// Le bouton mène à la fiche plutôt que de créer le soin sur place : la
/// planification exige un **type d'action** que le calendrier ne porte pas, et
/// le choisir à la place de l'éleveur reviendrait à inscrire « Vaccination »
/// sur un contrôle d'oxygénation.
class _LigneEcheance extends StatelessWidget {
  const _LigneEcheance({required this.rappel});

  final RappelProphylaxie rappel;

  @override
  Widget build(BuildContext context) {
    final configuration = ConfigurationsEspeces.parIdentifiant[rappel.espece];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: rappel.enRetard
            ? AppColors.errorContainer
            : AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Icon(
            Symbols.event_busy,
            size: 18,
            color: rappel.enRetard ? AppColors.errorDeep : AppColors.outline,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rappel.echeance.traitement,
                  style: _texte.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${configuration?.libelle ?? rappel.espece}'
                  '  ·  bande ${rappel.bande.code}'
                  '  ·  J${rappel.projetee.jourDeCycle}'
                  '  ·  ${Formats.date(rappel.datePrevue)}'
                  '${rappel.enRetard ? "  ·  en retard de ${rappel.joursDeRetard} j" : ""}',
                  style: _texte.copyWith(
                    fontSize: 11,
                    color: rappel.enRetard
                        ? AppColors.errorDeep
                        : AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (configuration != null)
            AppButton(
              label: 'Planifier',
              variant: AppButtonVariant.outline,
              onPressed: () {
                Navigator.of(context).pop();
                context.go(configuration.route);
              },
            ),
        ],
      ),
    );
  }
}
