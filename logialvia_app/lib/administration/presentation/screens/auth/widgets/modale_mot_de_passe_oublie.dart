import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/app_modal.dart';

/// Modale `#modal-forgot` — login.html l.116-126.
///
/// ECART_DELIBERE, assume et documente :
/// le prototype affiche un champ e-mail et un bouton "Envoyer le lien de
/// réinitialisation" dont le seul effet reel est un toast de succes
/// (login.html l.145) — aucun envoi n'a lieu. C'est exactement le pattern
/// interdit par le Master Prompt §2.3 ("zero fonctionnalite decorative", cite
/// nommement le cas `validateSale()`), et il est structurellement impossible a
/// honorer aujourd'hui : LogiALVIA Desktop est hors-ligne par defaut, sans
/// aucun appel reseau ni configuration SMTP (Doc B1 §7, Doc I3 §3).
///
/// La modale conserve donc son titre, sa taille et sa place dans le parcours,
/// mais indique la seule procedure reellement disponible au lieu de simuler un
/// envoi.
///
/// TODO(dette): brancher un envoi reel de lien de reinitialisation le jour ou
/// la configuration e-mail de Doc F8 (Parametres Generaux) existera, et
/// restaurer alors le champ e-mail + le bouton d'envoi du prototype.
Future<void> afficherModaleMotDePasseOublie(BuildContext context) {
  return AppModal.show<void>(
    context,
    title: 'Mot de passe oublié',
    maxWidth: 384, // `max-w-sm`
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: const Text(
        'La réinitialisation d\'un mot de passe se fait auprès de '
        'l\'administratrice, depuis la gestion des utilisateurs.\n\n'
        'Aucun envoi d\'e-mail n\'est possible : LogiALVIA fonctionne '
        'entièrement hors-ligne sur ce poste.',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: AppTypography.textXs,
          height: 1.5,
          color: AppColors.outline,
        ),
      ),
    ),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Fermer',
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),
    ],
  );
}
