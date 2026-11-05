# G2 — Directives Obligatoires des Actions UI/UX

Règles impératives, sans exception, applicables à toute interaction utilisateur du système. Ce document est une checklist de conformité — toute action UI qui viole une règle ci-dessous est un défaut à corriger avant livraison, pas un détail mineur.

---

## 1. Aucune Action Destructive Sans Confirmation

**Directive** : toute action qui supprime ou annule irréversiblement une donnée DOIT passer par une modale de confirmation explicite (Doc E5 §3), jamais un simple clic direct.

**S'applique à** : suppression d'article de stock, annulation de vente, suppression d'utilisateur, clôture d'exercice (renforcée, Doc F6 Écran 6).

---

## 2. Aucune Action Silencieuse

**Directive** : toute action de sauvegarde/modification réussie DOIT produire un retour visuel explicite (`AppToast`, Doc E2 §5) — jamais une action qui se termine sans confirmation visible à l'utilisateur, qui laisserait un doute sur la réussite de l'opération.

**Corollaire** : une action qui échoue DOIT également produire un retour visuel explicite (toast d'erreur), jamais un échec silencieux.

---

## 3. Zéro Fonctionnalité Décorative (rappel du Master Prompt, reposé ici comme directive UI/UX)

**Directive** : un bouton qui affiche un message de succès DOIT avoir réellement produit l'effet annoncé (persistance en base, calcul effectué). Ce projet a directement souffert de cette violation côté prototype web (`validateSale()` générant une fausse référence sans rien persister) — corrigé, mais la vigilance reste une directive permanente pour toute nouvelle fonctionnalité développée en Dart.

---

## 4. Validation Avant Soumission, Jamais Après Coup Silencieux

**Directive** : un formulaire invalide ne doit **jamais** se soumettre silencieusement avec des valeurs par défaut ou vides. L'erreur s'affiche sous le champ concerné (Doc E6) et bloque la soumission.

---

## 5. Cohérence de Position des Éléments Interactifs

**Directive** (rappel direct de votre exigence initiale) : la position des boutons, CTA, et éléments d'action DOIT être identique à celle du prototype HTML source, écran par écran. Un bouton "Enregistrer" toujours en bas à droite d'une modale, un bouton d'action principale toujours en haut à droite d'une section — cette cohérence n'est pas une question de goût, c'est une exigence de conformité au design déjà validé.

---

## 6. Feedback Immédiat sur les Calculs en Direct

**Directive** (application UI de Doc G1 §4) : tout champ qui déclenche un calcul en aperçu (effectif projeté, total du panier) DOIT refléter le changement à chaque frappe, sans délai perceptible et sans nécessiter un clic supplémentaire hors du champ de saisie.

---

## 7. États Vides Toujours Informatifs

**Directive** (rappel de Doc E4 §1, E7 §1) : un tableau sans donnée affiche un message explicite avec, si pertinent, un bouton d'action pour créer la première entrée — jamais un espace visuellement vide sans explication. Un KPI sans donnée affiche "0" ou l'unité appropriée — jamais une carte vide.

---

## 8. Accessibilité Non Négociable sur les Composants Interactifs

**Directive** (rappel de l'audit déjà mené sur le projet jumeau AgriERP, à appliquer nativement ici plutôt qu'en correctif a posteriori) :
- Tout bouton icône-seule a un `tooltip`/label sémantique
- Toute modale est annoncée comme telle (`Semantics(container: true)`)
- Tout élément de navigation par onglet expose son état sélectionné (`Semantics(selected: ...)`)
- Le focus clavier reste visible sur tout élément interactif (jamais de `focusColor: Colors.transparent` sans alternative)

---

## 9. Un Seul Chemin pour une Même Action

**Directive** : si une action est accessible depuis 2 endroits différents de l'interface (ex : "Ajouter un Produit" depuis le Catalogue ET depuis une alerte de stock bas), les deux chemins DOIVENT appeler exactement le même `usecase`/la même modale — jamais deux implémentations parallèles qui pourraient diverger avec le temps (Strict Avoid §5, cohérence des patterns).

---

## 10. Priorité de Lecture Visuelle Cohérente avec le Prototype ("Psychologie de Conversion")

**Directive** : la hiérarchie visuelle qui guide l'œil de l'utilisateur vers l'action attendue (bouton primaire en couleur pleine navy, actions secondaires en contour, action destructive en rouge — Doc E2 §1) doit rester strictement cohérente sur les 31 écrans. Ne jamais utiliser la couleur primaire pour une action secondaire ou inversement, ce qui casserait la lecture immédiate déjà acquise par l'utilisateur habitué au prototype.
