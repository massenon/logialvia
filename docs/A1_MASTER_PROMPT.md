# A1 — MASTER PROMPT — Instructions Fondamentales du Projet LogiALVIA Flutter

Ce document est la **référence de premier niveau**. Tout autre document de cette série (B à K) doit être lu comme une application concrète des règles posées ici. En cas de conflit apparent entre deux documents, ce Master Prompt prévaut.

---

## 1. Contexte du Projet

**LogiALVIA** est l'outil de gestion intégrée d'ALLMANY ET COMPAGNIE (Natitingou, Bénin), une exploitation avicole/pisciculture/cuniculture avec activité commerciale annexe (fournitures scolaires, textile). Le prototype HTML/Tailwind/JavaScript vanille (31 écrans, validé, fonctionnel de bout en bout — POS→Stock→Historique→Fiches d'élevage communiquant réellement via une couche de synchronisation `localStorage`) constitue la **référence de vérité absolue** pour la conversion Flutter Desktop.

**Ce projet n'est pas une refonte.** C'est une traduction technique fidèle d'un système déjà pensé, déjà testé, déjà corrigé. Toute tentation d'"améliorer" une mise en page, un flux, un libellé pendant la conversion est une déviation du mandat, sauf demande explicite.

---

## 2. Rôle Attendu de l'Agent (Claude Code ou équivalent) sur ce Projet

1. **Traducteur fidèle, pas concepteur.** La conception visuelle et fonctionnelle est déjà faite et validée dans le prototype HTML. Le rôle est de la porter en Dart/Flutter à l'identique — page, structure, ordre des sections, espacements, conteneurs, hiérarchie typographique, position des boutons, emplacement des images, emplacement des CTA, animations, KPI, structure des DataTables, comportement responsive, structure HTML/CSS transposée en widgets.
2. **Zéro écran vide.** Un écran converti qui affiche une structure sans données réelles (mock ou persistées) est un échec de livraison, pas un travail partiel acceptable.
3. **Zéro fonctionnalité décorative.** Un bouton qui affiche un toast de succès sans réellement écrire en base est un bug, au même titre qu'une erreur de compilation. Ce projet a déjà souffert de ce pattern côté web (`validateSale()` qui générait une référence aléatoire sans rien persister) — **ne jamais le reproduire côté Flutter**.
4. **Validation avant livraison, systématiquement.** Chaque fichier Dart produit doit être vérifié (`flutter analyze` au minimum, idéalement `flutter test` si des tests existent pour la portion concernée) avant d'être présenté comme terminé. Un fichier "écrit mais non vérifié" doit être explicitement signalé comme tel, jamais présenté avec la même confiance qu'un fichier validé.

---

## 3. Méthodologie de Travail

### 3.1 Ordre de Référence pour Toute Nouvelle Tâche
1. Consulter le document de spécification du module concerné (section F)
2. Consulter la fiche fonctionnelle de l'onglet concerné si applicable (section H)
3. Consulter le Design System (section E) pour toute question de style
4. Consulter le modèle de données (section D) pour toute question de persistance
5. Consulter la logique de calcul (Doc 05, réintégré en section F pour les fiches d'élevage) pour toute formule
6. **Ne jamais halluciner une valeur, une couleur, un libellé, une formule** — si l'information n'est dans aucun document ni dans le HTML source, le signaler et demander, ne pas inventer une valeur plausible.

### 3.2 Cycle de Développement par Écran
```
1. Lire le fichier HTML source correspondant (correspondance exacte en F0)
2. Identifier tous les composants reutilisables applicables (section E)
3. Construire le Widget Screen + son ViewModel (ChangeNotifier)
4. Brancher la persistance reelle (jamais de donnees mock statiques une fois
   le Repository disponible)
5. Verifier chaque interaction (clic, saisie, validation) contre le
   comportement JS original — reproduire fidelement, pas "ameliorer"
6. flutter analyze — corriger tout avertissement avant de continuer
7. Confronter visuellement au HTML source (capture d'ecran cote a cote
   recommandee) — voir K2 Checklist de Recette Visuelle
```

### 3.3 Gestion des Écarts Techniques Inévitables
Certains éléments HTML n'ont pas d'équivalent Flutter strictement identique (`<select>` natif vs `DropdownButton`, `<input type="date">` vs `showDatePicker`). Dans ces cas :
- Reproduire l'**intention visuelle et fonctionnelle** le plus fidèlement possible
- Documenter l'écart dans le fichier concerné via un commentaire `// ECART_DELIBERE:` expliquant pourquoi
- Ne jamais silencieusement diverger sans commentaire

---

## 4. Règles de Qualité — Non Négociables

| Règle | Application concrète |
|---|---|
| Aucun code dupliqué | Tout pattern visuel répété sur 2+ écrans devient un composant dans `core/widgets/` (section E2) avant d'être utilisé une 2ᵉ fois |
| Variables réutilisées | Constantes de couleur/espacement/typographie centralisées (section E1) — jamais de valeur hexadécimale ou numérique en dur dans un widget d'écran |
| Composants réutilisables | Voir E2 — la bibliothèque existe, elle doit être utilisée, pas recréée ad hoc |
| Architecture claire | Respect strict des 3 couches (section C) — aucune logique métier dans `presentation/`, aucun widget Flutter dans `domain/` |
| Commentaires utiles | Un commentaire explique le **pourquoi** (une règle métier, un écart délibéré, un piège déjà rencontré), jamais le **quoi** évident (`// increment i` sur `i++` est interdit, inutile) |

---

## 5. Contraintes Globales du Projet

- **Plateforme cible** : Flutter Desktop, Windows en priorité
- **Persistance** : locale (SQLite via Drift), pas de backend serveur pour cette phase — miroir exact de l'architecture `localStorage` déjà en place côté web
- **Hors-ligne first** : aucune dépendance réseau obligatoire au fonctionnement (police embarquée, pas de CDN)
- **Langue** : Français, intégralement — aucun libellé anglais dans l'interface utilisateur finale (les noms de variables/fonctions Dart restent en anglais par convention du langage, mais tout texte affiché à l'utilisateur est en français, fidèle au prototype)
- **Devise** : Franc CFA (FCFA), formatage `fr-FR` pour les séparateurs de milliers, jamais de symbole `$` ou `€`

---

## 6. Document Complémentaire Obligatoire

Voir `A2_STRICT_AVOID.md` pour la liste des anti-patterns formellement interdits sur ce projet, avec le mécanisme de contrôle associé à chacun.
