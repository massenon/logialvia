import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/sync/moteur_synchronisation.dart';
import '../../../../core/sync/droits_poste.dart';
import '../../../../core/sync/environnement.dart';
import '../../../../core/sync/service_appairage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../../data/repositories/preferences_poste_repository.dart';
import '../../viewmodels/appairage_view_model.dart';

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

/// Onglet « Appairage » — relie ce poste au serveur web (`45_`, `46_`).
///
/// ## Ce que cet onglet ne fait PAS
///
/// - il n'ouvre **aucune session** dans l'application : les comptes locaux
///   restent ceux du poste (DV-20) ; le compte saisi ici est un compte **web**,
///   utilisé une seule fois pour obtenir le jeton de synchronisation ;
/// - il ne **synchronise** pas encore : l'envoi et la réception sont l'étape P2.
///   L'onglet le dit, pour qu'« appairé » ne soit pas pris pour « synchronisé ».
class OngletAppairage extends StatelessWidget {
  const OngletAppairage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AppairageViewModel>();
    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    final etat = vm.etat!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BandeauEtat(etat: etat),
        const SizedBox(height: AppSpacing.md),
        const _CarteEnvironnement(),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: 'Ce poste',
          icone: Symbols.computer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Ligne('Code du poste', etat.codePoste ?? 'Non attribué'),
              _Ligne(
                'Identifiant',
                etat.identifiantPoste,
                selectionnable: true,
              ),
              if (etat.appaire) ...[
                _Ligne('Serveur', etat.adresse ?? '—'),
                _Ligne('Compte web', etat.compte ?? '—'),
                if (etat.appaireLe != null)
                  _Ligne(
                    'Appairé le',
                    '${Formats.date(etat.appaireLe!)} à '
                        '${Formats.heure(etat.appaireLe!)}',
                  ),
              ],
            ],
          ),
        ),
        if (etat.appaire) ...[
          const SizedBox(height: AppSpacing.md),
          _CarteDroits(vm: vm, etat: etat),
          const SizedBox(height: AppSpacing.md),
          _CarteSynchroAuto(vm: vm),
        ],
        const SizedBox(height: AppSpacing.md),
        if (etat.appaire)
          _CarteAppaire(vm: vm)
        else
          _FormulaireAppairage(
            vm: vm,
            adresseInitiale:
                etat.adresse ?? Environnement.courant.adresseProposee ?? '',
          ),
        if (vm.dernierRapport != null) ...[
          const SizedBox(height: AppSpacing.md),
          _MessageSynchro(rapport: vm.dernierRapport!),
        ],
        if (vm.dernierResultat != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Message(resultat: vm.dernierResultat!),
        ],
      ],
    );
  }
}

/// Environnement de cette construction du logiciel (`Environnement`) et
/// adresse proposée à l'appairage.
class _CarteEnvironnement extends StatelessWidget {
  const _CarteEnvironnement();

  @override
  Widget build(BuildContext context) {
    final env = Environnement.courant;

    return CarteSection(
      titre: 'Environnement',
      icone: Symbols.public,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Ligne('Environnement', env.libelle),
          _Ligne(
            'Adresse par défaut',
            env.adresseProposee ?? 'Aucune : à saisir à l\'appairage',
          ),
        ],
      ),
    );
  }
}

/// « Synchro automatique » : à quel rythme le poste reçoit ce que les autres
/// postes ont saisi (la routine). Les autres déclencheurs ne changent pas : à
/// l'ouverture, 3 s après une saisie, à la fermeture, et toutes les 30 s pour
/// savoir si le web a demandé une synchronisation.
class _CarteSynchroAuto extends StatelessWidget {
  const _CarteSynchroAuto({required this.vm});

  final AppairageViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Synchro automatique',
      icone: Symbols.schedule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Synchroniser toutes les'),
              const SizedBox(width: AppSpacing.sm),
              DropdownButton<int>(
                key: const Key('intervalle-synchronisation'),
                value: vm.intervalleMinutes,
                items: [
                  for (final minutes
                      in PreferencesPosteRepository.intervallesSynchroMinutes)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(
                        minutes == 1 ? '1 minute' : '$minutes minutes',
                      ),
                    ),
                ],
                onChanged: (minutes) {
                  if (minutes != null) vm.definirIntervalleMinutes(minutes);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Une saisie est envoyée 3 secondes après, à la fermeture du '
            'logiciel et sur « Synchroniser maintenant » : ce réglage ne '
            'concerne que la réception de ce que les autres postes ont saisi.',
            style: TextStyle(
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

/// Libellés des rôles du serveur (`config/logialvia.php`, DV-07).
const Map<String, String> _libellesRoles = {
  'admin': 'Administrateur',
  'comptable': 'Comptable',
  'caissier': 'Agent de Vente',
  'animalier': 'Agent d\'Élevage',
};

/// État de droits et d'horloge du poste (`47g_`) : compte appairé, droits effectifs, ce qui
/// attend un droit, écart d'horloge avec le serveur, et « Réessayer ».
class _CarteDroits extends StatelessWidget {
  const _CarteDroits({required this.vm, required this.etat});

  final AppairageViewModel vm;
  final EtatAppairage etat;

  @override
  Widget build(BuildContext context) {
    final droits = vm.droits?.droits ?? etat.droits;
    final enAttente = vm.droits?.enAttenteDeDroit ?? 0;
    final decalage = vm.droits?.decalageHorloge ?? etat.decalageHorloge;
    final horloge = decalage == null ? null : analyserHorloge(decalage);

    return CarteSection(
      titre: 'Droits et horloge',
      icone: Symbols.shield_person,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (droits == null)
            const _Ligne(
              'Droits',
              'Non communiqués par le serveur : le poste propose tout et le '
                  'serveur tranche.',
            )
          else ...[
            _Ligne('Compte', droits.compte),
            _Ligne(
              'Rôle',
              droits.roles.isEmpty
                  ? 'Aucun rôle'
                  : droits.roles.map((r) => _libellesRoles[r] ?? r).join(', '),
            ),
            _Ligne(
              'Peut envoyer',
              '${droits.tablesEcrites.length} table(s) de saisies, '
                  '${droits.demandes.length} type(s) de réglages',
            ),
          ],
          _Ligne(
            'En attente de droit',
            enAttente == 0
                ? 'Rien'
                : '$enAttente saisie(s) ou demande(s) que ce compte ne peut '
                      'pas envoyer. Elles ne sont pas perdues : elles partiront '
                      'dès qu\'un compte qui en a le droit synchronisera.',
          ),
          _Ligne(
            'Horloge',
            decalage == null
                ? 'Pas encore mesurée'
                : horloge!.etat == EtatHorloge.juste
                ? 'Juste (écart ${formaterDuree(decalage)})'
                : decalage.isNegative
                ? 'En retard de ${formaterDuree(decalage)}'
                : 'En avance de ${formaterDuree(decalage)}',
          ),
          if (horloge != null && horloge.aAvertir)
            Container(
              key: const Key('appairage-horloge'),
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Text(
                horloge.message!,
                style: _texte.copyWith(
                  color: AppColors.errorDeep,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (vm.peutSynchroniser)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                key: const Key('appairage-reessayer'),
                label: vm.synchronisationEnCours
                    ? 'Synchronisation…'
                    : 'Réessayer',
                icon: Symbols.refresh,
                variant: AppButtonVariant.outline,
                onPressed: vm.occupe || vm.synchronisationEnCours
                    ? null
                    : vm.reessayer,
              ),
            ),
        ],
      ),
    );
  }
}

class _BandeauEtat extends StatelessWidget {
  const _BandeauEtat({required this.etat});

  final EtatAppairage etat;

  @override
  Widget build(BuildContext context) {
    final (fond, teinte, icone, message) = etat.appaire
        ? (
            AppColors.successContainer,
            AppColors.successDeep,
            Symbols.link,
            'Poste appairé au serveur (code ${etat.codePoste}). Pour '
                'l\'instant, seuls les CLIENTS sont synchronisés ; les autres '
                'données restent sur ce poste, branchées une à une.',
          )
        : (
            AppColors.surfaceZebra,
            AppColors.onSurface,
            Symbols.link_off,
            'Poste non appairé. Il fonctionne seul, hors ligne, avec ses '
                'comptes locaux. L\'appairage n\'est nécessaire que pour '
                'échanger des données avec le serveur web.',
          );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 22, color: teinte),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              key: const Key('appairage-bandeau'),
              style: _texte.copyWith(
                fontWeight: FontWeight.w700,
                color: teinte,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne(this.libelle, this.valeur, {this.selectionnable = false});

  final String libelle;
  final String valeur;
  final bool selectionnable;

  @override
  Widget build(BuildContext context) {
    final texte = Text(
      valeur,
      style: _texte.copyWith(fontWeight: FontWeight.w600),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(libelle.toUpperCase(), style: AppTypography.label),
          ),
          Expanded(
            child: selectionnable
                ? SelectableText(
                    valeur,
                    style: _texte.copyWith(fontWeight: FontWeight.w600),
                  )
                : texte,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.resultat});

  final ResultatAppairage resultat;

  @override
  Widget build(BuildContext context) {
    final bon = resultat.reussi || resultat.issue == IssueAppairage.deconnecte;
    final injoignable = resultat.issue == IssueAppairage.injoignable;
    final teinte = bon
        ? AppColors.successDeep
        : injoignable
        ? AppColors.onSurface
        : AppColors.errorDeep;
    final fond = bon
        ? AppColors.successContainer
        : injoignable
        ? AppColors.surfaceZebra
        : AppColors.errorContainer;
    return Container(
      key: const Key('appairage-message'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Text(
        resultat.message,
        style: _texte.copyWith(
          color: teinte,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MessageSynchro extends StatelessWidget {
  const _MessageSynchro({required this.rapport});

  final RapportSynchronisation rapport;

  @override
  Widget build(BuildContext context) {
    final bon =
        rapport.reussie &&
        rapport.refusees == 0 &&
        !rapport.envoiSuspendu &&
        !rapport.horlogeAAvertir;
    final neutre = rapport.issue == IssueSynchronisation.horsLigne;
    final teinte = bon
        ? AppColors.successDeep
        : neutre
        ? AppColors.onSurface
        : AppColors.errorDeep;
    final fond = bon
        ? AppColors.successContainer
        : neutre
        ? AppColors.surfaceZebra
        : AppColors.errorContainer;
    return Container(
      key: const Key('synchro-message'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Text(
        rapport.message,
        style: _texte.copyWith(
          color: teinte,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FormulaireAppairage extends StatefulWidget {
  const _FormulaireAppairage({required this.vm, required this.adresseInitiale});

  final AppairageViewModel vm;
  final String adresseInitiale;

  @override
  State<_FormulaireAppairage> createState() => _FormulaireAppairageState();
}

class _FormulaireAppairageState extends State<_FormulaireAppairage> {
  late final TextEditingController _adresse = TextEditingController(
    text: widget.adresseInitiale,
  );
  final TextEditingController _identifiant = TextEditingController();
  final TextEditingController _motDePasse = TextEditingController();

  @override
  void dispose() {
    _adresse.dispose();
    _identifiant.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    final saisi = _motDePasse.text;
    // Vidé AVANT l'appel : le mot de passe ne reste pas dans le champ pendant
    // que le réseau répond, ni après.
    _motDePasse.clear();
    await widget.vm.connecter(
      adresse: _adresse.text,
      identifiant: _identifiant.text,
      motDePasse: saisi,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Appairer ce poste',
      icone: Symbols.link,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Champ(
            cle: const Key('appairage-adresse'),
            libelle: 'Adresse du serveur',
            controleur: _adresse,
            indice: 'https://logialvia.exemple.bj',
          ),
          _Champ(
            cle: const Key('appairage-identifiant'),
            libelle: 'Identifiant du compte web',
            controleur: _identifiant,
          ),
          _Champ(
            cle: const Key('appairage-mot-de-passe'),
            libelle: 'Mot de passe',
            controleur: _motDePasse,
            masque: true,
            note:
                'Le mot de passe sert une seule fois et n\'est jamais '
                'conservé sur ce poste : seul un jeton révocable l\'est.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: widget.vm.occupe ? 'Connexion…' : 'Appairer',
              icon: Symbols.link,
              onPressed: widget.vm.occupe ? null : _connecter,
            ),
          ),
        ],
      ),
    );
  }
}

class _Champ extends StatelessWidget {
  const _Champ({
    required this.cle,
    required this.libelle,
    required this.controleur,
    this.indice,
    this.masque = false,
    this.note,
  });

  final Key cle;
  final String libelle;
  final TextEditingController controleur;
  final String? indice;
  final bool masque;
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
          TextField(
            key: cle,
            controller: controleur,
            obscureText: masque,
            enableSuggestions: !masque,
            autocorrect: false,
            style: _texte.copyWith(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surfaceCard,
              hintText: indice,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.cardRadius,
                borderSide: const BorderSide(color: AppColors.outlineVariant),
              ),
            ),
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

class _CarteAppaire extends StatelessWidget {
  const _CarteAppaire({required this.vm});

  final AppairageViewModel vm;

  Future<void> _deconnecter(BuildContext context) async {
    final confirme = await AppModal.show<bool>(
      context,
      title: 'Déconnecter ce poste ?',
      maxWidth: 480,
      child: Text(
        'Le jeton de synchronisation de ce poste sera effacé. Vos données '
        'locales ne sont pas touchées, mais le poste ne pourra plus échanger '
        'avec le serveur avant un nouvel appairage.',
        style: _texte.copyWith(height: 1.5),
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
            label: 'Déconnecter',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    );
    if (confirme != true || !context.mounted) return;
    await vm.deconnecter();
    if (!context.mounted) return;
    showAppToast(context, 'Poste déconnecté.');
  }

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Connexion au serveur',
      icone: Symbols.cloud_sync,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          if (vm.peutSynchroniser)
            AppButton(
              label: vm.synchronisationEnCours
                  ? 'Synchronisation…'
                  : 'Synchroniser maintenant',
              icon: Symbols.sync,
              onPressed: vm.occupe || vm.synchronisationEnCours
                  ? null
                  : vm.synchroniser,
            ),
          AppButton(
            label: vm.occupe ? 'Test en cours…' : 'Tester la connexion',
            icon: Symbols.wifi_find,
            variant: AppButtonVariant.outline,
            onPressed: vm.occupe ? null : vm.tester,
          ),
          AppButton(
            label: 'Déconnecter ce poste',
            icon: Symbols.link_off,
            variant: AppButtonVariant.outline,
            onPressed: vm.occupe ? null : () => _deconnecter(context),
          ),
        ],
      ),
    );
  }
}
