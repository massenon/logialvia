import '../../../core/widgets/auteur_courant.dart';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/resultat/resultat.dart';
import '../../../commercial/domain/entities/vente.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import '../../data/repositories/parametres_repository_drift.dart';
import '../../domain/entities/parametres_entreprise.dart';
import '../../domain/entities/utilisateur.dart';
import '../../domain/repositories/parametres_repository.dart';
import '../../../commercial/domain/services/transmission_mecef.dart';
import '../../../core/sync/planificateur_synchronisation.dart';
import '../../../core/sync/service_appairage.dart';
import '../../../core/sync/depot_etat_synchronisation.dart';
import '../../../core/sync/depot_journal_synchronisation.dart';
import '../viewmodels/appairage_view_model.dart';
import '../viewmodels/synchronisation_view_model.dart';
import 'widgets/onglet_synchronisation.dart';
import '../viewmodels/modules_actifs_view_model.dart';
import '../viewmodels/parametres_generaux_view_model.dart';
import '../../data/seed/seed_demonstration.dart';
import '../../domain/services/service_archivage.dart';
import '../../domain/services/service_images_entreprise.dart';
import '../../domain/services/service_reinitialisation.dart';
import '../../domain/services/service_sauvegarde.dart';
import '../viewmodels/corbeille_view_model.dart';
import '../viewmodels/sauvegardes_view_model.dart';
import 'widgets/modale_utilisateur.dart';
import 'widgets/onglet_appairage.dart';
import 'widgets/onglet_corbeille.dart';
import 'widgets/onglet_donnees_test.dart';
import 'widgets/onglet_sauvegardes.dart';
import '../../../core/saisie/formats_saisie.dart';

class PageParametresGeneraux extends StatelessWidget {
  const PageParametresGeneraux({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ParametresGenerauxViewModel>(
          create: (context) => ParametresGenerauxViewModel(
            ParametresRepositoryDrift(context.read<AppDatabase>()),
            // Logo et favicon : copiés dans le dossier de données du poste.
            ServiceImagesEntreprise(
              () async => Directory(
                '${(await getApplicationSupportDirectory()).path}'
                '${Platform.pathSeparator}images',
              ),
            ),
          )..charger(),
        ),
        // Corbeille et Donnees de Test partagent un ViewModel : les deux
        // decrivent ce qui peut disparaitre, et l'un vide la corbeille de
        // l'autre.
        ChangeNotifierProvider<CorbeilleViewModel>(
          create: (context) => CorbeilleViewModel(
            ServiceArchivage(context.read<AppDatabase>()),
            ServiceReinitialisation(context.read<AppDatabase>()),
            SeedDemonstration(context.read<AppDatabase>()),
          )..charger(),
        ),
        // L'onglet Sauvegardes a son propre ViewModel : il lit le disque, pas
        // la table des parametres.
        ChangeNotifierProvider<SauvegardesViewModel>(
          create: (context) => SauvegardesViewModel(
            ServiceSauvegarde(
              context.read<AppDatabase>(),
              context.read<DossierDocuments>().dossier,
            ),
          )..charger(),
        ),
        // Synchronisation : journal des tentatives, refuses, coherence locale.
        ChangeNotifierProvider<SynchronisationViewModel>(
          create: (context) => SynchronisationViewModel(
            context.read<PlanificateurSynchronisation>(),
            DepotJournalSynchronisation(context.read<AppDatabase>()),
            DepotEtatSynchronisation(context.read<AppDatabase>()),
            Directory(
              '${context.read<DossierDocuments>().dossier.path}'
              '${Platform.pathSeparator}LogiALVIA'
              '${Platform.pathSeparator}Journal',
            ),
          )..charger(),
        ),
        // Appairage : a son propre ViewModel (reseau + coffre du systeme).
        ChangeNotifierProvider<AppairageViewModel>(
          create: (context) => AppairageViewModel(
            context.read<ServiceAppairage>(),
            context.read<PlanificateurSynchronisation>(),
          )..charger(),
        ),
      ],
      child: const ParametresGenerauxScreen(),
    );
  }
}

/// Paramètres Généraux — Doc F8, **4 onglets internes** (`switchPgTab`).
class ParametresGenerauxScreen extends StatefulWidget {
  const ParametresGenerauxScreen({super.key});

  @override
  State<ParametresGenerauxScreen> createState() =>
      _ParametresGenerauxScreenState();
}

class _ParametresGenerauxScreenState extends State<ParametresGenerauxScreen> {
  int _onglet = 0;

  static const List<String> _onglets = [
    'Modules Actifs',
    'Données de l\'Entreprise',
    'Gestion Utilisateurs',
    'Modes de Paiement',
    'Appairage',
    'Synchronisation',
    'Sauvegardes',
    'Corbeille',
    'Données de Test',
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ParametresGenerauxViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Symbols.settings, size: 24, color: AppColors.brandNavy),
              SizedBox(width: AppSpacing.xs),
              Text('Paramètres Généraux', style: AppTypography.pageTitle),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // `overflow-x-auto` du prototype : la barre defile plutot que de
          // deborder. Sans lui, un libelle un peu long fait lever
          // `RenderFlex overflowed` a chaque affichage de l'ecran.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _onglets.length; i++)
                  _Onglet(
                    libelle: _onglets[i],
                    actif: i == _onglet,
                    onTap: () => setState(() => _onglet = i),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          switch (_onglet) {
            0 => const _OngletModulesActifs(),
            1 => _OngletEntreprise(vm: vm),
            2 => _OngletUtilisateurs(vm: vm),
            3 => const _OngletModesPaiement(),
            4 => const OngletAppairage(),
            5 => const OngletSynchronisation(),
            6 => const OngletSauvegardes(),
            7 => const OngletCorbeille(),
            _ => const OngletDonneesTest(),
          },
        ],
      ),
    );
  }
}

class _Onglet extends StatelessWidget {
  const _Onglet({
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
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
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
            fontSize: AppTypography.textXs,
            fontWeight: FontWeight.w700,
            color: actif ? AppColors.brandNavy : AppColors.outline,
          ),
        ),
      ),
    );
  }
}

/// Onglet 1 — Modules Actifs (Doc F8 Onglet 1, Doc I2).
///
/// C'est **le seul endroit** d'où les 3 filières désactivables peuvent être
/// activées : sans cet écran, elles restaient inaccessibles par conception
/// (masquées de la barre latérale et redirigées par le routeur).
class _OngletModulesActifs extends StatelessWidget {
  const _OngletModulesActifs();

  /// Les 5 lignes du prototype, puis escargots et ovins (DV-16, DV-17).
  static const List<({String? moduleId, String libelle, String note})> _lignes =
      [
        (
          moduleId: null,
          libelle: 'Goliaths',
          note: 'Activité principale confirmée — toujours actif',
        ),
        (
          moduleId: null,
          libelle: 'Pintades',
          note: 'Activité principale confirmée — toujours actif',
        ),
        (
          moduleId: 'pisciculture',
          libelle: 'Poissons-Chats (Pisciculture)',
          note: 'Fiche construite, paramètres non confirmés',
        ),
        (
          moduleId: 'aviculture_classique',
          libelle: 'Poulets / Pondeuses',
          note: 'Filière dupliquée — désactivée par défaut',
        ),
        (
          moduleId: 'cuniculture',
          libelle: 'Lapins (Cuniculture)',
          note: 'Copie fidèle — désactivée par défaut',
        ),
        (
          moduleId: 'heliciculture',
          libelle: 'Escargots (Héliciculture)',
          note: 'Filière ajoutée — désactivée par défaut',
        ),
        (
          moduleId: 'ovins',
          libelle: 'Ovins',
          note: 'Filière ajoutée — désactivée par défaut',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final modules = context.watch<ModulesActifsViewModel>();

    return CarteSection(
      titre: 'Modules Actifs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Textes repris mot pour mot du prototype (Doc F8 Onglet 1).
          const Text(
            'Goliaths et Pintades sont l\'activité principale confirmée '
            'd\'ALLMANY et restent toujours actifs. Les filières ci-dessous '
            'sont désactivées par défaut — activez-les uniquement si '
            'l\'activité démarre réellement.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: AppTypography.textXs,
              height: 1.5,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final ligne in _lignes)
            _LigneModule(
              libelle: ligne.libelle,
              note: ligne.note,
              // Goliaths / Pintades : `checked disabled` — affichés à titre
              // informatif, aucune interaction possible (Doc I2 §2).
              verrouille: ligne.moduleId == null,
              actif: ligne.moduleId == null
                  ? true
                  : modules.estActif(ligne.moduleId!),
              onChange: ligne.moduleId == null
                  ? null
                  : (valeur) async {
                      await modules.basculer(ligne.moduleId!, actif: valeur);
                      if (!context.mounted) return;
                      showAppToast(
                        context,
                        valeur
                            ? '${ligne.libelle} activée — sa fiche apparaît '
                                  'dans le menu latéral.'
                            : '${ligne.libelle} désactivée. Les données '
                                  'historiques sont conservées.',
                      );
                    },
            ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Activer un module affiche immédiatement sa fiche et son raccourci '
            'dans le menu latéral et le panneau d\'accès rapide.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _VerrouDonneesTest(),
        ],
      ),
    );
  }
}

/// Verrou de l'onglet « Données de Test ».
///
/// Il vit **ici**, dans Modules Actifs, et non dans l'onglet qu'il protège :
/// un interrupteur posé sur la porte qu'il verrouille ne verrouille rien.
class _VerrouDonneesTest extends StatelessWidget {
  const _VerrouDonneesTest();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ParametresGenerauxViewModel>();
    final actif = vm.parametres.modeDonneesTest;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: actif ? AppColors.errorContainer : AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LigneModule(
            libelle: 'Mode « Données de Test »',
            note: actif
                ? 'ACTIF — l\'onglet Données de Test autorise la remise à zéro'
                : 'Désactivé — l\'onglet Données de Test est verrouillé',
            actif: actif,
            verrouille: false,
            onChange: (valeur) async {
              vm.mettreAJour(vm.parametres.copyWith(modeDonneesTest: valeur));
              await vm.enregistrerParametres();
              if (!context.mounted) return;
              showAppToast(
                context,
                valeur
                    ? 'Mode « Données de Test » activé. Refermez-le dès la fin '
                          'de la période d\'essai.'
                    : 'Mode « Données de Test » désactivé : la '
                          'réinitialisation n\'est plus possible.',
                type: valeur ? ToastType.warning : ToastType.success,
              );
            },
          ),
          Text(
            'Tant qu\'il est désactivé, personne ne peut effacer les ventes, '
            'les achats ni les écritures — pas même une administratrice. '
            'Laissez-le fermé une fois l\'exploitation démarrée.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              height: 1.4,
              color: actif ? AppColors.errorDeep : AppColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneModule extends StatelessWidget {
  const _LigneModule({
    required this.libelle,
    required this.note,
    required this.actif,
    required this.verrouille,
    required this.onChange,
  });

  final String libelle;
  final String note;
  final bool actif;
  final bool verrouille;
  final ValueChanged<bool>? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      libelle,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (verrouille) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(
                        Symbols.lock,
                        size: 14,
                        color: AppColors.outline,
                      ),
                    ],
                  ],
                ),
                Text(
                  note,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: actif,
            activeThumbColor: AppColors.brandNavy,
            onChanged: verrouille ? null : onChange,
          ),
        ],
      ),
    );
  }
}

/// Onglet 2 — Données de l'Entreprise.
class _OngletEntreprise extends StatelessWidget {
  const _OngletEntreprise({required this.vm});

  final ParametresGenerauxViewModel vm;

  @override
  Widget build(BuildContext context) {
    final p = vm.parametres;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteSection(
          titre: 'Informations Générales',
          child: Column(
            children: [
              _Champ(
                libelle: 'Raison Sociale *',
                valeur: p.raisonSociale,
                onChange: (v) => vm.mettreAJour(p.copyWith(raisonSociale: v)),
              ),
              _Champ(
                libelle: 'Nom du Promoteur',
                valeur: p.nomPromoteur ?? '',
                onChange: (v) => vm.mettreAJour(p.copyWith(nomPromoteur: v)),
              ),
              _Champ(
                libelle: 'Adresse du Siège d\'Exploitation',
                valeur: p.adresseSiege ?? '',
                onChange: (v) => vm.mettreAJour(p.copyWith(adresseSiege: v)),
              ),
              _Champ(
                libelle: 'Téléphone Principal',
                valeur: p.telephone ?? '',
                onChange: (v) => vm.mettreAJour(p.copyWith(telephone: v)),
              ),
              _Champ(
                libelle: 'Email de Contact',
                valeur: p.email ?? '',
                onChange: (v) => vm.mettreAJour(p.copyWith(email: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Ajoutee : le prototype ne prevoit aucun delai de paiement, alors que
        // ses rapports affichent une colonne « Echeance ». Voir Doc F7.
        CarteSection(
          titre: 'Conditions de Vente',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Champ(
                libelle: 'Délai de paiement par défaut (jours)',
                valeur: p.delaiPaiementJours?.toString() ?? '',
                clavier: TextInputType.number,
                formatteurs: FormatteursSaisie.entierPositif,
                note:
                    'Pré-remplit « Payable le » au point de vente. Laissé '
                    'vide, aucune échéance n\'est proposée et aucune créance '
                    'n\'est signalée en retard.',
                onChange: (v) {
                  final jours = int.tryParse(v.trim());
                  vm.mettreAJour(
                    p.copyWith(
                      // Une valeur illisible ou negative vaut « non fixe » :
                      // mieux vaut ne rien affirmer qu'affirmer faux.
                      delaiPaiementJours: jours != null && jours > 0
                          ? jours
                          : null,
                    ),
                  );
                },
              ),
              if (p.delaiPaiementJours == null)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.brandGold.withValues(alpha: 0.1),
                    borderRadius: AppRadius.cardRadius,
                  ),
                  child: const Text(
                    'Aucun délai n\'est fixé. Les ventes à crédit sont donc '
                    'enregistrées « Sans échéance » : elles apparaissent dans '
                    'les créances, mais ne sont jamais déclarées en retard et '
                    'ne déclenchent aucune lettre de relance pour retard. '
                    'Renseignez le délai réellement pratiqué pour activer ce '
                    'suivi.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.brandNavy,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Informations Légales & Fiscales',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Champ(
                libelle: 'Identifiant Fiscal Unique (IFU) *',
                valeur: p.ifu ?? '',
                clavier: TextInputType.number,
                formatteurs: FormatteursSaisie.entierPositif,
                note: 'Chiffres uniquement',
                onChange: (v) => vm.mettreAJour(p.copyWith(ifu: v)),
              ),
              _Champ(
                libelle: 'Registre du Commerce (RCCM)',
                valeur: p.rccm ?? '',
                onChange: (v) => vm.mettreAJour(p.copyWith(rccm: v)),
              ),
              const SizedBox(height: AppSpacing.sm),
              // BR-ADM-004 — bascule conditionnee a l'IFU ET au RCCM.
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: p.mecefActivable
                      ? AppColors.successContainer
                      : AppColors.surfaceZebra,
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Module de conformité fiscale MeCeF',
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            p.mecefActivable
                                ? 'IFU et RCCM renseignés — activable.'
                                : 'BR-ADM-004 : renseignez l\'IFU et le RCCM '
                                      'pour pouvoir l\'activer.',
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 12,
                              color: AppColors.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: p.mecefActif,
                      activeThumbColor: AppColors.brandNavy,
                      onChanged: (valeur) {
                        final resultat = vm.basculerMecef(actif: valeur);
                        if (resultat is Echec<void>) {
                          showAppToast(
                            context,
                            resultat.message,
                            type: ToastType.error,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              // La transmission n'a de sens que si le module est actif.
              if (p.mecefActif) ...[
                const SizedBox(height: AppSpacing.sm),
                _Champ(
                  libelle: 'URL du service e-MECeF',
                  valeur: p.mecefUrl ?? '',
                  note: 'Fournie par la DGI',
                  onChange: (v) => vm.mettreAJour(p.copyWith(mecefUrl: v)),
                ),
                _Champ(
                  libelle: 'NIM (Numéro d\'Identification de la Machine)',
                  valeur: p.mecefNim ?? '',
                  note: 'S\'imprime sur chaque facture normalisée',
                  onChange: (v) => vm.mettreAJour(p.copyWith(mecefNim: v)),
                ),
                const SizedBox(height: AppSpacing.sm),
                const _JetonMecef(),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Configuration Email (SMTP)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _Champ(
                      libelle: 'Serveur SMTP',
                      valeur: p.smtpServeur ?? '',
                      onChange: (v) =>
                          vm.mettreAJour(p.copyWith(smtpServeur: v)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _Champ(
                      libelle: 'Port',
                      valeur: p.smtpPort?.toString() ?? '',
                      clavier: TextInputType.number,
                      formatteurs: FormatteursSaisie.entierPositif,
                      onChange: (v) =>
                          vm.mettreAJour(p.copyWith(smtpPort: int.tryParse(v))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('SÉCURITÉ', style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<String>(
                initialValue: p.smtpSecurite,
                isExpanded: true,
                decoration: _decoration,
                items: [
                  for (final s in ParametresEntrepriseModele.securitesSmtp)
                    DropdownMenuItem(
                      value: s,
                      child: Text(s, style: _style),
                    ),
                ],
                onChanged: (v) => vm.mettreAJour(p.copyWith(smtpSecurite: v)),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Doc I3 §3 / Strict Avoid §13.
              const Text(
                'Le mot de passe SMTP n\'est volontairement pas stocké ici : '
                'un secret n\'a pas sa place en clair dans la base. Il sera '
                'demandé via un stockage sécurisé le jour où l\'envoi '
                'd\'e-mails sera réellement implémenté.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Logo / Favicon (F8 Onglet 2) : un champ de saisie du chemin par image ;
        // le fichier est validé (type reel, taille) puis COPIE dans le dossier du
        // poste — voir `ServiceImagesEntreprise` (Doc I3 §2).
        CarteSection(
          titre: 'Logo / Favicon',
          child: _ImagesEntreprise(vm: vm),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Enregistrer les Modifications',
          icon: Symbols.save,
          fullWidth: true,
          onPressed: () async {
            final modules = context.read<ModulesActifsViewModel>();
            final resultat = await vm.enregistrerParametres();
            if (!context.mounted) return;
            switch (resultat) {
              case Succes<void>():
                // L'entree « Facturation MeCeF » de la barre laterale depend
                // de `mecefActif`. Sans ce rechargement, activer le module ne
                // se voyait qu'au prochain demarrage -- ce qui donnait
                // l'impression que rien ne s'etait passe.
                await modules.charger();
                if (!context.mounted) return;
                showAppToast(context, 'Paramètres enregistrés.');
              case Echec<void>(message: final message):
                showAppToast(context, message, type: ToastType.error);
            }
          },
        ),
      ],
    );
  }
}

/// Onglet 3 — Gestion Utilisateurs.
class _OngletUtilisateurs extends StatelessWidget {
  const _OngletUtilisateurs({required this.vm});

  final ParametresGenerauxViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Gestion des Utilisateurs',
      action: AppButton(
        label: 'Ajouter un Utilisateur',
        icon: Symbols.person_add,
        height: 32,
        onPressed: () async {
          final resultat = await afficherModaleUtilisateur(context, vm);
          if (resultat == null || !context.mounted) return;
          switch (resultat) {
            case Succes<Utilisateur>(valeur: final u):
              showAppToast(
                context,
                'Compte « ${u.identifiant} » créé. Communiquez-lui son mot de '
                'passe : il n\'est plus consultable ensuite.',
              );
            case Echec<Utilisateur>(message: final message):
              showAppToast(context, message, type: ToastType.error);
          }
        },
      ),
      child: Column(
        children: [
          Container(
            color: AppColors.surfaceZebra,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _entete('Nom Complet', flex: 2),
                _entete('Identifiant', flex: 2),
                _entete('Rôle'),
                _entete('Actions', alignement: TextAlign.right),
              ],
            ),
          ),
          for (var i = 0; i < vm.utilisateurs.length; i++)
            _LigneUtilisateur(
              entree: vm.utilisateurs[i],
              zebre: i.isOdd,
              vm: vm,
            ),
        ],
      ),
    );
  }

  static Widget _entete(
    String libelle, {
    int flex = 1,
    TextAlign alignement = TextAlign.left,
  }) => Expanded(
    flex: flex,
    child: Text(
      libelle,
      textAlign: alignement,
      style: _style.copyWith(fontSize: 12, color: AppColors.outline),
    ),
  );
}

class _LigneUtilisateur extends StatelessWidget {
  const _LigneUtilisateur({
    required this.entree,
    required this.zebre,
    required this.vm,
  });

  final UtilisateurAvecRole entree;
  final bool zebre;
  final ParametresGenerauxViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: zebre ? AppColors.surfaceZebra : null,
        border: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(entree.utilisateur.nom, style: _style)),
          Expanded(
            flex: 2,
            child: Text(entree.utilisateur.identifiant, style: _style),
          ),
          Expanded(child: Text(entree.role.libelle, style: _style)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.errorDeep,
                ),
                onPressed: () async {
                  final resultat = await vm.supprimerUtilisateur(
                    entree,
                    auteur: auteurCourant(context),
                  );
                  if (!context.mounted) return;
                  switch (resultat) {
                    case Succes<void>():
                      showAppToast(context, 'Utilisateur supprimé.');
                    case Echec<void>(message: final message):
                      showAppToast(context, message, type: ToastType.error);
                  }
                },
                child: const Text(
                  'Supprimer',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Onglet 4 — Modes de Paiement.
class _OngletModesPaiement extends StatelessWidget {
  const _OngletModesPaiement();

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Modes de Paiement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('MODES DE RÈGLEMENT', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          // Les 2 lignes sont `checked disabled` — informatives, non modifiables.
          for (final mode in const ['Espèces', 'Mobile Money'])
            _LigneModule(
              libelle: mode,
              note: 'Toujours actif',
              actif: true,
              verrouille: true,
              onChange: null,
            ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Conformément au CDCT, seuls 2 modes de règlement sont retenus — '
            'pas de virement bancaire ni de multi-comptes.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Arbitrage de la Gerante : « Avance » quitte la table des modes.
          // Elle repond a « combien le client a paye », pas a « avec quoi ».
          // Point 3 de l'index maitre — clos.
          const Text('CONDITIONS DE PAIEMENT', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          for (final condition in ConditionPaiement.toutes)
            _LigneModule(
              libelle: condition,
              note: condition == ConditionPaiement.comptant
                  ? 'Vente soldée à l\'encaissement'
                  : 'Vente à crédit — suivie dans Clients & Créances',
              actif: true,
              verrouille: true,
              onChange: null,
            ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.brandGold.withValues(alpha: 0.1),
              borderRadius: AppRadius.cardRadius,
            ),
            child: const Text(
              '« Avance (Solde Restant Dû) » figurait jusqu\'ici parmi les '
              'modes de règlement. C\'est une condition de paiement : une '
              'avance se verse en espèces ou en Mobile Money, comme toute '
              'autre vente. Les deux se choisissent désormais séparément au '
              'point de vente, ce qui permet enfin de savoir avec quoi une '
              'avance a été encaissée.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                height: 1.4,
                color: AppColors.brandNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Champ extends StatelessWidget {
  const _Champ({
    required this.libelle,
    required this.valeur,
    required this.onChange,
    this.clavier,
    this.formatteurs,
    this.note,
  });

  final String libelle;
  final String valeur;
  final ValueChanged<String> onChange;
  final TextInputType? clavier;

  /// Filtre de frappe — voir `FormatteursSaisie`.
  final List<TextInputFormatter>? formatteurs;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(libelle.toUpperCase(), style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            initialValue: valeur,
            keyboardType: clavier,
            inputFormatters: formatteurs,
            onChanged: onChange,
            style: _style,
            decoration: _decoration,
          ),
          if (note != null)
            Text(
              note!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                color: AppColors.outline,
              ),
            ),
        ],
      ),
    );
  }
}

const TextStyle _style = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 13,
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

/// Le jeton e-MECeF — saisi ici, stocké hors de la base.
///
/// Un jeton fiscal donne le droit d'émettre des factures au nom de
/// l'entreprise. La base SQLite se recopie à chaque sauvegarde et se transporte
/// sur une clé USB : le jeton n'y descend pas. Il va dans le magasin sécurisé
/// du système, comme le veut déjà la note de `PARAMETRES_ENTREPRISE` pour le
/// mot de passe SMTP.
class _JetonMecef extends StatefulWidget {
  const _JetonMecef();

  @override
  State<_JetonMecef> createState() => _JetonMecefState();
}

class _JetonMecefState extends State<_JetonMecef> {
  static const DepotJetonMecef _depot = DepotJetonMecef();

  final TextEditingController _saisie = TextEditingController();
  bool _renseigne = false;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _relire();
  }

  Future<void> _relire() async {
    final present = await _depot.renseigne;
    if (!mounted) return;
    setState(() {
      _renseigne = present;
      _charge = true;
    });
  }

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_charge) return const SizedBox.shrink();

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
              Icon(
                _renseigne ? Symbols.key : Symbols.key_off,
                size: 18,
                color: _renseigne ? AppColors.successDeep : AppColors.outline,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  _renseigne
                      ? 'Jeton e-MECeF enregistré. Il n\'est pas affiché, et '
                            'ne figure pas dans les sauvegardes.'
                      : 'Aucun jeton. Sans lui, les factures s\'émettent et '
                            's\'impriment, mais restent « À transmettre ».',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.outline,
                  ),
                ),
              ),
              if (_renseigne)
                TextButton(
                  onPressed: () async {
                    await _depot.effacer();
                    await _relire();
                    if (!context.mounted) return;
                    showAppToast(context, 'Jeton e-MECeF effacé.');
                  },
                  child: const Text('Effacer'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _saisie,
                  obscureText: true,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.onSurface,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Coller le jeton fourni par la DGI',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Enregistrer le jeton',
                icon: Symbols.key,
                variant: AppButtonVariant.outline,
                onPressed: () async {
                  final valeur = _saisie.text.trim();
                  if (valeur.isEmpty) {
                    showAppToast(
                      context,
                      'Le jeton est vide.',
                      type: ToastType.error,
                    );
                    return;
                  }
                  await _depot.ecrire(valeur);
                  _saisie.clear();
                  await _relire();
                  if (!context.mounted) return;
                  showAppToast(context, 'Jeton e-MECeF enregistré.');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Zone « Logo / Favicon » : saisie du chemin du fichier, « Importer »,
/// aperçu, « Retirer ».
class _ImagesEntreprise extends StatelessWidget {
  const _ImagesEntreprise({required this.vm});

  final ParametresGenerauxViewModel vm;

  @override
  Widget build(BuildContext context) {
    final p = vm.parametres;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LigneImage(
          vm: vm,
          type: TypeImageEntreprise.logo,
          titre: 'Logo de l\'entreprise',
          note: 'PNG, JPG ou WebP, 2 Mo au maximum.',
          chemin: p.cheminLogo,
        ),
        const SizedBox(height: AppSpacing.md),
        _LigneImage(
          vm: vm,
          type: TypeImageEntreprise.favicon,
          titre: 'Favicon (icône)',
          note: 'PNG, ICO, JPG ou WebP, carré, 512 Ko au maximum.',
          chemin: p.cheminFavicon,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Copiez le chemin du fichier (Explorateur : clic droit > « Copier en '
          'tant que chemin d\'accès ») et collez-le dans le champ. Le fichier '
          'est copié dans le dossier du poste : il peut ensuite être déplacé ou '
          'supprimé. Ces images restent propres à ce poste (elles ne sont pas '
          'synchronisées avec le serveur).',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            color: AppColors.outline,
          ),
        ),
      ],
    );
  }
}

class _LigneImage extends StatefulWidget {
  const _LigneImage({
    required this.vm,
    required this.type,
    required this.titre,
    required this.note,
    required this.chemin,
  });

  final ParametresGenerauxViewModel vm;
  final TypeImageEntreprise type;
  final String titre;
  final String note;
  final String? chemin;

  @override
  State<_LigneImage> createState() => _LigneImageState();
}

class _LigneImageState extends State<_LigneImage> {
  final TextEditingController _saisie = TextEditingController();
  bool _enCours = false;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  Future<void> _importer() async {
    setState(() => _enCours = true);
    final resultat = await widget.vm.importerImage(widget.type, _saisie.text);
    if (!mounted) return;
    setState(() => _enCours = false);
    switch (resultat) {
      case Succes<void>():
        _saisie.clear();
        showAppToast(
          context,
          '${widget.titre} importé : pensez à « Enregistrer les Modifications ».',
          type: ToastType.success,
        );
      case Echec<void>(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chemin = widget.chemin;
    final existe = chemin != null && File(chemin).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.titre.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              margin: const EdgeInsets.only(right: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceZebra,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: AppColors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: existe
                  ? Image.file(
                      File(chemin),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Symbols.broken_image,
                        color: AppColors.outline,
                      ),
                    )
                  : const Icon(Symbols.image, color: AppColors.outline),
            ),
            Expanded(
              child: TextField(
                controller: _saisie,
                onSubmitted: (_) => _importer(),
                style: _style,
                decoration: _decoration.copyWith(
                  hintText: r'C:\Images\mon-fichier.png',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'Importer',
              icon: Symbols.upload,
              variant: AppButtonVariant.outline,
              onPressed: _enCours ? null : _importer,
            ),
            if (chemin != null) ...[
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Retirer',
                icon: Symbols.delete,
                variant: AppButtonVariant.outline,
                onPressed: () => widget.vm.retirerImage(widget.type),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.note,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            color: AppColors.outline,
          ),
        ),
      ],
    );
  }
}
