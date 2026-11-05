import 'package:flutter/widgets.dart';

/// # Moteur de visite guidée — `common.js` §16
///
/// Le prototype décrit un « moteur générique réutilisable sur n'importe quelle
/// page. Chaque page définit son propre scénario dans `window.TOUR_STEPS`
/// (tableau d'étapes `{ selector, title, text }`). Le bouton d'aide flottant
/// appelle `startTourGuide()` au clic. **Si aucun scénario n'est défini pour la
/// page courante, un message honnête est affiché plutôt que de simuler un tour
/// vide.** »
///
/// Cette dernière phrase est la seule ligne du prototype qui énonce d'elle-même
/// la règle « zéro fonctionnalité décorative ». Elle est respectée telle quelle.
///
/// ## Ce qui remplace le sélecteur CSS
///
/// `document.querySelector('#kpi-panel')` n'a pas d'équivalent dans un arbre de
/// widgets. Une étape désigne donc sa cible par un **nom**, et l'écran entoure
/// le widget correspondant d'une [CibleTour] portant ce nom. Le registre fait
/// le lien, et il se vide quand l'écran est démonté — exactement comme un
/// sélecteur cesse de correspondre quand le nœud quitte le DOM.
///
/// Conséquence identique au web : `startTourGuide()` **filtre** les étapes dont
/// la cible est absente. Une étape qui vise un panneau replié ou un onglet non
/// ouvert est sautée, elle ne bloque pas la visite.
class EtapeTour {
  const EtapeTour({
    required this.cible,
    required this.titre,
    required this.texte,
    this.detail,
  });

  /// Nom de la [CibleTour] à mettre en surbrillance — équivalent du `selector`.
  final String cible;

  final String titre;

  /// Le texte de la bulle, à l'écran. Deux phrases au plus : c'est un rappel,
  /// pas une explication.
  final String texte;

  /// Complément **réservé au manuel d'utilisation**, ignoré à l'écran.
  ///
  /// Une bulle de visite guidée et un paragraphe de manuel n'ont pas le même
  /// format : la première doit tenir en deux phrases, le second doit expliquer
  /// les règles de gestion, ce qui est calculé plutôt que saisi, et les pièges.
  ///
  /// Les écrire dans deux fichiers séparés garantirait qu'ils divergent. Ils
  /// vivent donc côte à côte, et c'est le générateur du manuel qui décide
  /// lequel il consomme.
  final String? detail;
}

/// Registre des cibles montées, alimenté par [CibleTour].
///
/// Volontairement statique : une cible doit pouvoir être déclarée n'importe où
/// dans l'arbre sans que l'écran ait à remonter une clé jusqu'à la coquille.
/// C'est le pendant du DOM global qu'interroge `querySelector`.
class RegistreTour {
  RegistreTour._();

  static final Map<String, GlobalKey> _cibles = {};

  static void enregistrer(String nom, GlobalKey cle) => _cibles[nom] = cle;

  static void retirer(String nom, GlobalKey cle) {
    // On ne retire que si la cle est encore celle enregistree : lors d'un
    // remplacement d'ecran, le `initState` du nouveau peut passer avant le
    // `dispose` de l'ancien. Retirer sans verifier effacerait la cible qui
    // vient d'arriver.
    if (_cibles[nom] == cle) _cibles.remove(nom);
  }

  /// La cible si elle est **réellement affichée**. Une clé enregistrée dont le
  /// contexte n'est plus monté ne compte pas.
  static RenderBox? rendu(String nom) {
    final contexte = _cibles[nom]?.currentContext;
    if (contexte == null || !contexte.mounted) return null;
    final rendu = contexte.findRenderObject();
    return rendu is RenderBox && rendu.hasSize ? rendu : null;
  }

  static bool existe(String nom) => rendu(nom) != null;

  /// Utilisé par les tests : le registre est un état global de processus.
  @visibleForTesting
  static void vider() => _cibles.clear();
}

/// Entoure le widget que la visite doit mettre en surbrillance.
///
/// N'ajoute **aucun** rendu : ni marge, ni décoration, ni contrainte. Le
/// surlignage est peint par la superposition, au-dessus de l'écran.
class CibleTour extends StatefulWidget {
  const CibleTour({super.key, required this.nom, required this.child});

  final String nom;
  final Widget child;

  @override
  State<CibleTour> createState() => _CibleTourState();
}

class _CibleTourState extends State<CibleTour> {
  final GlobalKey _cle = GlobalKey();

  @override
  void initState() {
    super.initState();
    RegistreTour.enregistrer(widget.nom, _cle);
  }

  @override
  void didUpdateWidget(CibleTour ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.nom != widget.nom) {
      RegistreTour.retirer(ancien.nom, _cle);
      RegistreTour.enregistrer(widget.nom, _cle);
    }
  }

  @override
  void dispose() {
    RegistreTour.retirer(widget.nom, _cle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _cle, child: widget.child);
}
