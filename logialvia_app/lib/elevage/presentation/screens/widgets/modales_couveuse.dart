import '../../../../core/widgets/auteur_courant.dart';
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
import '../../../domain/entities/cycle_incubation.dart';
import '../../../domain/repositories/cycle_couveuse_repository.dart';
import '../../viewmodels/cycle_couveuse_view_model.dart';
import '../../../../core/saisie/formats_saisie.dart';

/// Modale « Déclarer un Nouveau Cycle » — cycle-couveuse.html l.219-261.
Future<Resultat<CycleIncubation>?> afficherModaleCreationCycle(
  BuildContext context,
  CycleCouveuseViewModel vm,
) {
  return AppModal.show<Resultat<CycleIncubation>>(
    context,
    title: 'Déclarer un Nouveau Cycle',
    child: _FormulaireCreation(vm: vm),
  );
}

/// Modale « Modifier le Cycle » — le même formulaire, en modification.
///
/// Écrire un second formulaire aurait garanti que les deux divergent : c'est
/// exactement la même saisie, avec la même date d'éclosion recalculée en
/// direct. Seul le code du cycle n'est pas modifiable — il est la référence
/// portée par le journal d'élevage et les rapports.
Future<Resultat<void>?> afficherModaleEditionCycle(
  BuildContext context,
  CycleCouveuseViewModel vm,
  CycleIncubation cycle,
) {
  return AppModal.show<Resultat<void>>(
    context,
    title: 'Modifier le Cycle — ${cycle.code}',
    child: _FormulaireCreation(vm: vm, cycleAModifier: cycle),
  );
}

class _FormulaireCreation extends StatefulWidget {
  const _FormulaireCreation({required this.vm, this.cycleAModifier});

  final CycleCouveuseViewModel vm;

  /// `null` en création.
  final CycleIncubation? cycleAModifier;

  @override
  State<_FormulaireCreation> createState() => _FormulaireCreationState();
}

class _FormulaireCreationState extends State<_FormulaireCreation> {
  EspeceCouvable? _espece;
  DateTime? _date;
  String? _machineId;
  final _oeufs = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  bool get _enModification => widget.cycleAModifier != null;

  @override
  void initState() {
    super.initState();
    final cycle = widget.cycleAModifier;
    if (cycle != null) {
      _espece = cycle.espece;
      _date = cycle.dateChargement;
      _machineId = cycle.machineId;
      _oeufs.text = '${cycle.oeufsCharges}';
    }
  }

  @override
  void dispose() {
    _oeufs.dispose();
    super.dispose();
  }

  /// `computeEclosionPrevue()` du prototype : la date d'éclosion s'affiche dès
  /// que l'espèce **et** la date sont renseignées — elle n'est jamais saisie.
  DateTime? get _eclosionPrevue {
    if (_espece == null || _date == null) return null;
    return _date!.add(Duration(days: _espece!.dureeIncubationJours));
  }

  /// Premier mirage — J+7. Calculé comme l'éclosion, jamais saisi.
  DateTime? get _mirage1 => _date?.add(
    const Duration(days: EspeceCouvable.jourMirage1),
  );

  /// Second mirage — J+14.
  DateTime? get _mirage2 => _date?.add(
    const Duration(days: EspeceCouvable.jourMirage2),
  );

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final cycle = widget.cycleAModifier;
    final resultat = cycle == null
        ? await widget.vm.creerCycle(
            espece: _espece,
            dateChargement: _date,
            oeufsCharges: int.tryParse(_oeufs.text),
            machineId: _machineId,
          )
        : await widget.vm.modifierCycle(
            cycle: cycle,
            espece: _espece,
            dateChargement: _date,
            oeufsCharges: int.tryParse(_oeufs.text),
            machineId: _machineId,
          );
    if (!mounted) return;

    if (resultat case Echec(:final message)) {
      setState(() {
        _enCours = false;
        _erreur = message;
      });
      return;
    }
    Navigator.of(context).pop(resultat);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Espèce'.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<EspeceCouvable>(
          initialValue: _espece,
          isExpanded: true,
          decoration: _decoration,
          hint: const Text('-- Choisir --', style: _styleChamp),
          items: [
            for (final espece in EspeceCouvable.values)
              DropdownMenuItem(
                value: espece,
                child: Text(
                  '${espece.libelle} (incubation ≈ '
                  '${espece.dureeIncubationJours} jours)',
                  style: _styleChamp,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _espece = v),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Date de Chargement'.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton.icon(
          onPressed: () async {
            final choisie = await showDatePicker(
              context: context,
              initialDate: _date ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(DateTime.now().year + 1, 12, 31),
              locale: const Locale('fr'),
            );
            if (choisie != null) setState(() => _date = choisie);
          },
          icon: const Icon(Symbols.calendar_month, size: 16),
          label: Text(_date == null ? 'Sélectionner…' : Formats.date(_date!)),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(double.infinity, 40),
            foregroundColor: AppColors.onSurface,
            side: const BorderSide(color: AppColors.outlineVariant),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Une incubation en continu suppose plusieurs machines : sans ce
        // champ, `CYCLE_COUVEUSE.machineId` restait vide et le filtre par
        // incubateur ne filtrait rien.
        Text('Incubateur'.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String?>(
          initialValue: _machineId,
          isExpanded: true,
          decoration: _decoration,
          hint: Text(
            widget.vm.machines.isEmpty
                ? '-- aucun incubateur déclaré --'
                : '-- Choisir --',
            style: _styleChamp,
          ),
          items: [
            // « Non précisé » reste possible : un lot peut être suivi sans
            // machine, et l'imposer bloquerait une saisie légitime.
            const DropdownMenuItem<String?>(
              child: Text('Non précisé', style: _styleChamp),
            ),
            for (final machine in widget.vm.machines)
              DropdownMenuItem<String?>(
                value: machine.id,
                child: Text(
                  machine.capaciteOeufs == null
                      ? '${machine.code} — ${machine.libelle}'
                      : '${machine.code} — ${machine.libelle} '
                            '(${machine.capaciteOeufs} œufs)',
                  style: _styleChamp,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _machineId = v),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Nombre d\'Œufs Chargés'.toUpperCase(),
          style: AppTypography.label,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _oeufs,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.entierPositif,
          style: _styleChamp,
          decoration: _decoration.copyWith(hintText: 'Ex. 200'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        _CalendrierPrevisionnel(
          mirage1: _mirage1,
          mirage2: _mirage2,
          eclosion: _eclosionPrevue,
          espece: _espece,
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
              label: _enCours
                  ? 'Enregistrement…'
                  : (_enModification ? 'Enregistrer' : 'Créer le Cycle'),
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }
}

/// Modale « Enregistrer l'Éclosion » — cycle-couveuse.html l.263-290.
/// Modale de mirage — saisie des œufs retirés à J+7 ou à J+14.
///
/// Le mirage est l'opération qui donne son sens au **TER** : c'est là qu'on
/// sort de la machine les œufs clairs (jamais fécondés) puis les œufs gâtés
/// (embryon mort). Le dénominateur de la formule
/// `E(0) − [B(7) + M(14)]` se construit ici, saisie après saisie.
/// Les trois échéances d'un lot, calculées et jamais saisies.
///
/// ## Pourquoi l'éclosion s'affiche en fenêtre
///
/// Une éclosion ne tombe pas au jour dit : la température, l'hygrométrie et
/// l'âge des reproducteurs l'avancent ou la retardent. Annoncer une date au
/// jour près ferait passer une éclosion parfaitement normale à J−1 pour une
/// avance anormale — et pousserait à ouvrir la machine trop tôt.
///
/// La fenêtre est de **deux jours de part et d'autre**
/// ([CycleIncubation.toleranceEclosionJours]), chiffre donné par la Gérante.
/// Les deux mirages, eux, sont des **rendez-vous fixes** : J+7 et J+14. On les
/// affiche à la date exacte, parce que c'est ce jour-là qu'il faut mirer.
class _CalendrierPrevisionnel extends StatelessWidget {
  const _CalendrierPrevisionnel({
    required this.mirage1,
    required this.mirage2,
    required this.eclosion,
    required this.espece,
  });

  final DateTime? mirage1;
  final DateTime? mirage2;
  final DateTime? eclosion;
  final EspeceCouvable? espece;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.brandGold.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.3)),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Symbols.event_available,
                size: 20,
                color: AppColors.brandNavy,
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'CALENDRIER PRÉVISIONNEL (CALCULÉ)',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.outline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (mirage1 == null)
            const Text(
              '— sélectionnez une espèce et une date de chargement —',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.outline,
              ),
            )
          else ...[
            _Echeance(
              jour: 'J+${EspeceCouvable.jourMirage1}',
              libelle: 'Mirage 1 — œufs clairs',
              valeur: Formats.date(mirage1!),
            ),
            _Echeance(
              jour: 'J+${EspeceCouvable.jourMirage2}',
              libelle: 'Mirage 2 — œufs gâtés',
              valeur: Formats.date(mirage2!),
            ),
            if (eclosion != null)
              _Echeance(
                jour: 'J+${espece!.dureeIncubationJours}',
                libelle: 'Éclosion attendue',
                valeur:
                    '${Formats.date(eclosion!.subtract(const Duration(days: CycleIncubation.toleranceEclosionJours)))}'
                    '  ——  '
                    '${Formats.date(eclosion!.add(const Duration(days: CycleIncubation.toleranceEclosionJours)))}',
                accent: true,
                precision: 'Au plus probable le ${Formats.date(eclosion!)} '
                    '— fenêtre de ± ${CycleIncubation.toleranceEclosionJours} jours',
              ),
          ],
        ],
      ),
    );
  }
}

class _Echeance extends StatelessWidget {
  const _Echeance({
    required this.jour,
    required this.libelle,
    required this.valeur,
    this.precision,
    this.accent = false,
  });

  final String jour;
  final String libelle;
  final String valeur;
  final String? precision;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  jour,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandGold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  libelle,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Text(
                valeur,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: accent ? 13 : 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
          if (precision != null)
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Text(
                precision!,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 10,
                  color: AppColors.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<Resultat<void>?> afficherModaleMirage(
  BuildContext context,
  CycleCouveuseViewModel vm,
  CycleIncubation lot,
  int jour,
) {
  final premier = jour == EspeceCouvable.jourMirage1;
  return AppModal.show<Resultat<void>>(
    context,
    title: premier
        ? 'Mirage 1 (J+7) — ${lot.code}'
        : 'Mirage 2 (J+14) — ${lot.code}',
    maxWidth: 480,
    child: _FormulaireMirage(vm: vm, lot: lot, jour: jour),
  );
}

class _FormulaireMirage extends StatefulWidget {
  const _FormulaireMirage({
    required this.vm,
    required this.lot,
    required this.jour,
  });

  final CycleCouveuseViewModel vm;
  final CycleIncubation lot;
  final int jour;

  @override
  State<_FormulaireMirage> createState() => _FormulaireMirageState();
}

class _FormulaireMirageState extends State<_FormulaireMirage> {
  late final TextEditingController _retires = TextEditingController(
    text: (widget.jour == EspeceCouvable.jourMirage1
                ? widget.lot.oeufsBlancsJ7
                : widget.lot.oeufsGatesJ14)
            ?.toString() ??
        '',
  );

  String? _erreur;
  bool _enCours = false;

  bool get _premier => widget.jour == EspeceCouvable.jourMirage1;

  @override
  void dispose() {
    _retires.dispose();
    super.dispose();
  }

  /// Œufs qui resteront en machine après ce mirage — le dénominateur du TER.
  int get _restants {
    final retires = int.tryParse(_retires.text) ?? 0;
    final autre = _premier
        ? (widget.lot.oeufsGatesJ14 ?? 0)
        : (widget.lot.oeufsBlancsJ7 ?? 0);
    return widget.lot.oeufsCharges - autre - retires;
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    final resultat = await widget.vm.enregistrerMirage(
      lot: widget.lot,
      jour: widget.jour,
      oeufsRetires: int.tryParse(_retires.text),
    );
    if (!mounted) return;

    if (resultat is Echec<void>) {
      setState(() {
        _enCours = false;
        _erreur = resultat.message;
      });
      return;
    }
    Navigator.of(context).pop(resultat);
  }

  @override
  Widget build(BuildContext context) {
    final echeance = _premier
        ? widget.lot.dateMirage1
        : widget.lot.dateMirage2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.lot.espece.libelle} · ${widget.lot.oeufsCharges} œufs '
          'chargés le ${Formats.date(widget.lot.dateChargement)} · échéance '
          'le ${Formats.date(echeance)}',
          style: _styleChamp.copyWith(color: AppColors.outline),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          (_premier
                  ? 'Œufs clairs retirés (non fécondés)'
                  : 'Œufs gâtés retirés (embryon mort)')
              .toUpperCase(),
          style: AppTypography.label,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _retires,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.entierPositif,
          autofocus: true,
          style: _styleChamp,
          decoration: _decoration,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceZebra,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Text(
            'Après ce mirage, $_restants œufs resteront en incubation. C\'est '
            'sur eux que le Taux d\'Éclosion Réel sera calculé — pas sur les '
            '${widget.lot.oeufsCharges} œufs de départ, qui contiennent des '
            'œufs jamais fécondés.',
            style: _styleChamp.copyWith(
              fontSize: 11,
              height: 1.4,
              color: AppColors.outline,
            ),
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
              label: _enCours ? 'Enregistrement…' : 'Enregistrer le Mirage',
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }
}

/// Modale d'éclosion — relève des poussins et **remplacement du lot**.
///
/// Sur un couvoir en incubation continue, l'éclosion libère une place dans la
/// machine. La refermer vide serait du rendement perdu : le cahier des charges
/// demande donc qu'un sous-lot puisse être inséré dans la foulée, avec sa
/// propre date d'insertion et son propre calendrier.
Future<Resultat<ResultatEclosion>?> afficherModaleEclosion(
  BuildContext context,
  CycleCouveuseViewModel vm,
  CycleIncubation cycle,
) {
  return AppModal.show<Resultat<ResultatEclosion>>(
    context,
    title: 'Enregistrer l\'Éclosion — ${cycle.code}',
    maxWidth: 560,
    child: _FormulaireEclosion(vm: vm, cycle: cycle),
  );
}

class _FormulaireEclosion extends StatefulWidget {
  const _FormulaireEclosion({required this.vm, required this.cycle});

  final CycleCouveuseViewModel vm;
  final CycleIncubation cycle;

  @override
  State<_FormulaireEclosion> createState() => _FormulaireEclosionState();
}

class _FormulaireEclosionState extends State<_FormulaireEclosion> {
  final _poussins = TextEditingController();
  final _perdus = TextEditingController();
  final _remplacement = TextEditingController();

  bool _remplacer = false;
  late EspeceCouvable _especeRemplacement = widget.cycle.espece;
  DateTime _dateRemplacement = DateTime.now();

  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _poussins.dispose();
    _perdus.dispose();
    _remplacement.dispose();
    super.dispose();
  }

  int get _eclos => int.tryParse(_poussins.text) ?? 0;

  /// **TER** en direct — rapporté aux œufs retenus après les deux mirages,
  /// pas à la quantité de départ.
  double get _ter {
    final retenus = widget.cycle.oeufsRetenusApresMirages;
    if (retenus <= 0) return 0;
    return _eclos / retenus * 100;
  }

  double get _tauxBrut {
    if (widget.cycle.oeufsCharges <= 0) return 0;
    return _eclos / widget.cycle.oeufsCharges * 100;
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    final resultat = await widget.vm.enregistrerEclosion(
      cycle: widget.cycle,
      poussinsEclos: int.tryParse(_poussins.text),
      oeufsPerdus: int.tryParse(_perdus.text),
      oeufsRemplacement: _remplacer ? int.tryParse(_remplacement.text) : null,
      especeRemplacement: _remplacer ? _especeRemplacement : null,
      dateRemplacement: _remplacer ? _dateRemplacement : null,
    );
    if (!mounted) return;

    if (resultat is Echec<ResultatEclosion>) {
      setState(() {
        _enCours = false;
        _erreur = resultat.message;
      });
      return;
    }
    Navigator.of(context).pop(resultat);
  }

  @override
  Widget build(BuildContext context) {
    final lot = widget.cycle;
    final retenus = lot.oeufsRetenusApresMirages;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${lot.espece.libelle} · ${lot.oeufsCharges} œufs chargés le '
            '${Formats.date(lot.dateChargement)}'
            '${lot.machineCode == null ? '' : ' · ${lot.machineCode}'}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _RappelMirages(lot: lot),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Nombre de Poussins Éclos'.toUpperCase(),
            style: AppTypography.label,
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _poussins,
            keyboardType: TextInputType.number,
            inputFormatters: FormatteursSaisie.entierPositif,
            style: _styleChamp,
            decoration: _decoration,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Nombre d\'Œufs Non Éclos / Cassés'.toUpperCase(),
            style: AppTypography.label,
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _perdus,
            keyboardType: TextInputType.number,
            inputFormatters: FormatteursSaisie.entierPositif,
            style: _styleChamp,
            decoration: _decoration,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Taux(
                  libelle: 'Taux d\'Éclosion Réel',
                  valeur: _ter,
                  fond: AppColors.successContainer,
                  texte: AppColors.successDeep,
                  detail: 'sur $retenus œufs retenus',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Taux(
                  libelle: 'Taux Brut',
                  valeur: _tauxBrut,
                  fond: AppColors.surfaceZebra,
                  texte: AppColors.outline,
                  detail: 'sur ${lot.oeufsCharges} œufs chargés',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _BlocRemplacement(
            actif: _remplacer,
            onChange: (v) => setState(() => _remplacer = v),
            controleur: _remplacement,
            espece: _especeRemplacement,
            onEspece: (e) => setState(() => _especeRemplacement = e),
            date: _dateRemplacement,
            onDate: (d) => setState(() => _dateRemplacement = d),
            onSaisie: () => setState(() {}),
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
                label: _enCours
                    ? 'Enregistrement…'
                    : (_remplacer
                          ? 'Enregistrer et Remplacer'
                          : 'Enregistrer l\'Éclosion'),
                onPressed: _enCours ? null : _valider,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rappel des mirages — le dénominateur du TER se lit ici.
class _RappelMirages extends StatelessWidget {
  const _RappelMirages({required this.lot});

  final CycleIncubation lot;

  @override
  Widget build(BuildContext context) {
    final blancs = lot.oeufsBlancsJ7;
    final gates = lot.oeufsGatesJ14;
    final manquant = blancs == null || gates == null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: manquant
            ? AppColors.brandGold.withValues(alpha: 0.1)
            : AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Text(
        manquant
            ? 'Mirages non saisis : ${blancs == null ? 'J+7' : ''}'
                  '${blancs == null && gates == null ? ' et ' : ''}'
                  '${gates == null ? 'J+14' : ''}. Le taux réel sera calculé '
                  'sur les ${lot.oeufsCharges} œufs de départ, donc identique '
                  'au taux brut.'
            : 'Mirages : $blancs œufs clairs (J+7) et $gates œufs gâtés '
                  '(J+14) retirés — ${lot.oeufsRetenusApresMirages} œufs '
                  'restent en incubation.',
        style: _styleChamp.copyWith(
          fontSize: 11,
          height: 1.4,
          color: manquant ? AppColors.brandNavy : AppColors.outline,
        ),
      ),
    );
  }
}

/// Remplacement du lot — création du sous-lot dans la place libérée.
class _BlocRemplacement extends StatelessWidget {
  const _BlocRemplacement({
    required this.actif,
    required this.onChange,
    required this.controleur,
    required this.espece,
    required this.onEspece,
    required this.date,
    required this.onDate,
    required this.onSaisie,
  });

  final bool actif;
  final ValueChanged<bool> onChange;
  final TextEditingController controleur;
  final EspeceCouvable espece;
  final ValueChanged<EspeceCouvable> onEspece;
  final DateTime date;
  final ValueChanged<DateTime> onDate;
  final VoidCallback onSaisie;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: actif,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onChange(v ?? false),
              ),
              Expanded(
                child: Text(
                  'Recharger la machine immédiatement',
                  style: _styleChamp.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: Text(
              'Un sous-lot est créé, rattaché à celui-ci pour la traçabilité, '
              'mais avec son propre calendrier de mirages et d\'éclosion.',
              style: _styleChamp.copyWith(
                fontSize: 11,
                height: 1.4,
                color: AppColors.outline,
              ),
            ),
          ),
          if (actif) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Œufs insérés'.toUpperCase(),
                        style: AppTypography.label,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: controleur,
                        keyboardType: TextInputType.number,
                        inputFormatters: FormatteursSaisie.entierPositif,
                        style: _styleChamp,
                        decoration: _decoration,
                        onChanged: (_) => onSaisie(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Espèce'.toUpperCase(), style: AppTypography.label),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<EspeceCouvable>(
                        initialValue: espece,
                        isExpanded: true,
                        style: _styleChamp,
                        decoration: _decoration,
                        items: [
                          for (final e in EspeceCouvable.values)
                            DropdownMenuItem(
                              value: e,
                              child: Text(
                                '${e.libelle} (${e.dureeIncubationJours} j)',
                                style: _styleChamp,
                              ),
                            ),
                        ],
                        onChanged: (v) => onEspece(v ?? espece),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Date d\'insertion'.toUpperCase(),
              style: AppTypography.label,
            ),
            const SizedBox(height: AppSpacing.xs),
            InkWell(
              onTap: () async {
                final choix = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(date.year - 1),
                  lastDate: DateTime(date.year + 1, 12, 31),
                  locale: const Locale('fr'),
                );
                if (choix != null) onDate(choix);
              },
              child: InputDecorator(
                decoration: _decoration,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(Formats.date(date), style: _styleChamp),
                    ),
                    const Icon(
                      Symbols.calendar_month,
                      size: 18,
                      color: AppColors.outline,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Taux extends StatelessWidget {
  const _Taux({
    required this.libelle,
    required this.valeur,
    required this.fond,
    required this.texte,
    this.detail,
  });

  final String libelle;
  final double valeur;
  final Color fond;
  final Color texte;

  /// Ce sur quoi le taux est rapporte — « sur 85 oeufs retenus ». Sans lui,
  /// deux pourcentages cote a cote n'ont pas de sens comparable.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: fond, borderRadius: AppRadius.cardRadius),
      child: Column(
        children: [
          Text(
            libelle.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.outline,
            ),
          ),
          Text(
            Formats.pourcentage(valeur.clamp(0, 100)),
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: texte,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 10,
                color: AppColors.outline,
              ),
            ),
        ],
      ),
    );
  }
}

const TextStyle _styleChamp = TextStyle(
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
);

/// Modale d'avertissement avant suppression d'un lot d'incubation.
///
/// Un cycle **éclos** n'est jamais proposé à la suppression : ses poussins sont
/// déjà entrés dans les effectifs de la filière et son taux d'éclosion dans les
/// statistiques de la couveuse. L'effacer laisserait des poussins sans origine
/// et fausserait un taux moyen déjà publié.
Future<Resultat<void>?> afficherModaleSuppressionCycle(
  BuildContext context,
  CycleCouveuseViewModel vm,
  CycleIncubation cycle,
) async {
  final confirme = await AppModal.show<bool>(
    context,
    title: 'Supprimer le cycle ${cycle.code} ?',
    maxWidth: 520,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.errorContainer,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color: AppColors.errorDeep.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Symbols.warning,
                size: 20,
                color: AppColors.errorDeep,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Cette action est irréversible.',
                  style: _styleChamp.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.errorDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Les ${cycle.oeufsCharges} œufs de ce lot, chargés le '
          '${Formats.date(cycle.dateChargement)}, disparaîtront du couvoir et '
          'des rapports d\'élevage. L\'éclosion prévue le '
          '${Formats.date(cycle.dateEclosionPrevue)} ne sera plus annoncée sur '
          'le tableau de bord.',
          style: _styleChamp.copyWith(height: 1.5),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Ne supprimez un lot que s\'il a été déclaré par erreur. Un lot '
          'réellement mis en couveuse puis perdu doit être enregistré comme '
          'éclosion avec 0 poussin — la perte reste ainsi visible dans le taux '
          'd\'éclosion moyen, ce qui est le but du suivi.',
          style: _styleChamp.copyWith(
            color: AppColors.outline,
            height: 1.5,
          ),
        ),
      ],
    ),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Annuler',
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
      ),
      Builder(
        builder: (ctx) => AppButton(
          label: 'Supprimer définitivement',
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );

  if (confirme != true) return null;
  // L'auteur est lu APRES la modale : le contexte a survecu a un `await`, il
  // faut donc verifier qu'il est encore monte avant de s'en servir.
  if (!context.mounted) return null;
  return vm.supprimerCycle(cycle, auteur: auteurCourant(context));
}


// ===================================================== Parc d'incubateurs

/// Modale « Ajouter un Incubateur ».
///
/// Une couveuse en incubation continue n'a pas une machine mais un **parc** :
/// c'est ce qui permet à des lots d'âges différents de cohabiter sans se
/// mélanger. `CYCLE_COUVEUSE.machineId` existait depuis v21 et le filtre par
/// machine s'en servait déjà — mais rien, dans l'écran, ne permettait de
/// déclarer une machine. Un référentiel qu'aucun écran n'alimente est un
/// référentiel vide.
Future<Resultat<MachineIncubateur>?> afficherModaleNouvelleMachine(
  BuildContext context,
  CycleCouveuseViewModel vm,
) {
  return AppModal.show<Resultat<MachineIncubateur>>(
    context,
    title: 'Ajouter un Incubateur',
    maxWidth: 420,
    child: _FormulaireMachine(vm: vm),
  );
}

class _FormulaireMachine extends StatefulWidget {
  const _FormulaireMachine({required this.vm});

  final CycleCouveuseViewModel vm;

  @override
  State<_FormulaireMachine> createState() => _FormulaireMachineState();
}

class _FormulaireMachineState extends State<_FormulaireMachine> {
  final _code = TextEditingController();
  final _libelle = TextEditingController();
  final _capacite = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _code.dispose();
    _libelle.dispose();
    _capacite.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.creerMachine(
      code: _code.text,
      libelle: _libelle.text,
      capaciteOeufs: _capacite.text.trim().isEmpty
          ? null
          : int.tryParse(_capacite.text.trim()),
    );
    if (!mounted) return;
    switch (resultat) {
      case Succes<MachineIncubateur>():
        Navigator.of(context).pop(resultat);
      case Echec<MachineIncubateur>(message: final message):
        setState(() {
          _enCours = false;
          _erreur = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('CODE *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _code,
          style: _styleChamp,
          decoration: _decoration.copyWith(hintText: 'Ex. INC-01'),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('LIBELLÉ *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _libelle,
          style: _styleChamp,
          decoration: _decoration.copyWith(
            hintText: 'Ex. Couveuse 528 œufs — atelier',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('CAPACITÉ (ŒUFS)', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _capacite,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.entierPositif,
          style: _styleChamp,
          decoration: _decoration.copyWith(hintText: 'Facultatif'),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          "La capacité sert à signaler une surcharge, jamais à la bloquer : "
          "la Gérante sait ce que sa machine encaisse. Laissée vide, aucune "
          "occupation n'est calculée en pourcentage.",
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 10,
            color: AppColors.outline,
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
              label: _enCours ? 'Enregistrement…' : 'Enregistrer',
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }
}

// ================================================ Historique des remplacements

/// Modale « Historique des Remplacements » — la lignée d'un emplacement.
///
/// Sur un couvoir en rotation, un lot éclos est aussitôt remplacé par un
/// sous-lot qui prend sa place dans la machine. `lotParentId` chaîne ces
/// occupations successives ; la lignée est cette chaîne, du lot racine au
/// dernier sous-lot.
///
/// Le **TER de la lignée** mesure la productivité de l'emplacement sur la
/// durée — ce que le TER d'un lot isolé ne dit pas.
Future<void> afficherModaleLignee(
  BuildContext context,
  CycleCouveuseViewModel vm,
  CycleIncubation lot,
) {
  final racine = vm.racineDe(lot) ?? lot;
  final lignee = vm.lignee(racine.id);
  final ter = vm.terDeLaLignee(racine.id);

  return AppModal.show<void>(
    context,
    title: 'Historique des Remplacements',
    maxWidth: 640,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Lignée du lot ${racine.code} — ${lignee.length} occupation(s) '
          'successive(s) du même emplacement. Chaque sous-lot a ses propres '
          'mirages (M1 à J+7, M2 à J+14), comptés depuis sa propre date '
          'et non celle du lot remplacé.',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < lignee.length; i++)
          _LigneLignee(
            lot: lignee[i],
            rang: i,
            estCourant: lignee[i].id == lot.id,
            reference: vm.reference,
          ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceZebra,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: [
              const Icon(
                Symbols.query_stats,
                size: 18,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  "TER de la lignée — éclos rapportés aux œufs retenus après "
                  "les deux mirages, sur toutes les occupations",
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Text(
                // « — » et non « 0 % » : sans éclosion enregistrée, la lignée
                // n'a pas de taux, elle n'a pas encore produit.
                ter == null ? '—' : Formats.pourcentage(ter),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.successDeep,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Fermer',
              variant: AppButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    ),
  );
}

class _LigneLignee extends StatelessWidget {
  const _LigneLignee({
    required this.lot,
    required this.rang,
    required this.estCourant,
    required this.reference,
  });

  final CycleIncubation lot;
  final int rang;
  final bool estCourant;
  final DateTime reference;

  @override
  Widget build(BuildContext context) {
    final ter = lot.tauxEclosionReel;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: estCourant
            ? AppColors.brandGold.withValues(alpha: 0.12)
            : AppColors.surfaceCard,
        border: Border.all(
          color: estCourant ? AppColors.brandGold : AppColors.outlineVariant,
        ),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${rang + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.outline,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lot.code,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  lot.estSousLot
                      ? 'Remplace ${lot.lotParentCode ?? '—'} · '
                            '${lot.quantiteRemplacee} œufs le '
                            '${Formats.date(lot.dateRemplacement!)}'
                      : 'Lot d\'origine · chargé le '
                            '${Formats.date(lot.dateChargement)}',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${lot.oeufsCharges} œufs',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.onSurface,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lot.estEnCours
                      ? 'J+${lot.ageJours(reference)}'
                      : '${lot.poussinsEclos ?? 0} éclos',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.onSurface,
                  ),
                ),
                // Un sous-lot a SES PROPRES mirages : il entre en machine a
                // une autre date, donc son J+7 et son J+14 ne tombent pas avec
                // ceux du lot qu'il remplace. Les afficher ici est ce qui rend
                // la chaine de remplacements lisible — sans eux, on croirait
                // que la lignee partage un seul calendrier.
                Text(
                  'M1 ${lot.oeufsBlancsJ7 ?? '—'} '
                  '· M2 ${lot.oeufsGatesJ14 ?? '—'}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10,
                    color:
                        lot.oeufsBlancsJ7 == null || lot.oeufsGatesJ14 == null
                        ? AppColors.errorDeep
                        : AppColors.outline,
                  ),
                ),
                Text(
                  '${Formats.date(lot.dateMirage1)} · '
                  '${Formats.date(lot.dateMirage2)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 9,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              ter == null ? '—' : Formats.pourcentage(ter),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ter == null
                    ? AppColors.outline
                    : AppColors.successDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
