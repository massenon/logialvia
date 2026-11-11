import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../administration/data/repositories/parametres_repository_drift.dart';
import '../../administration/presentation/viewmodels/auth_view_model.dart';
import '../database/app_database.dart';
import '../theme/app_colors.dart';
import '../resultat/resultat.dart';
import '../widgets/app_button.dart';
import '../widgets/app_toast.dart';
import 'document_pdf.dart';
import 'service_impression.dart';

/// Bouton « Exporter PDF » — Doc E9 §4, présent sur 24 écrans du prototype.
///
/// Un seul widget pour tous : il construit l'en-tête officielle depuis les
/// paramètres d'entreprise et la session réellement ouverte, puis passe le
/// [DocumentPdf] au générateur unique. Aucun écran ne compose son en-tête ni ne
/// touche au paquet `pdf`.
class BoutonExportPdf extends StatefulWidget {
  const BoutonExportPdf({
    super.key,
    required this.construire,
    this.libelle = 'Exporter PDF',
    this.variante = AppButtonVariant.outline,
  });

  /// Construit le document au moment du clic, jamais à l'avance : il doit
  /// refléter les filtres et la période en vigueur à cet instant.
  final DocumentPdf Function() construire;

  final String libelle;
  final AppButtonVariant variante;

  @override
  State<BoutonExportPdf> createState() => _BoutonExportPdfState();
}

class _BoutonExportPdfState extends State<BoutonExportPdf> {
  bool _enCours = false;

  Future<void> _exporter() async {
    setState(() => _enCours = true);

    final entete = await enteteOfficielle(context);
    if (!mounted) return;

    final resultat = await const ServiceImpression().imprimer(
      widget.construire(),
      entete: entete,
    );

    if (!mounted) return;
    setState(() => _enCours = false);

    if (resultat case Echec(:final message)) {
      showAppToast(context, message, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: _enCours ? 'Préparation…' : widget.libelle,
      icon: Symbols.picture_as_pdf,
      variant: widget.variante,
      onPressed: _enCours ? null : _exporter,
    );
  }
}

/// Variante compacte du bouton d'export, pour une **cellule de tableau**.
///
/// `rapports-exports.html` l.640 place deux icones dans la colonne Actions de
/// chaque creance ; un bouton pleine largeur y serait hors d'echelle. Le
/// mecanisme est le meme — meme en-tete officielle, meme generateur unique.
class IconeExportPdf extends StatefulWidget {
  const IconeExportPdf({
    super.key,
    required this.construire,
    required this.icone,
    required this.infobulle,
    this.couleur,
  });

  final DocumentPdf Function() construire;
  final IconData icone;
  final String infobulle;
  final Color? couleur;

  @override
  State<IconeExportPdf> createState() => _IconeExportPdfState();
}

class _IconeExportPdfState extends State<IconeExportPdf> {
  bool _enCours = false;

  Future<void> _exporter() async {
    setState(() => _enCours = true);
    final entete = await enteteOfficielle(context);
    if (!mounted) return;

    final resultat = await const ServiceImpression().imprimer(
      widget.construire(),
      entete: entete,
    );
    if (!mounted) return;
    setState(() => _enCours = false);

    if (resultat case Echec(:final message)) {
      showAppToast(context, message, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _enCours
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(widget.icone, size: 16),
      color: widget.couleur ?? AppColors.brandNavy,
      tooltip: widget.infobulle,
      visualDensity: VisualDensity.compact,
      onPressed: _enCours ? null : _exporter,
    );
  }
}

/// Compose l'en-tête officielle depuis les données réelles.
///
/// Le prototype écrit « Gérante : SIDI ALI Raïmatou » et « Généré par :
/// Administratrice » **en dur** dans son générateur : un document imprimé par
/// l'Agent de Vente porterait quand même la mention « Administratrice ». Sur un
/// état signé, c'est une fausse attribution.
Future<EnteteOfficielle> enteteOfficielle(BuildContext context) async {
  final session = context.read<AuthViewModel>().session;
  final parametres = await ParametresRepositoryDrift(
    context.read<AppDatabase>(),
  ).charger();

  final generePar = session == null
      ? '—'
      : '${session.utilisateur.nom} (${session.utilisateur.identifiant}) — '
            '${session.role.libelle}';

  return EnteteOfficielle(
    raisonSociale: parametres.raisonSociale,
    promoteur: parametres.nomPromoteur,
    adresse: parametres.adresseSiege,
    generePar: generePar,
    ifu: parametres.ifu,
    rccm: parametres.rccm,
  );
}
