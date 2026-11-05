# A2 — STRICT_AVOID — Anti-Patterns Interdits & Mécanismes de Contrôle

Chaque point ci-dessous est accompagné d'un **mécanisme de contrôle concret**, applicable à ce projet précis — pas un conseil générique. Un point sans mécanisme de vérification associé n'est qu'une intention, pas une règle.

---

## 1. Vulnérabilités de Sécurité

**Risque concret sur ce projet** : base SQLite locale contenant des données sensibles (chiffre d'affaires, créances clients, salaires si le module RH est un jour porté) sans chiffrement au repos ; champs de saisie sans validation d'entrée exposant à des injections SQL si des requêtes brutes sont un jour utilisées.

**Contrôle** :
- Utiliser exclusivement l'API typée de Drift (`select()`, `insert()`, `update()`) — **jamais** de `customSelect()` avec concaténation de chaîne pour construire une requête SQL
- Si un chiffrement de la base devient nécessaire (données financières), évaluer `sqlcipher_flutter_libs` avant la mise en production, pas après
- Toute entrée utilisateur affichée ailleurs (ex : nom de client dans une facture PDF) doit être échappée par les mécanismes natifs Flutter (`Text()` échappe déjà par défaut — ne jamais utiliser `HtmlWidget`/rendu HTML brut sur une donnée utilisateur)

---

## 2. Bugs Cachés et Cas Limites

**Risque concret déjà rencontré sur ce projet** (côté web, corrigé) : le bug SRH/TS de la fiche Pondeuses (Doc 05) était un cas limite silencieux — fonctionnait pour les jours sans sortie de plateaux, cassait sans erreur visible les jours avec sortie.

**Contrôle** :
- Toute fonction de calcul (Doc 05) doit être accompagnée d'un test unitaire couvrant explicitement le cas limite qui a historiquement cassé (`stock initial = 0`, `mortalité = effectif total`, `vente > stock disponible`)
- Règle systématique : avant de considérer une fonction de calcul "terminée", tracer manuellement 3 à 5 jours consécutifs avec des valeurs réelles et vérifier la cohérence ligne par ligne (méthode qui a permis de détecter le bug SRH originellement)

---

## 3. Code Spaghetti / Architecture Pauvre

**Contrôle** : application stricte des 3 couches du Doc C1 (Architecture). Un `ViewModel` qui appelle directement Drift sans passer par un `Repository`, ou un widget qui contient une formule de calcul métier au lieu d'appeler un `usecase`, est un manquement à corriger avant merge — pas une dette acceptable "pour l'instant".

---

## 4. Dette Technique qui s'Accumule

**Contrôle** : tout écart délibéré (Master Prompt §3.3) ou compromis temporaire doit être marqué `// TODO(dette):` avec une description du correctif futur — **jamais** un TODO silencieux perdu dans le code. Un grep périodique sur `TODO(dette)` donne une vue exacte de la dette réelle, pas une impression.

---

## 5. Patterns de Code Incohérents

**Risque concret** : ce projet a 5 fiches d'élevage très similaires (Goliaths/Pintades/Lapins/Poulets/Poissons-Chats) — le risque naturel est que chacune soit codée légèrement différemment au fil du temps (nommage de variable, structure de fichier).

**Contrôle** : les 5 fiches doivent utiliser **le même patron de classe de base** (ex : `FicheEspeceScreenBase` abstraite dont chaque fiche hérite, ou un unique `FicheEspeceScreen` générique paramétré par une configuration d'espèce) plutôt que 5 implémentations indépendantes qui divergent. Voir Doc F pour la spécification détaillée de ce patron.

---

## 6. Absence de Tests Automatisés

**Contrôle minimal non négociable pour ce projet** :
- **100% des fonctions de `domain/usecases/` liées au calcul** (Doc 05) doivent avoir un test unitaire — c'est la logique la plus critique et la plus silencieusement cassable du projet
- Les `Repository` de `data/` doivent avoir au moins un test d'intégration par méthode CRUD (base SQLite en mémoire pour les tests, via `NativeDatabase.memory()` de Drift)
- Les écrans (`presentation/`) : tests de widget de base a minima pour les DataTables (rendu correct avec 0 ligne, 1 ligne, N lignes — voir Doc E4)

---

## 7. Documentation Manquante ou Obsolète

**Contrôle** : cette série de documents (A à K) doit être mise à jour **au moment où un écart est découvert**, pas en fin de projet. Si un développeur code un écran et constate que la spécification F correspondante était fausse ou incomplète, corriger le document immédiatement, dans le même commit que le code.

---

## 8. Goulots d'Étranglement de Performance

**Risque concret sur ce projet** : les tableaux mensuels de 31 jours (fiches d'élevage) et les DataTables de l'historique des ventes peuvent grossir avec l'usage réel — un `ListView` non virtualisé ou une requête Drift sans pagination deviendrait lent après plusieurs mois d'utilisation réelle.

**Contrôle** :
- Toute liste potentiellement longue (Historique des Ventes, Journal Comptable) utilise `ListView.builder` (rendu paresseux), jamais `Column` avec une liste de widgets construite en mémoire d'un coup
- Les requêtes Drift sur des tables à croissance illimitée (Ventes, LignesVente) doivent supporter une pagination (`.limit()`) dès la première implémentation, pas ajoutée après coup quand la lenteur devient perceptible

---

## 9. Conflits de Dépendances / Versions

**Contrôle** : `pubspec.lock` **doit être commité** dans le dépôt (contrairement à la pratique courante pour les packages publiés, une application n'est pas un package — le lock file garantit une reproduction exacte de l'environnement). Toute mise à jour de dépendance passe par `flutter pub upgrade --major-versions` suivi d'un `flutter analyze` + `flutter test` complet avant merge, jamais une mise à jour isolée d'un seul package sans revalidation globale.

---

## 10. Implémentations Hallucinées ou Incorrectes

**Mécanisme de contrôle spécifique à ce projet, déjà appliqué avec rigueur dans les documents précédents** :
- Toute valeur (couleur, formule, libellé, structure de donnée) doit être traçable à une source réelle : le fichier HTML/JS du prototype, ou un document de cette série déjà validé
- Si une information manque réellement (ex : contenu non chargé de `sidebar.js` dans une session de travail antérieure), la règle est de **le dire explicitement**, jamais de "combler" par une supposition plausible présentée avec la même confiance qu'une donnée vérifiée
- Avant toute livraison de code Dart non compilé/non vérifié (contrainte d'environnement documentée en A1), le signaler clairement — ne jamais présenter du code non testé comme équivalent à du code validé

---

## 11. Débogage et Maintenance Difficiles

**Contrôle** : chaque `Repository` et `usecase` doit avoir des noms de méthode qui décrivent l'action métier, pas l'implémentation technique (`enregistrerVente()`, pas `insertRowVentes()`). Un développeur qui doit déboguer un problème de vente doit pouvoir suivre le code sans deviner où chercher.

---

## 12. Code Dupliqué ou Mort

**Contrôle** :
- `flutter analyze` avec la règle `unused_element` activée dans `analysis_options.yaml` détecte le code mort automatiquement — à faire tourner avant chaque livraison
- Toute duplication de plus de 5 lignes identiques (ou quasi-identiques) entre 2 fichiers doit être extraite en fonction/widget partagé avant merge — pas "on verra plus tard"

---

## 13. Secrets / Clés API Committés Accidentellement

**Risque réel même pour une app locale sans backend** : si une clé d'API tierce est un jour ajoutée (ex : service SMS pour les relances clients, passerelle Mobile Money), elle ne doit **jamais** apparaître en dur dans le code source.

**Contrôle** :
- `.gitignore` doit exclure tout fichier `*.env`, `secrets.dart` dès l'initialisation du projet (Doc K3 Setup), avant le premier commit contenant une clé
- Utiliser `flutter_dotenv` ou équivalent pour toute clé future, jamais une constante Dart en dur

---

## 14. Conflits de Fusion et Problèmes d'Intégration

**Contrôle** : la correspondance 1:1 stricte entre fichiers HTML et écrans Dart (Doc F0) signifie que **chaque écran est un périmètre de fichier isolé** — deux développeurs travaillant sur 2 écrans différents ne touchent jamais les mêmes fichiers, sauf modification d'un composant partagé (section E), qui doit alors être coordonnée explicitement (annonce avant modification, pas de surprise en review).

---

## 15. Mauvaise Scalabilité à Mesure que les Fonctionnalités Grandissent

**Contrôle** : le patron générique évoqué au point 5 (une seule classe paramétrée pour les 5 fiches d'élevage plutôt que 5 implémentations séparées) est directement un choix de scalabilité — ajouter une 6ᵉ espèce à l'avenir (ex : si l'aviculture s'étend) doit être une question de configuration, pas de duplication d'un écran entier.

---

## Résumé — mécanisme de revue

Avant toute livraison considérée "terminée" sur ce projet, vérifier cette checklist des 15 points ci-dessus n'a **aucune case ignorée sans justification écrite**. Une case ignorée sans justification est un signal d'alerte, pas un détail.
