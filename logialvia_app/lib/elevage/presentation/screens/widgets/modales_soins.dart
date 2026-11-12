import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../domain/entities/configuration_espece.dart';
import '../../../domain/entities/soin.dart';
import '../../viewmodels/soins_view_model.dart';
import '../../../../core/saisie/formats_saisie.dart';

/// Modale « Nouveau Soin » — soins-calendrier.html l.260-298, 9 champs.
Future<Resultat<Soin>?> afficherModaleNouveauSoin(
  BuildContext context,
  SoinsViewModel vm,
) {
  return AppModal.show<Resultat<Soin>>(
    context,
    title: 'Nouveau Soin',
    maxWidth: 560, // `max-w-lg`
    child: _FormulaireSoin(vm: vm),
  );
}

class _FormulaireSoin extends StatefulWidget {
  const _FormulaireSoin({required this.vm});

  final SoinsViewModel vm;

  @override
  State<_FormulaireSoin> createState() => _FormulaireSoinState();
}

class _FormulaireSoinState extends State<_FormulaireSoin> {
  String? _espece;
  DateTime _date = DateTime.now();
  String? _type;
  final _produit = TextEditingController();
  final _dose = TextEditingController();
  final _remanence = TextEditingController(text: '0');
  final _veterinaire = TextEditingController();
  final _symptomes = TextEditingController();
  final _cout = TextEditingController();
  bool _dejaEffectue = false;
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _produit.dispose();
    _dose.dispose();
    _remanence.dispose();
    _veterinaire.dispose();
    _symptomes.dispose();
    _cout.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.enregistrerSoin(
      espece: _espece,
      date: _date,
      typeSoin: _type,
      produit: _produit.text.isEmpty ? null : _produit.text,
      dose: _dose.text.isEmpty ? null : _dose.text,
      remanenceJours: int.tryParse(_remanence.text) ?? 0,
      veterinaire: _veterinaire.text.isEmpty ? null : _veterinaire.text,
      symptomes: _symptomes.text.isEmpty ? null : _symptomes.text,
      coutFcfa: int.tryParse(_cout.text) ?? 0,
      dejaEffectue: _dejaEffectue,
    );
    if (!mounted) return;

    if (resultat is Echec<Soin>) {
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
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          champDeroulant(
            libelle: 'Lot / Bande *',
            valeur: _espece,
            options: {
              for (final config
                  in ConfigurationsEspeces.parIdentifiant.values.toSet())
                config.identifiant: config.libelle,
            },
            onChange: (v) => setState(() => _espece = v),
          ),
          const SizedBox(height: AppSpacing.md),
          champDate(
            context: context,
            libelle: 'Date du Soin *',
            date: _date,
            onChange: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: AppSpacing.md),
          champDeroulant(
            libelle: 'Type d\'Action *',
            valeur: _type,
            options: {for (final t in TypeSoin.tous) t: t},
            onChange: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: champTexte(
                  libelle: 'Produit Utilisé',
                  controleur: _produit,
                  indication: 'ex : Antcox',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: champTexte(
                  libelle: 'Dose',
                  controleur: _dose,
                  indication: 'ex : 1C/20L d\'eau',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          champTexte(
            libelle: 'Délai d\'Attente / Rémanence (jours)',
            controleur: _remanence,
            clavier: TextInputType.number,
            formatteurs: FormatteursSaisie.entierPositif,
            couleurLibelle: AppColors.errorDeep,
          ),
          const SizedBox(height: AppSpacing.md),
          champTexte(
            libelle: 'Vétérinaire / Animalier',
            controleur: _veterinaire,
            indication: 'ex : SIDI ALI Raïmatou',
          ),
          const SizedBox(height: AppSpacing.md),
          champTexte(
            libelle: 'Symptômes observés',
            controleur: _symptomes,
            lignes: 2,
          ),
          const SizedBox(height: AppSpacing.md),
          champTexte(
            libelle: 'Coût (FCFA)',
            controleur: _cout,
            clavier: TextInputType.number,
            formatteurs: FormatteursSaisie.montant,
            indication: '0',
          ),
          const SizedBox(height: AppSpacing.sm),
          // AJOUT : le prototype cree toujours un soin sans distinguer
          // « deja administre » de « planifie », alors que l'ecran affiche les
          // deux statuts. Sans ce choix, aucun soin ne pourrait jamais etre
          // enregistre comme deja effectue.
          Row(
            children: [
              Checkbox(
                value: _dejaEffectue,
                activeColor: AppColors.brandNavy,
                onChanged: (v) => setState(() => _dejaEffectue = v ?? false),
              ),
              const Expanded(
                child: Text(
                  'Soin déjà administré (sinon il sera enregistré comme planifié)',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
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
      ),
    );
  }
}

/// Modale « Planifier une Intervention » — `soins-calendrier.html` l.361-387.
///
/// Ouverte depuis l'onglet **Calendrier Vétérinaire**, elle n'est pas un
/// doublon de « Nouveau Soin » malgré la parenté des champs : celle-là consigne
/// un soin **administré ou à administrer**, avec produit, dose, rémanence,
/// vétérinaire, symptômes et coût ; celle-ci pose une **échéance** dans le
/// planning, en trois champs.
///
/// ⚠️ Côté web, les deux n'écrivent pas au même endroit : `confirmNouveauSoin()`
/// alimente le registre, `submitPlanifierIntervention()` écrit dans
/// `GANTT_LOTS[].interventions`, une structure parallèle en mémoire. D'où deux
/// plannings qui ne se voient pas l'un l'autre. Ici les deux modales écrivent
/// dans `SOINS_CALENDRIER` ; le Gantt lit cette table, donc une intervention
/// planifiée apparaît aussitôt dans le registre et réciproquement.
///
/// Le statut est toujours « Planifié » : on ne planifie pas quelque chose de
/// déjà fait. La case « soin déjà administré » de l'autre modale n'a donc pas
/// d'équivalent ici.
Future<Resultat<Soin>?> afficherModalePlanifierIntervention(
  BuildContext context,
  SoinsViewModel vm,
) {
  return AppModal.show<Resultat<Soin>>(
    context,
    title: 'Planifier une Intervention',
    maxWidth: 480, // `max-w-md`
    child: _FormulaireIntervention(vm: vm),
  );
}

class _FormulaireIntervention extends StatefulWidget {
  const _FormulaireIntervention({required this.vm});

  final SoinsViewModel vm;

  @override
  State<_FormulaireIntervention> createState() =>
      _FormulaireInterventionState();
}

class _FormulaireInterventionState extends State<_FormulaireIntervention> {
  String? _espece;
  final _intervention = TextEditingController();
  DateTime _date = DateTime.now();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _intervention.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final libelle = _intervention.text.trim();
    if (libelle.isEmpty) {
      setState(() => _erreur = 'L\'intervention est obligatoire.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    final resultat = await widget.vm.enregistrerSoin(
      espece: _espece,
      date: _date,
      // Le prototype laisse le libellé libre (« ex : Vaccin Newcastle
      // (Rappel) ») : une échéance de planning n'entre pas toujours dans les
      // 4 types d'action du registre. Il est repris tel quel.
      typeSoin: libelle,
      dejaEffectue: false,
    );
    if (!mounted) return;

    if (resultat is Echec<Soin>) {
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        champDeroulant(
          libelle: 'Lot / Bande *',
          valeur: _espece,
          options: {
            for (final config
                in ConfigurationsEspeces.parIdentifiant.values.toSet())
              config.identifiant: config.libelle,
          },
          onChange: (v) => setState(() => _espece = v),
        ),
        const SizedBox(height: AppSpacing.md),
        champTexte(
          libelle: 'Intervention *',
          controleur: _intervention,
          indication: 'ex : Vaccin Newcastle (Rappel)',
        ),
        const SizedBox(height: AppSpacing.md),
        champDate(
          context: context,
          libelle: 'Date Prévue',
          date: _date,
          onChange: (d) => setState(() => _date = d),
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
              label: _enCours ? 'Planification…' : 'Planifier',
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }
}

/// Modale « Nouvelle Entrée Infirmerie » — l.300-319.
Future<Resultat<EntreeInfirmerie>?> afficherModaleEntreeInfirmerie(
  BuildContext context,
  SoinsViewModel vm,
) {
  return AppModal.show<Resultat<EntreeInfirmerie>>(
    context,
    title: 'Nouvelle Entrée Infirmerie',
    maxWidth: 384, // `max-w-sm`
    child: _FormulaireInfirmerie(vm: vm),
  );
}

class _FormulaireInfirmerie extends StatefulWidget {
  const _FormulaireInfirmerie({required this.vm});

  final SoinsViewModel vm;

  @override
  State<_FormulaireInfirmerie> createState() => _FormulaireInfirmerieState();
}

class _FormulaireInfirmerieState extends State<_FormulaireInfirmerie> {
  final _sujet = TextEditingController();
  final _motif = TextEditingController();
  String _isolement = NiveauIsolement.surveillance;
  String? _espece;
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _sujet.dispose();
    _motif.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.enregistrerEntreeInfirmerie(
      sujet: _sujet.text,
      motif: _motif.text,
      niveauIsolement: _isolement,
      espece: _espece,
    );
    if (!mounted) return;

    if (resultat is Echec<EntreeInfirmerie>) {
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        champTexte(
          libelle: 'Lot / Sujet',
          controleur: _sujet,
          indication: 'Ex. Goliath #G-014',
        ),
        const SizedBox(height: AppSpacing.md),
        champTexte(
          libelle: 'Motif',
          controleur: _motif,
          indication: 'Ex. Suspicion Newcastle',
        ),
        const SizedBox(height: AppSpacing.md),
        champDeroulant(
          libelle: 'Niveau d\'Isolement',
          valeur: _isolement,
          options: {for (final n in NiveauIsolement.tous) n: n},
          onChange: (v) =>
              setState(() => _isolement = v ?? NiveauIsolement.surveillance),
        ),
        const SizedBox(height: AppSpacing.md),
        // AJOUT : le prototype ne relie l'entree a aucune espece, ce qui rend
        // impossible la repercussion d'un deces sur la fiche d'elevage qu'il
        // annonce pourtant (l.326). Champ optionnel, pour que l'information
        // existe au moins en base.
        champDeroulant(
          libelle: 'Filière concernée (facultatif)',
          valeur: _espece,
          options: {
            for (final config
                in ConfigurationsEspeces.parIdentifiant.values.toSet())
              config.identifiant: config.libelle,
          },
          onChange: (v) => setState(() => _espece = v),
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

/// Ce que l'utilisateur a repondu a la modale « Declarer le Deces ? ».
class ChoixDeces {
  const ChoixDeces(this.indexCategorie);

  /// Index, dans `ConfigurationEspece.categories`, de la categorie ou porter
  /// la perte. `null` quand l'utilisateur declare l'avoir deja saisie sur la
  /// fiche : la fiche reste alors inchangee.
  final int? indexCategorie;
}

/// Modale « Déclarer le Décès ? » — l.321-332.
///
/// ## Pourquoi elle pose une question de plus que le prototype
///
/// Le prototype annonce que le décès « sera reflété dans le décompte de
/// mortalité de la fiche d'élevage correspondante » (l.326) — répercussion qui
/// n'existe nulle part dans son code. Elle existe désormais ici.
///
/// Mais une fiche d'élevage compte les morts **par catégorie d'effectif**, et
/// une entrée d'infirmerie ne dit pas de quelle catégorie relève le sujet.
/// L'information manque : la modale la demande, plutôt que de la deviner. Le
/// bouton reste inactif tant qu'aucune réponse n'est donnée — y compris
/// « déjà saisie », qui est une réponse à part entière.
///
/// Retourne `null` si l'utilisateur annule.
Future<ChoixDeces?> afficherModaleConfirmationDeces(
  BuildContext context,
  EntreeInfirmerie entree,
) {
  return AppModal.show<ChoixDeces>(
    context,
    title: 'Déclarer le Décès ?',
    maxWidth: 384,
    child: _ContenuConfirmationDeces(entree: entree),
  );
}

class _ContenuConfirmationDeces extends StatefulWidget {
  const _ContenuConfirmationDeces({required this.entree});

  final EntreeInfirmerie entree;

  @override
  State<_ContenuConfirmationDeces> createState() =>
      _ContenuConfirmationDecesState();
}

class _ContenuConfirmationDecesState extends State<_ContenuConfirmationDeces> {
  /// Valeur du menu : l'index de categorie en texte, ou [_dejaSaisie].
  String? _choix;

  static const String _dejaSaisie = 'deja-saisie';

  ConfigurationEspece? get _configuration =>
      ConfigurationsEspeces.parIdentifiant[widget.entree.espece];

  @override
  Widget build(BuildContext context) {
    final configuration = _configuration;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Symbols.heart_broken, size: 48, color: AppColors.errorDeep),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.entree.sujet,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          "Cette action clôture l'entrée d'infirmerie.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (configuration == null)
          const Text(
            "Aucune filière n'est rattachée à cette entrée : la perte ne peut "
            "être portée sur aucune fiche. Saisissez-la vous-même sur la fiche "
            "concernée.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppColors.outline,
            ),
          )
        else ...[
          champDeroulant(
            libelle: 'Mortalité à porter sur la fiche ${configuration.libelle}',
            valeur: _choix,
            options: {
              for (var i = 0; i < configuration.categories.length; i++)
                '$i': configuration.categories[i].libelle,
              _dejaSaisie: 'Déjà saisie sur la fiche — ne rien ajouter',
            },
            onChange: (v) => setState(() => _choix = v),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            "L'effectif de la catégorie choisie est décrémenté, et les jours "
            "suivants déjà saisis sont recalculés.",
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 10,
              color: AppColors.outline,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'Confirmer le Décès',
              variant: AppButtonVariant.danger,
              // Sans filiere rattachee, il n'y a rien a demander : le bouton
              // reste actif. Avec une filiere, la reponse est obligatoire —
              // deviner la categorie fausserait un effectif.
              onPressed: configuration != null && _choix == null
                  ? null
                  : () => Navigator.of(context).pop(
                      ChoixDeces(
                        _choix == null || _choix == _dejaSaisie
                            ? null
                            : int.parse(_choix!),
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

Widget champTexte({
  required String libelle,
  required TextEditingController controleur,
  String? indication,
  TextInputType? clavier,
    List<TextInputFormatter>? formatteurs,
  int lignes = 1,
  Color? couleurLibelle,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        libelle.toUpperCase(),
        style: AppTypography.label.copyWith(color: couleurLibelle),
      ),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: controleur,
        keyboardType: clavier,
        inputFormatters: formatteurs,
        maxLines: lignes,
        style: _styleChamp,
        decoration: _decoration.copyWith(hintText: indication),
      ),
    ],
  );
}

Widget champDeroulant({
  required String libelle,
  required String? valeur,
  required Map<String, String> options,
  required ValueChanged<String?> onChange,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(libelle.toUpperCase(), style: AppTypography.label),
      const SizedBox(height: AppSpacing.xs),
      DropdownButtonFormField<String>(
        initialValue: valeur,
        isExpanded: true,
        decoration: _decoration,
        hint: const Text('-- Sélectionner --', style: _styleChamp),
        items: [
          for (final entree in options.entries)
            DropdownMenuItem(
              value: entree.key,
              child: Text(entree.value, style: _styleChamp),
            ),
        ],
        onChanged: onChange,
      ),
    ],
  );
}

Widget champDate({
  required BuildContext context,
  required String libelle,
  required DateTime date,
  required ValueChanged<DateTime> onChange,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(libelle.toUpperCase(), style: AppTypography.label),
      const SizedBox(height: AppSpacing.xs),
      OutlinedButton.icon(
        onPressed: () async {
          final choisie = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2020),
            lastDate: DateTime(DateTime.now().year + 2, 12, 31),
            locale: const Locale('fr'),
          );
          if (choisie != null) onChange(choisie);
        },
        icon: const Icon(Symbols.calendar_month, size: 16),
        label: Text(Formats.date(date)),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(double.infinity, 44),
          foregroundColor: AppColors.onSurface,
          side: const BorderSide(color: AppColors.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        ),
      ),
    ],
  );
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
