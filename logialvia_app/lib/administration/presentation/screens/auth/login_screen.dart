import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/marque_logialvia.dart';
import '../../viewmodels/auth_view_model.dart';
import 'widgets/banniere_verrouillage.dart';
import 'widgets/champ_connexion.dart';
import 'widgets/modale_mot_de_passe_oublie.dart';

/// Ecran 3 du module Authentification — Doc F1, fidele a `login.html`.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Largeur a partir de laquelle le visuel de marque apparait (`lg` = 1024 px, comme le web).
  static const double _largeurDeuxVolets = 1024;

  static const String _visuelConnexion = 'assets/images/login_visuel.webp';

  final _identifiantController = TextEditingController();
  final _motDePasseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _afficherMessageDiffere();
      _preremplirIdentifiant();
    });
  }

  /// « Se souvenir de moi » — le champ identifiant est pré-rempli si la
  /// dernière connexion réussie l'avait demandé.
  ///
  /// Le mot de passe reste exigé : la case ne rouvre pas la session, elle
  /// évite de retaper qui l'on est. Voir `PreferencesPosteRepository`.
  Future<void> _preremplirIdentifiant() async {
    final vm = context.read<AuthViewModel>();
    await vm.chargerPreferencesConnexion();
    if (!mounted) return;
    final memorise = vm.identifiantMemorise;
    if (memorise != null && _identifiantController.text.isEmpty) {
      _identifiantController.text = memorise;
      // Le curseur va au mot de passe : c'est le seul champ qui reste a
      // remplir.
      _focusMotDePasse.requestFocus();
    }
  }

  final FocusNode _focusMotDePasse = FocusNode();

  /// Toast de deconnexion, affiche a l'arrivee sur l'ecran apres un delai de
  /// 300 ms — login.html l.219.
  Future<void> _afficherMessageDiffere() async {
    final message = context.read<AuthViewModel>().consommerMessageDiffere();
    if (message == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    showAppToast(context, message);
  }

  @override
  void dispose() {
    _identifiantController.dispose();
    _motDePasseController.dispose();
    _focusMotDePasse.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    final vm = context.read<AuthViewModel>();
    final reponse = await vm.seConnecter(
      identifiant: _identifiantController.text,
      motDePasse: _motDePasseController.text,
    );
    if (!mounted) return;

    final message = reponse.messageToast;
    if (message != null) {
      showAppToast(
        context,
        message,
        type: reponse.issue == IssueConnexion.succes
            ? ToastType.success
            : ToastType.error,
      );
    }

    if (reponse.issue != IssueConnexion.succes) return;

    // Le prototype laisse le toast de succes visible 700 ms avant de naviguer
    // (login.html l.184).
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();

    return Scaffold(
      backgroundColor: AppColors.surfaceCard,
      // Connexion en deux volets (maquette `login`, web et poste) : visuel de marque a gauche sur grand ecran,
      // formulaire a droite ; le bandeau d'icones de modules a ete retire.
      body: LayoutBuilder(
        builder: (context, contraintes) {
          final large = contraintes.maxWidth >= _largeurDeuxVolets;
          final formulaire = Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(large ? 48 : 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _BarreLangueVersion(),
                    const SizedBox(height: 16), // `mb-4`
                    const _EnTeteMarque(),
                    const SizedBox(height: 32), // `space-y-8`
                    const _Accroche(),
                    if (vm.verrouille) ...[
                      const SizedBox(height: 20),
                      BanniereVerrouillage(
                        libelleCompteARebours: vm.libelleVerrouillage,
                      ),
                    ],
                    const SizedBox(height: 32),
                    _formulaire(vm),
                    const SizedBox(height: 24), // `mt-6`
                    const Divider(height: 1),
                    const SizedBox(height: 16), // `pt-4`
                    const _PiedDePage(),
                  ],
                ),
              ),
            ),
          );
          if (!large) return formulaire;

          // Largeur = min(moitie de la fenetre, hauteur) : le visuel (carre) s'affiche ENTIER, sans rogner ses textes ;
          // si la moitie est plus etroite que la hauteur, il est centre sur le fond marine.
          final largeurVisuel = math.min(
            contraintes.maxWidth / 2,
            contraintes.maxHeight,
          );

          return Row(
            children: [
              SizedBox(
                width: largeurVisuel,
                height: double.infinity,
                child: ColoredBox(
                  color: AppColors.brandNavyDark,
                  child: Image.asset(
                    _visuelConnexion,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
              Expanded(child: formulaire),
            ],
          );
        },
      ),
    );
  }

  Widget _formulaire(AuthViewModel vm) {
    final actionsBloquees = vm.verrouille || vm.connexionEnCours;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChampConnexion(
          label: 'NOM D\'UTILISATEUR OU EMAIL',
          controller: _identifiantController,
          iconePrefixe: Symbols.person,
          // DECISION CLIENT (2026-11-11) : aucun identifiant ni mot de passe suggere (ni `admin`, ni le
          // mot de passe initial) ; le texte guide seulement.
          placeholder: 'Entrez votre nom d\'utilisateur',
          erreur: vm.erreurIdentifiant,
          autofocus: true,
        ),
        const SizedBox(height: 16), // `space-y-4`
        ChampConnexion(
          label: 'MOT DE PASSE',
          controller: _motDePasseController,
          focusNode: _focusMotDePasse,
          iconePrefixe: Symbols.lock,
          placeholder: 'Entrez votre mot de passe',
          erreur: vm.erreurMotDePasse,
          masque: vm.motDePasseMasque,
          onSubmitted: actionsBloquees ? null : (_) => _soumettre(),
          suffixe: IconButton(
            onPressed: vm.basculerVisibiliteMotDePasse,
            icon: Icon(
              vm.motDePasseMasque ? Symbols.visibility : Symbols.visibility_off,
              size: 18,
              color: AppColors.outline,
            ),
            tooltip: vm.motDePasseMasque
                ? 'Afficher le mot de passe'
                : 'Masquer le mot de passe',
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: 16),
        _optionsSecondaires(vm),
        const SizedBox(height: 16),
        AppButton(
          label: 'Se connecter',
          icon: Symbols.lock_open,
          fullWidth: true,
          height: 44, // `h-11`
          uppercase: true,
          letterSpacing: 0.6, // `tracking-wider`
          fontSize: AppTypography.textXs,
          onPressed: actionsBloquees ? null : _soumettre,
        ),
      ],
    );
  }

  Widget _optionsSecondaires(AuthViewModel vm) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        InkWell(
          onTap: () => vm.definirSeSouvenirDeMoi(!vm.seSouvenirDeMoi),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16, // `h-4 w-4`
                height: 16,
                child: Checkbox(
                  value: vm.seSouvenirDeMoi,
                  onChanged: (valeur) =>
                      vm.definirSeSouvenirDeMoi(valeur ?? false),
                  activeColor: AppColors.brandNavy,
                  side: const BorderSide(color: AppColors.outlineVariant),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8), // `ml-2`
              const Text(
                'Se souvenir de moi',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: AppTypography.textXs,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => afficherModaleMotDePasseOublie(context),
          child: const Text(
            'Mot de passe oublié ?',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: AppTypography.textXs,
              fontWeight: FontWeight.w600,
              color: AppColors.brandNavy,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarreLangueVersion extends StatelessWidget {
  const _BarreLangueVersion();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: AppTypography.textXs,
      color: AppColors.outline,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12, // `px-3`
            vertical: 6, // `py-1.5`
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.outlineVariant),
            borderRadius: AppRadius.pill,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.translate, size: 16, color: AppColors.outline),
              SizedBox(width: 4), // `gap-1`
              Text('Français', style: style),
            ],
          ),
        ),
        const SizedBox(width: 8), // `gap-2`
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8), // `px-2`
          child: Text(
            'v1.0.0',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: AppTypography.textXs,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6, // `tracking-wider`
              color: AppColors.outline,
            ),
          ),
        ),
      ],
    );
  }
}

class _EnTeteMarque extends StatelessWidget {
  const _EnTeteMarque();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.egg, size: 38, color: AppColors.brandNavy),
            SizedBox(width: 8), // `gap-2`
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MarqueLogiAlvia(
                  fontSize: 22,
                  fontWeight: FontWeight.w900, // `font-black`
                  couleurBase: AppColors.brandNavy,
                  letterSpacing: -0.5, // `tracking-tight`
                  height: 1, // `leading-none`
                ),
                SizedBox(height: 2), // `mt-0.5`
                Text(
                  'ALLMANY ET COMPAGNIE',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9, // `tracking-widest`
                    color: AppColors.brandNavy,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4), // `gap-1`
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 4), // `pt-1`
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: AppColors.brandNavy.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: const Text(
            'GESTION ET SUIVI AVICOLE INTÉGRÉ',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 12 * 0.15, // `tracking-[0.15em]`
              color: AppColors.brandNavy,
            ),
          ),
        ),
      ],
    );
  }
}

class _Accroche extends StatelessWidget {
  const _Accroche();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bienvenue !',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 20, // `text-xl`
            fontWeight: FontWeight.w700,
            height: 1.25, // `leading-tight`
            color: AppColors.brandNavy,
          ),
        ),
        Text(
          'Connectez-vous à votre espace LogiALVIA.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: AppTypography.textXs,
            color: AppColors.outline,
          ),
        ),
      ],
    );
  }
}

class _PiedDePage extends StatelessWidget {
  const _PiedDePage();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '© 2026 LogiAgriERP — (PAEB)/Cabinet FAGUEZ SARL '
      '— Conçu par Dr MASSENON Rhodes',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 12,
        color: AppColors.outline,
      ),
    );
  }
}
