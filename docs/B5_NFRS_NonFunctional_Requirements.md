# B5 — NFRS — Non-Functional Requirements Specification

Chaque exigence non-fonctionnelle est assortie d'un critère mesurable — une exigence non-fonctionnelle sans seuil chiffré n'est pas vérifiable et n'a pas sa place ici.

---

## 1. Performance

| ID | Exigence | Seuil mesurable |
|---|---|---|
| NFRS-PERF-01 | Temps de chargement d'un écran depuis la navigation | < 300ms perçu (pas de latence visible entre le clic de menu et l'affichage) |
| NFRS-PERF-02 | Temps de réponse d'une requête de lecture sur l'historique des ventes (jusqu'à 5000 lignes) | < 500ms |
| NFRS-PERF-03 | Temps de validation d'une vente (transaction complète FRS-VTE-03) | < 200ms |
| NFRS-PERF-04 | Rendu d'une DataTable de 1000 lignes | Sans gel perceptible de l'interface (pagination ou virtualisation obligatoire, Strict Avoid §8) |

## 2. Fiabilité

| ID | Exigence | Seuil mesurable |
|---|---|---|
| NFRS-FIAB-01 | Intégrité des calculs de la fiche journalière (Doc 05) | 0 écart toléré sur les cas de test tracés manuellement (jeu de test de référence à constituer à partir des 9 jours déjà validés côté web pour la fiche Pondeuses) |
| NFRS-FIAB-02 | Atomicité de la transaction de vente | 0 état intermédiaire observable en cas d'interruption (coupure de courant, fermeture forcée) — soit la vente est complète, soit aucune trace n'est laissée |
| NFRS-FIAB-03 | Perte de données en cas de fermeture inattendue de l'application | 0 perte de données déjà validées par l'utilisateur (chaque saisie confirmée est persistée immédiatement, pas en mémoire tampon uniquement) |

## 3. Utilisabilité

| ID | Exigence | Seuil mesurable |
|---|---|---|
| NFRS_UTIL-01 | Temps de prise en main pour un utilisateur déjà familier du prototype HTML | < 15 minutes (contrainte directement liée à la fidélité visuelle exigée — Master Prompt) |
| NFRS-UTIL-02 | Nombre de clics pour atteindre n'importe quelle fonctionnalité depuis l'écran d'accueil | ≤ 3 clics (règle héritée du prototype de référence) |
| NFRS-UTIL-03 | Lisibilité en environnement lumineux extérieur (contexte agricole, écran potentiellement consulté hors bâtiment) | Contraste minimum conforme WCAG 2.2 AA (ratio 4.5:1 texte normal, cohérent avec l'audit déjà mené sur le projet AgriERP jumeau) |

## 4. Sécurité

| ID | Exigence | Seuil mesurable |
|---|---|---|
| NFRS-SEC-01 | Accès aux écrans selon le rôle connecté | 0 accès non autorisé possible en navigation directe (contournement de menu) — voir FRS-ADM-01 |
| NFRS-SEC-02 | Protection contre l'injection SQL | 0 requête construite par concaténation de chaîne — API typée Drift exclusivement (Strict Avoid §1) |
| NFRS-SEC-03 | Aucun secret/clé en dur dans le code source | 0 occurrence détectable par recherche statique avant chaque livraison (Strict Avoid §13) |

## 5. Maintenabilité

| ID | Exigence | Seuil mesurable |
|---|---|---|
| NFRS-MAINT-01 | Couverture de test des fonctions de calcul métier (Doc 05) | 100% des `usecases/` de calcul, conformément à Strict Avoid §6 |
| NFRS-MAINT-02 | Duplication de code | 0 bloc de plus de 5 lignes dupliqué entre 2 fichiers sans extraction en composant partagé (Strict Avoid §12) |
| NFRS-MAINT-03 | Avertissements `flutter analyze` | 0 avertissement non justifié en commentaire avant toute livraison |

## 6. Portabilité

| ID | Exigence | Seuil mesurable |
|---|---|---|
| NFRS-PORT-01 | Plateforme cible principale | Windows 10/11 64-bit, fonctionnement vérifié sans dépendance à une version spécifique au-delà du strict minimum documenté (Doc K3 Setup) |
| NFRS-PORT-02 | Fonctionnement hors-ligne | 100% des fonctionnalités du périmètre (B1 §5) opérationnelles sans connexion réseau |

## 7. Scalabilité

| ID | Exigence | Seuil mesurable |
|---|---|---|
| NFRS-SCAL-01 | Volume de données supporté sans dégradation perceptible | Au moins 5 années d'historique de ventes/fiches journalières à raison d'usage quotidien réel, sans repenser l'architecture de persistance |
| NFRS-SCAL-02 | Ajout d'une nouvelle filière d'élevage | Réalisable par configuration du patron générique (Strict Avoid §5/§15), pas par duplication d'écran complet |

---

## Note

Les seuils marqués comme "hérités" d'un projet jumeau (AgriERP) ou du prototype de référence ne sont pas des suppositions — ils reflètent des décisions déjà prises et documentées sur ce projet ou son jumeau direct. Tout seuil sans source identifiable ici doit être validé avec la Direction avant d'être considéré comme définitif.
