import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/widgets/champ_saisie_nombre.dart';
import '../../../core/widgets/icone_symbole.dart';
import '../../../core/tour/tour_guide.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../domain/entities/configuration_espece.dart';
import '../../domain/entities/journee_elevage.dart';
import '../../domain/services/calcul_fiche_journaliere.dart';
import '../../domain/services/controle_vraisemblance.dart';
import '../../domain/services/reperes_zootechniques.dart';
import '../viewmodels/fiche_espece_view_model.dart';
import 'widgets/compteur_categorie.dart';
import 'widgets/suivi_stock_oeufs.dart';
import 'widgets/tableau_hebdomadaire.dart';
import 'widgets/bandeaux_expert.dart';
import 'widgets/bloc_bande_prophylaxie.dart';
import 'widgets/tableau_mensuel.dart';
import '../../../core/saisie/formats_saisie.dart';

/// **Écran unique des 5 fiches d'élevage**, paramétré par [ConfigurationEspece].
///
/// Strict Avoid §5 et §15 l'exigent explicitement : les 5 fiches doivent
/// partager un seul patron paramétré, jamais 5 implémentations qui divergeront
/// au fil du temps. Ajouter une 6ᵉ espèce est une question de configuration.
///
/// Ordre des sections, fidèle à `fiche-goliaths.html` (Doc F3) :
/// en-tête → rappel du cycle → 4 KPI → saisie journalière → tableau mensuel.
class FicheEspeceScreen extends StatefulWidget {
  const FicheEspeceScreen({super.key, required this.configuration});

  final ConfigurationEspece configuration;

  @override
  State<FicheEspeceScreen> createState() => _FicheEspeceScreenState();
}

class _FicheEspeceScreenState extends State<FicheEspeceScreen> {
  /// `switchDensityView()` — bascule Grille Quotidienne / Vue Hebdomadaire.
  /// Purement local : c'est une densite d'affichage, elle n'a rien a persister.
  bool _hebdomadaire = false;

  ConfigurationEspece get configuration => widget.configuration;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FicheEspeceViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EnTete(configuration: configuration, vm: vm),
          const SizedBox(height: AppSpacing.lg),
          _RappelCycle(etapes: configuration.etapesCycle),
          const SizedBox(height: AppSpacing.lg),
          // La mise en bande donne son J1 au cycle : c'est elle qui date les
          // echeances de prophylaxie, indexees sur le jour du cycle.
          BandeauBande(vm: vm, configuration: configuration),
          const SizedBox(height: AppSpacing.lg),
          // Fiche modifiee ailleurs, chaine incoherente, bande a recoder (`47e_`).
          BandeauxExpert(vm: vm),
          _BandeauKpiFiche(vm: vm, configuration: configuration),
          const SizedBox(height: AppSpacing.lg),
          FormulaireJournalier(
            key: ValueKey(
              '${configuration.identifiant}-${vm.jourActif.toIso8601String()}',
            ),
            vm: vm,
            configuration: configuration,
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Historique du Mois — ${_libelleMois(vm.jourActif)}',
            // `fiche-goliaths.html` l.372-377 : la bascule est posee a droite
            // du titre de la section, dans une pilule.
            action: CibleTour(
              nom: 'bascule-hebdomadaire',
              child: BasculeDensite(
                hebdomadaire: _hebdomadaire,
                onChange: (v) => setState(() => _hebdomadaire = v),
              ),
            ),
            child: _hebdomadaire
                ? TableauHebdomadaire(
                    nombreJours: vm.nombreJoursDuMois,
                    journees: vm.journeesDuMois,
                    moisAffiche: vm.jourActif,
                    effectifInitial: vm.effectifReportMois,
                    libelleNaissances: configuration.libelleNaissances,
                  )
                : TableauMensuel(
                    nombreJours: vm.nombreJoursDuMois,
                    journees: vm.journeesDuMois,
                    jourActif: vm.jourActif.day,
                    moisAffiche: vm.jourActif,
                    onSelectionner: (jour) => vm.changerJour(
                      DateTime(vm.jourActif.year, vm.jourActif.month, jour),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _libelleMois(DateTime date) {
    const mois = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    return '${mois[date.month - 1]} ${date.year}';
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.configuration, required this.vm});

  final ConfigurationEspece configuration;
  final FicheEspeceViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          IconeSymbole.depuisNom(configuration.icone),
          size: 24,
          color: AppColors.brandNavy,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Fiche ${configuration.libelle}',
            style: AppTypography.pageTitle,
          ),
        ),
        const Text(
          'Jour actif :',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () async {
            // ECART_DELIBERE : `<input type="date">` n'a pas d'equivalent
            // Flutter natif — `showDatePicker`, meme intention (A1 §3.3).
            final choisie = await showDatePicker(
              context: context,
              initialDate: vm.jourActif,
              firstDate: DateTime(2020),
              lastDate: DateTime(DateTime.now().year + 1, 12, 31),
              locale: const Locale('fr'),
            );
            if (choisie != null) await vm.changerJour(choisie);
          },
          icon: const Icon(Symbols.calendar_month, size: 16),
          label: Text(Formats.date(vm.jourActif)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandNavy,
            side: const BorderSide(color: AppColors.outlineVariant),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
          ),
        ),
      ],
    );
  }
}

/// Bandeau « Rappel du Cycle » — fiche-goliaths.html l.105-113.
class _RappelCycle extends StatelessWidget {
  const _RappelCycle({required this.etapes});

  final List<String> etapes;

  @override
  Widget build(BuildContext context) {
    // Couleurs des pastilles, dans l'ordre du prototype : navy plein, or
    // translucide, puis vert de confirmation pour l'etape commercialisable.
    const fonds = [
      AppColors.brandNavy,
      Color(0x4DB58B2A),
      AppColors.successContainer,
    ];
    const textes = [Colors.white, AppColors.brandNavy, AppColors.successDeep];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(
            Symbols.event_repeat,
            size: 20,
            color: AppColors.brandNavy,
          ),
          const Text(
            'Rappel du Cycle :',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
          for (var i = 0; i < etapes.length; i++) ...[
            if (i > 0)
              const Icon(
                Symbols.arrow_forward,
                size: 15,
                color: AppColors.outline,
              ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: fonds[i % fonds.length],
                borderRadius: AppRadius.pill,
              ),
              child: Text(
                etapes[i],
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: textes[i % textes.length],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BandeauKpiFiche extends StatelessWidget {
  const _BandeauKpiFiche({required this.vm, required this.configuration});

  final FicheEspeceViewModel vm;
  final ConfigurationEspece configuration;

  @override
  Widget build(BuildContext context) {
    final libelleMature = configuration.categories.length > 2
        ? configuration.categories[2].libelle
        : 'Matures';
    final libelleImmature = configuration.categories.length > 1
        ? configuration.categories[1].libelle
        : 'Immatures';

    final cartes = [
      KpiCard(
        libelle: 'Effectif Vivant',
        valeur: '${vm.effectifVivant}',
        accent: AppColors.brandNavy,
        icone: Symbols.pets,
        detail: vm.aDesDonnees ? null : 'Aucune journée saisie ce mois-ci',
      ),
      KpiCard(
        libelle: '$libelleMature (Éligibles Vente)',
        valeur: '${vm.effectifMatures}',
        accent: AppColors.successDeep,
        icone: Symbols.verified,
      ),
      KpiCard(
        libelle: '$libelleImmature (Immatures)',
        valeur: '${vm.effectifImmatures}',
        accent: AppColors.brandGold,
        icone: Symbols.child_care,
      ),
      KpiCard(
        libelle: 'Taux de Mortalité (Cumul)',
        valeur: Formats.pourcentage(vm.tauxMortaliteCumul),
        // DV-13 : 10 % avertissement, 20 % critique (`47e_`).
        accent: switch (vm.niveauMortaliteCumul) {
          NiveauAlerte.critique => AppColors.errorDeep,
          NiveauAlerte.avertissement => AppColors.brandGold,
          NiveauAlerte.normal => AppColors.successDeep,
        },
        icone: Symbols.trending_down,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // `grid-cols-2 md:grid-cols-4` sur cet ecran (fiche-goliaths.html l.115).
        final largeur = (constraints.maxWidth - AppSpacing.md * 3) / 4;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final carte in cartes) SizedBox(width: largeur, child: carte),
          ],
        );
      },
    );
  }
}

/// Formulaire de saisie journalière — Doc F3 §2.
class FormulaireJournalier extends StatefulWidget {
  const FormulaireJournalier({
    super.key,
    required this.vm,
    required this.configuration,
  });

  final FicheEspeceViewModel vm;
  final ConfigurationEspece configuration;

  @override
  State<FormulaireJournalier> createState() => _FormulaireJournalierState();
}

class _FormulaireJournalierState extends State<FormulaireJournalier> {
  late int _achat;
  late int _ne;
  late List<int> _morts;
  late List<int> _dons;
  late final TextEditingController _poids;
  late final TextEditingController _observation;
  late bool _traitementValide;
  bool _enregistrement = false;

  // Suivi du stock d'œufs — Pondeuses uniquement (Doc H2).
  late int _oeufsPondus;
  late int _oeufsCasses;
  late int _sortiesPlateaux;

  bool get _suitLeStockOeufs => widget.configuration.identifiant == 'pondeuses';

  SaisieStockOeufs? get _saisieOeufs => _suitLeStockOeufs
      ? SaisieStockOeufs(
          oeufsPondus: _oeufsPondus,
          oeufsCasses: _oeufsCasses,
          sortiesPlateaux: _sortiesPlateaux,
        )
      : null;

  @override
  void initState() {
    super.initState();
    final journee = widget.vm.journeeActive;
    _achat = journee.achat;
    _ne = journee.ne;
    _morts = List<int>.from(journee.mortsParCategorie);
    _dons = List<int>.from(journee.donsParCategorie);
    _poids = TextEditingController(
      text: journee.poidsGeneralG?.toString() ?? '',
    );
    _observation = TextEditingController(text: journee.traitementObs ?? '');
    _traitementValide = journee.traitementValide;
    _oeufsPondus = journee.oeufsPondus ?? 0;
    _oeufsCasses = journee.oeufsCasses ?? 0;
    _sortiesPlateaux = journee.sortiesPlateaux ?? 0;
  }

  @override
  void dispose() {
    _poids.dispose();
    _observation.dispose();
    super.dispose();
  }

  MouvementsJour get _mouvements => MouvementsJour(
    achat: _achat,
    ne: _ne,
    // Le champ Ventes est alimenté par le POS, jamais saisi ici — `readonly`
    // dans le prototype (fiche-goliaths.html l.159).
    vente: widget.vm.venteDuJour,
    mortsParCategorie: _morts,
    donsParCategorie: _dons,
  );

  Future<void> _enregistrer() async {
    setState(() => _enregistrement = true);
    final resultat = await widget.vm.enregistrer(
      mouvements: _mouvements,
      poidsGeneralG: int.tryParse(_poids.text),
      traitementObs: _observation.text.isEmpty ? null : _observation.text,
      traitementValide: _traitementValide,
      stockOeufs: _saisieOeufs,
    );
    if (!mounted) return;
    setState(() => _enregistrement = false);

    switch (resultat) {
      case Succes<JourneeElevage>():
        showAppToast(
          context,
          'Saisie du jour ${widget.vm.jourActif.day} enregistrée avec succès.',
        );
      case Echec<JourneeElevage>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectifs = widget.vm.calculerEnDirect(_mouvements);
    final provende = widget.vm.provendeDuJour(
      effectifs.parCategorie,
      poidsTotalGrammes: int.tryParse(_poids.text),
    );
    final provendeG = provende.grammes;

    return CarteSection(
      titre: 'Saisie Journalière — ${Formats.date(widget.vm.jourActif)}',
      cibleTour: 'saisie-journaliere',
      icone: Symbols.edit_note,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Les trois colonnes partagent le meme champ : le prototype leur
              // donne la meme classe CSS, seule la lecture seule differe.
              // Les libelles viennent de la configuration de l'espece, pas de
              // l'ecran — chaque filiere a son vocabulaire (voir le glossaire
              // de `ConfigurationEspece`).
              Expanded(
                child: ChampSaisieNombre(
                  libelle: widget.configuration.libelleAchats,
                  valeur: _achat,
                  onChange: (v) => setState(() => _achat = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ChampSaisieNombre(
                  libelle: widget.configuration.libelleNaissances,
                  valeur: _ne,
                  onChange: (v) => setState(() => _ne = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ChampSaisieNombre(
                  libelle: 'Ventes',
                  // `<span class="text-outline font-normal text-[9px]">(POS)`
                  // — dans le libelle, pas en note sous le champ : la note
                  // decalait cette colonne par rapport aux deux autres.
                  suffixeLibelle: '(POS)',
                  valeur: widget.vm.venteDuJour,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _BlocCategories(
            titre: 'Morts par catégorie',
            icone: Symbols.skull,
            couleurFond: AppColors.errorContainer,
            couleurTexte: AppColors.errorDeep,
            configuration: widget.configuration,
            valeurs: _morts,
            onChange: (i, v) => setState(() => _morts[i] = v),
          ),
          const SizedBox(height: AppSpacing.md),
          _BlocCategories(
            titre: 'Dons par catégorie',
            icone: Symbols.redeem,
            couleurFond: AppColors.brandNavy.withValues(alpha: 0.05),
            couleurTexte: AppColors.brandNavy,
            configuration: widget.configuration,
            valeurs: _dons,
            onChange: (i, v) => setState(() => _dons[i] = v),
          ),
          const SizedBox(height: AppSpacing.md),
          _Totaux(effectifs: effectifs),
          _BlocControle(
            controle: widget.vm.controlerEnDirect(
              _mouvements,
              poidsTotalGrammes: int.tryParse(_poids.text),
              stockOeufs: _saisieOeufs,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _TableauRationnement(
            configuration: widget.configuration,
            vm: widget.vm,
            effectifs: effectifs.parCategorie,
            provendeTotaleG: provendeG,
            provende: provende,
          ),
          // Section unique a l'onglet Pondeuses (Doc H2 §Onglet 2).
          if (_suitLeStockOeufs) ...[
            const SizedBox(height: AppSpacing.md),
            SuiviStockOeufs(
              resultat: widget.vm.calculerStockOeufsEnDirect(_saisieOeufs!),
              oeufsPondus: _oeufsPondus,
              oeufsCasses: _oeufsCasses,
              sortiesPlateaux: _sortiesPlateaux,
              onChangePondus: (v) => setState(() => _oeufsPondus = v),
              onChangeCasses: (v) => setState(() => _oeufsCasses = v),
              onChangeSorties: (v) => setState(() => _sortiesPlateaux = v),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChampTexte(
                  libelle: 'Pesée totale du lot (g)',
                  controleur: _poids,
                  clavier: TextInputType.number,
                  formatteurs: FormatteursSaisie.entierPositif,
                  onChange: () => setState(() {}),
                  note: effectifs.effectifTotal > 0 && _poids.text.isNotEmpty
                      ? 'Poids moyen : '
                            '${CalculFicheJournaliere.poidsMoyenGrammes(poidsTotalGrammes: int.tryParse(_poids.text) ?? 0, effectif: effectifs.effectifTotal)} g'
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ChampTexte(
                  libelle: 'Observation de traitement',
                  controleur: _observation,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // `#day-prophy-multilist` du prototype — la seule cible de la visite
          // guidee qui n'avait aucun point d'accroche de notre cote.
          CibleTour(
            nom: 'prophylaxie-du-jour',
            child: BlocProphylaxieDuJour(vm: widget.vm),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Checkbox(
                value: _traitementValide,
                activeColor: AppColors.brandNavy,
                onChanged: (v) =>
                    setState(() => _traitementValide = v ?? false),
              ),
              const Text(
                'Traitement du jour validé',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: AppColors.onSurface,
                ),
              ),
              const Spacer(),
              AppButton(
                label: _enregistrement ? 'Enregistrement…' : 'Enregistrer',
                icon: Symbols.save,
                onPressed: _enregistrement ? null : _enregistrer,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlocCategories extends StatelessWidget {
  const _BlocCategories({
    required this.titre,
    required this.icone,
    required this.couleurFond,
    required this.couleurTexte,
    required this.configuration,
    required this.valeurs,
    required this.onChange,
  });

  final String titre;
  final IconData icone;
  final Color couleurFond;
  final Color couleurTexte;
  final ConfigurationEspece configuration;
  final List<int> valeurs;
  final void Function(int index, int valeur) onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: couleurFond,
        border: Border.all(color: couleurTexte.withValues(alpha: 0.2)),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 16, color: couleurTexte),
              const SizedBox(width: AppSpacing.xs),
              Text(
                titre.toUpperCase(),
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: couleurTexte,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (var i = 0; i < configuration.categories.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: CompteurCategorie(
                    libelle: configuration.categories[i].libelle,
                    valeur: i < valeurs.length ? valeurs[i] : 0,
                    onChange: (v) => onChange(i, v),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Contrôle de vraisemblance d'expert (`47e_`) : erreurs (saisie refusée) et
/// avertissements (non bloquants), en direct sous les totaux.
class _BlocControle extends StatelessWidget {
  const _BlocControle({required this.controle});

  final ResultatControle controle;

  @override
  Widget build(BuildContext context) {
    if (controle.erreurs.isEmpty && controle.avertissements.isEmpty) {
      return const SizedBox.shrink();
    }
    Widget ligne(String texte, Color couleur, IconData icone) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: couleur),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: AppTypography.textXs,
                color: couleur,
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        key: const Key('controle-vraisemblance'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in controle.erreurs)
            ligne(e, AppColors.errorDeep, Symbols.error),
          for (final a in controle.avertissements)
            ligne(a, AppColors.brandGold, Symbols.warning),
        ],
      ),
    );
  }
}

class _Totaux extends StatelessWidget {
  const _Totaux({required this.effectifs});

  final EffectifsJour effectifs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: _Total(
              titre: 'Effectif Final du Jour (calculé)',
              formule:
                  '= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)',
              valeur: '${effectifs.effectifTotal}',
              couleur: AppColors.brandNavy,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _Total(
              titre: 'Taux de Mortalité du Jour',
              formule: '= (Morts du Jour ÷ Effectif J-1) × 100',
              valeur: Formats.pourcentage(effectifs.tauxMortalite),
              couleur: AppColors.errorDeep,
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.titre,
    required this.formule,
    required this.valeur,
    required this.couleur,
  });

  final String titre;
  final String formule;
  final String valeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre.toUpperCase(),
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.brandNavy,
          ),
        ),
        Text(
          formule,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // BR-ELV-007 / Doc 05 §6 : l'effectif est un `Text`, jamais un champ
        // editable — l'invariant est structurel, pas une propriete `readOnly`
        // contournable.
        Container(
          height: 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Text(
            valeur,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: couleur,
            ),
          ),
        ),
      ],
    );
  }
}

class _TableauRationnement extends StatelessWidget {
  const _TableauRationnement({
    required this.configuration,
    required this.vm,
    required this.effectifs,
    required this.provendeTotaleG,
    required this.provende,
  });

  final ConfigurationEspece configuration;

  /// Source des rations affichees : le bareme configure dans Parametres
  /// Elevage prime sur la valeur de reference de [ConfigurationEspece].
  final FicheEspeceViewModel vm;

  final List<int> effectifs;
  final int provendeTotaleG;

  /// Mode de calcul : sur le poids vif (bovins, avec pesée) ou par tête.
  final ProvendeJour provende;

  @override
  Widget build(BuildContext context) {
    const styleCellule = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 12,
      color: AppColors.onSurface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Symbols.restaurant,
              size: 16,
              color: AppColors.brandGold,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'RATIONNEMENT & PROVENDE SERVIE (g/j)',
              style: styleCellule.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
          ],
        ),
        if (configuration.noteRationnement != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            configuration.noteRationnement!,
            style: styleCellule.copyWith(color: AppColors.outline),
          ),
        ],
        // Une filiere rationnee sur le poids vif dit COMMENT la provende du
        // jour a ete obtenue : sans cette ligne, le total ne serait pas la
        // somme des lignes du tableau et on le croirait faux.
        if (configuration.rationEnPourcentagePoidsVif) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            key: const ValueKey('mode-provende'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: provende.surPoidsVif
                  ? AppColors.successContainer
                  : AppColors.brandGold.withValues(alpha: 0.15),
              borderRadius: AppRadius.cardRadius,
            ),
            child: Text(
              provende.surPoidsVif
                  ? 'Calculée sur le poids vif : poids moyen '
                        '${Formats.nombre(provende.poidsMoyenGrammes ?? 0)} g, '
                        'taux ${provende.tauxPourcent.toString().replaceAll('.', ',')} % '
                        'de matière sèche par jour. Le total ci-dessous '
                        'remplace la somme des rations par tête.'
                  : 'Aucune pesée exploitable : ration indicative par tête. '
                        'Saisissez la pesée totale du lot pour calculer la '
                        'provende sur le poids vif.',
              style: styleCellule.copyWith(
                color: provende.surPoidsVif
                    ? AppColors.successDeep
                    : AppColors.brandNavy,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.outlineVariant),
            borderRadius: AppRadius.cardRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                color: AppColors.surfaceZebra,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Catégorie',
                        style: styleCellule.copyWith(color: AppColors.outline),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Effectif',
                        textAlign: TextAlign.center,
                        style: styleCellule.copyWith(color: AppColors.outline),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Ration',
                        textAlign: TextAlign.center,
                        style: styleCellule.copyWith(color: AppColors.outline),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Provende',
                        textAlign: TextAlign.right,
                        style: styleCellule.copyWith(color: AppColors.outline),
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < configuration.categories.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  color: i.isOdd ? AppColors.surfaceZebra : null,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          configuration.categories[i].libelle,
                          style: styleCellule.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandNavy,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${i < effectifs.length ? effectifs[i] : 0}',
                          textAlign: TextAlign.center,
                          style: styleCellule,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${vm.rationCategorie(i)} g/j',
                          textAlign: TextAlign.center,
                          style: styleCellule,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${Formats.nombre((i < effectifs.length ? effectifs[i] : 0) * vm.rationCategorie(i))} g',
                          textAlign: TextAlign.right,
                          style: styleCellule.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                color: AppColors.brandNavy.withValues(alpha: 0.05),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Provende Servie du Jour',
                        style: styleCellule.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ),
                    Text(
                      '${Formats.nombre(provendeTotaleG)} g '
                      '(${(provendeTotaleG / 1000).toStringAsFixed(1)} Kg)',
                      style: styleCellule.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChampTexte extends StatelessWidget {
  const _ChampTexte({
    required this.libelle,
    required this.controleur,
    this.clavier,
    this.formatteurs,
    this.onChange,
    this.note,
  });

  final String libelle;
  final TextEditingController controleur;
  final TextInputType? clavier;

  /// Filtre de frappe — voir `FormatteursSaisie`.
  final List<TextInputFormatter>? formatteurs;
  final VoidCallback? onChange;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(libelle.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 40,
          child: TextField(
            controller: controleur,
            keyboardType: clavier,
            inputFormatters: formatteurs,
            onChanged: (_) => onChange?.call(),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surfaceCard,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.cardRadius,
                borderSide: const BorderSide(color: AppColors.outlineVariant),
              ),
            ),
          ),
        ),
        if (note != null)
          Text(
            note!,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
      ],
    );
  }
}
