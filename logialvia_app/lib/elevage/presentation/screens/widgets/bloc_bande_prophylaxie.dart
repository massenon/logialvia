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
import '../../../domain/entities/bande.dart';
import '../../../domain/entities/configuration_espece.dart';
import '../../../domain/entities/soin.dart';
import '../../viewmodels/fiche_espece_view_model.dart';
import '../../../../core/saisie/formats_saisie.dart';

/// Bandeau « Bande en Cours » de la fiche d'élevage.
///
/// ## Ce qu'il débloque
///
/// `parametres-elevage.html` annonce un calendrier de prophylaxie « injecté
/// dans Traitements & Prophylaxie des fiches journalières », et ce calendrier
/// est indexé sur le **jour du cycle**. Restait à savoir quand le cycle
/// commence : c'est la date de mise en bande, absente de tout le prototype et
/// de Doc D1. Elle se déclare ici.
///
/// Sans bande, aucune date n'est calculable — le bandeau le dit et propose
/// d'en déclarer une, plutôt que de supposer un J1.
class BandeauBande extends StatelessWidget {
  const BandeauBande({
    super.key,
    required this.vm,
    required this.configuration,
  });

  final FicheEspeceViewModel vm;
  final ConfigurationEspece configuration;

  @override
  Widget build(BuildContext context) {
    final bande = vm.bande;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bande == null
            ? AppColors.surfaceCard
            : AppColors.brandGold.withValues(alpha: 0.10),
        border: Border.all(
          color: bande == null ? AppColors.outlineVariant : AppColors.brandGold,
        ),
        borderRadius: AppRadius.cardRadius,
      ),
      child: bande == null
          ? _SansBande(vm: vm, configuration: configuration)
          : _AvecBande(vm: vm, bande: bande, configuration: configuration),
    );
  }
}

class _SansBande extends StatelessWidget {
  const _SansBande({required this.vm, required this.configuration});

  final FicheEspeceViewModel vm;
  final ConfigurationEspece configuration;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Symbols.event_busy, size: 22, color: AppColors.outline),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aucune bande déclarée à cette date',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              Text(
                vm.calendrierSansBande
                    ? 'Le calendrier de prophylaxie de cette filière est '
                          'indexé sur le jour du cycle : sans date de mise en '
                          'place, aucune échéance ne peut être datée.'
                    : 'Déclarez la mise en place pour suivre l\'âge du lot et '
                          'dater les échéances de prophylaxie.',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppButton(
          label: 'Déclarer une Mise en Bande',
          icon: Symbols.add_circle,
          onPressed: () => _declarer(context, vm, configuration),
        ),
      ],
    );
  }
}

class _AvecBande extends StatelessWidget {
  const _AvecBande({
    required this.vm,
    required this.bande,
    required this.configuration,
  });

  final FicheEspeceViewModel vm;
  final Bande bande;
  final ConfigurationEspece configuration;

  @override
  Widget build(BuildContext context) {
    final jour = vm.jourDeCycle ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Symbols.event_available, size: 22, color: AppColors.brandGold),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bande ${bande.code} — mise en place le '
                    '${Formats.date(bande.dateMiseEnBande)}',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandNavy,
                    ),
                  ),
                  Text(
                    [
                      if (bande.effectifInitial != null)
                        '${bande.effectifInitial} sujets mis en place',
                      if (bande.observations != null) bande.observations!,
                    ].join(' · '),
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11,
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ),
            ),
            _Pastille(jour: jour),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'Clôturer la Bande',
              variant: AppButtonVariant.outline,
              onPressed: () => _cloturer(context, vm, bande),
            ),
          ],
        ),
        if (bande.effectifInitial != null) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            // Le dire ici evite qu'un ecart entre les deux chiffres passe pour
            // une erreur de calcul.
            'L\'effectif mis en place est indicatif : l\'effectif réel de la '
            'fiche reste calculé jour après jour depuis les saisies.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: AppColors.outline,
            ),
          ),
        ],
      ],
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.jour});

  final int jour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        'Jour de cycle J$jour',
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Section « Traitements & Prophylaxie » de la saisie journalière —
/// `#day-prophy-multilist` du prototype.
///
/// Elle liste les échéances du calendrier qui tombent **ce jour de cycle**.
/// Chaque ligne peut être transformée en soin planifié : le type d'action est
/// demandé, jamais deviné — `TypeSoin` est une liste fermée et le calendrier
/// ne le porte pas. Une échéance déjà planifiée le dit et ne se reprogramme
/// pas.
class BlocProphylaxieDuJour extends StatelessWidget {
  const BlocProphylaxieDuJour({super.key, required this.vm});

  final FicheEspeceViewModel vm;

  @override
  Widget build(BuildContext context) {
    final bande = vm.bande;
    final echeances = vm.prophylaxieDuJour;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.vaccines,
                size: 18,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  bande == null
                      ? 'Traitements & Prophylaxie'
                      : 'Traitements & Prophylaxie — J${vm.jourDeCycle} du '
                            'cycle de la bande ${bande.code}',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (bande == null)
            const Text(
              'Aucune bande déclarée : les échéances du calendrier ne peuvent '
              'pas être datées.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                color: AppColors.outline,
              ),
            )
          else if (echeances.isEmpty)
            const Text(
              'Aucune échéance de prophylaxie ce jour-là.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                color: AppColors.outline,
              ),
            )
          else
            for (final projetee in echeances)
              _LigneEcheance(vm: vm, projetee: projetee),
        ],
      ),
    );
  }
}

class _LigneEcheance extends StatelessWidget {
  const _LigneEcheance({required this.vm, required this.projetee});

  final FicheEspeceViewModel vm;
  final EcheanceProjetee projetee;

  @override
  Widget build(BuildContext context) {
    final echeance = projetee.echeance;
    final fin = projetee.finRemanence;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            projetee.estEffectue
                ? Symbols.check_circle
                : projetee.estPlanifie
                ? Symbols.schedule
                : Symbols.radio_button_unchecked,
            size: 16,
            color: projetee.estEffectue
                ? AppColors.successDeep
                : projetee.estPlanifie
                ? AppColors.infoBlue
                : AppColors.outline,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${echeance.libelleJour} · ${echeance.traitement}',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  [
                    echeance.produit,
                    if (fin != null)
                      'Délai d\'attente jusqu\'au ${Formats.date(fin)}',
                  ].join(' · '),
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10,
                    color: fin == null ? AppColors.outline : AppColors.errorDeep,
                  ),
                ),
              ],
            ),
          ),
          if (projetee.estEffectue)
            const Text(
              'Effectué',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.successDeep,
              ),
            )
          else if (projetee.estPlanifie)
            const Text(
              'Déjà planifié',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.infoBlue,
              ),
            )
          else
            AppButton(
              label: 'Planifier',
              variant: AppButtonVariant.outline,
              onPressed: () => _planifier(context, vm, projetee),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ modales

Future<void> _declarer(
  BuildContext context,
  FicheEspeceViewModel vm,
  ConfigurationEspece configuration,
) async {
  final code = await vm.prochainCodeBande();
  if (!context.mounted) return;

  final resultat = await AppModal.show<Resultat<Bande>>(
    context,
    title: 'Déclarer une Mise en Bande',
    maxWidth: 460,
    child: _FormulaireBande(
      vm: vm,
      configuration: configuration,
      codeInitial: code,
    ),
  );
  if (resultat == null || !context.mounted) return;
  switch (resultat) {
    case Succes<Bande>(valeur: final bande):
      showAppToast(context, 'Bande ${bande.code} déclarée.');
    case Echec<Bande>(message: final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

class _FormulaireBande extends StatefulWidget {
  const _FormulaireBande({
    required this.vm,
    required this.configuration,
    required this.codeInitial,
  });

  final FicheEspeceViewModel vm;
  final ConfigurationEspece configuration;
  final String codeInitial;

  @override
  State<_FormulaireBande> createState() => _FormulaireBandeState();
}

class _FormulaireBandeState extends State<_FormulaireBande> {
  late final TextEditingController _code = TextEditingController(
    text: widget.codeInitial,
  );
  final _effectif = TextEditingController();
  final _observations = TextEditingController();
  DateTime _date = DateTime.now();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _code.dispose();
    _effectif.dispose();
    _observations.dispose();
    super.dispose();
  }

  /// Jours déjà écoulés si la mise en place est déclarée rétroactivement.
  ///
  /// Une bande déclarée après coup a un cycle déjà entamé : les échéances des
  /// premiers jours sont derrière nous. On l'annonce au lieu de les faire
  /// disparaître — l'application ne peut pas savoir si elles ont été faites.
  int get _joursEcoules {
    final maintenant = DateTime.now();
    final aujourdhui = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    );
    final debut = DateTime(_date.year, _date.month, _date.day);
    if (!debut.isBefore(aujourdhui)) return 0;
    return aujourdhui.difference(debut).inDays;
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.declarerBande(
      code: _code.text,
      dateMiseEnBande: _date,
      effectifInitial: _effectif.text.trim().isEmpty
          ? null
          : int.tryParse(_effectif.text.trim()),
      observations: _observations.text,
    );
    if (!mounted) return;
    switch (resultat) {
      case Succes<Bande>():
        Navigator.of(context).pop(resultat);
      case Echec<Bande>(message: final message):
        setState(() {
          _enCours = false;
          _erreur = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final retroactive = _joursEcoules > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Filière : ${widget.configuration.libelle}',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.brandNavy,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('CODE DE LA BANDE *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _code,
          style: _champ,
          decoration: _decoration,
        ),
        const SizedBox(height: 2),
        const Text(
          'Proposé depuis le préfixe des Paramètres Élevage.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 10,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('DATE DE MISE EN PLACE *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton.icon(
          onPressed: () async {
            final choisie = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2020),
              lastDate: DateTime(DateTime.now().year + 1, 12, 31),
              locale: const Locale('fr'),
            );
            if (choisie != null) setState(() => _date = choisie);
          },
          icon: const Icon(Symbols.calendar_month, size: 16),
          label: Text('${Formats.date(_date)} — J1 du cycle'),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(double.infinity, 44),
            foregroundColor: AppColors.onSurface,
            side: const BorderSide(color: AppColors.outlineVariant),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
          ),
        ),
        if (retroactive) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Mise en place rétroactive : le cycle en est déjà à J'
            '${_joursEcoules + 1}. Les échéances déjà passées '
            's\'afficheront à leur date, à vous de dire si elles ont été '
            'faites.',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 10,
              color: AppColors.errorDeep,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        const Text('EFFECTIF MIS EN PLACE', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _effectif,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.entierPositif,
          style: _champ,
          decoration: _decoration.copyWith(hintText: 'Facultatif'),
        ),
        const SizedBox(height: 2),
        const Text(
          'Indicatif : l\'effectif de la fiche reste calculé depuis les '
          'saisies journalières.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 10,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('OBSERVATIONS', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _observations,
          style: _champ,
          decoration: _decoration.copyWith(
            hintText: 'Ex. Enclos E2, souche locale',
          ),
        ),
        if (_erreur != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_erreur!, style: AppTypography.invalidFeedback),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: _enCours ? 'Enregistrement…' : 'Déclarer',
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _cloturer(
  BuildContext context,
  FicheEspeceViewModel vm,
  Bande bande,
) async {
  final confirme = await AppModal.show<bool>(
    context,
    title: 'Clôturer la Bande ?',
    maxWidth: 400,
    child: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Bande ${bande.code}, mise en place le '
            '${Formats.date(bande.dateMiseEnBande)}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Le cycle s\'arrête à aujourd\'hui : plus aucune échéance de '
            'prophylaxie ne sera datée pour cette bande. Les saisies '
            'journalières et l\'effectif ne changent pas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppButton(
                label: 'Annuler',
                variant: AppButtonVariant.outline,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Clôturer',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  if (confirme != true || !context.mounted) return;
  final resultat = await vm.cloturerBande(DateTime.now());
  if (!context.mounted) return;
  switch (resultat) {
    case Succes<void>():
      showAppToast(context, 'Bande ${bande.code} clôturée.');
    case Echec<void>(message: final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

Future<void> _planifier(
  BuildContext context,
  FicheEspeceViewModel vm,
  EcheanceProjetee projetee,
) async {
  final type = await AppModal.show<String>(
    context,
    title: 'Planifier ce Soin',
    maxWidth: 420,
    child: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${projetee.echeance.traitement} — ${projetee.echeance.produit}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
          Text(
            'Prévu le ${Formats.date(projetee.datePrevue)} '
            '(${projetee.echeance.libelleJour} du cycle)',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            // Le calendrier de prophylaxie ne porte pas le type d'action, et
            // `TypeSoin` est une liste fermee : le deduire du libelle
            // marcherait sur « Vaccin Newcastle » et se tromperait sur
            // « Controle Oxygenation ».
            'Type d\'action — le calendrier ne le précise pas :',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final type in TypeSoin.tous)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: AppButton(
                label: type,
                variant: AppButtonVariant.outline,
                onPressed: () => Navigator.of(ctx).pop(type),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Annuler',
                variant: AppButtonVariant.outline,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  if (type == null || !context.mounted) return;
  final resultat = await vm.planifierEcheance(
    projetee: projetee,
    typeSoin: type,
  );
  if (!context.mounted) return;
  switch (resultat) {
    case Succes<Soin>():
      showAppToast(
        context,
        'Soin planifié au ${Formats.date(projetee.datePrevue)} — visible dans '
        'le Calendrier de Soins.',
      );
    case Echec<Soin>(message: final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

const TextStyle _champ = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 14,
  color: AppColors.onSurface,
);

final InputDecoration _decoration = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: AppColors.surfaceCard,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  ),
  border: OutlineInputBorder(
    borderRadius: AppRadius.cardRadius,
    borderSide: const BorderSide(color: AppColors.outlineVariant),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: AppRadius.cardRadius,
    borderSide: const BorderSide(color: AppColors.outlineVariant),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: AppRadius.cardRadius,
    borderSide: const BorderSide(color: AppColors.brandGold),
  ),
);
