# B3 — SRS — Software Requirements Specification

## 1. Description Générale du Système

LogiALVIA Flutter est une application desktop monoposte (Windows en priorité), à persistance locale (SQLite via Drift), sans dépendance réseau obligatoire pour son fonctionnement. Elle porte fidèlement les 31 écrans et la logique métier déjà validés dans le prototype HTML de référence.

## 2. Contexte Système

```
                    ┌─────────────────────────────┐
                    │      LogiALVIA (Flutter)      │
                    │                                │
  Utilisateur ──────┤  Presentation (31 ecrans)      │
  (clavier/souris)  │         │                       │
                    │  Domain (usecases, entites)     │
                    │         │                       │
                    │  Data (repositories)             │
                    │         │                       │
                    │  SQLite locale (Drift)           │
                    └─────────────────────────────┘
                              │
                    Impression PDF (facture, rapports)
                    via pilote d'imprimante systeme Windows
```

Aucune interface externe obligatoire (pas d'API tierce requise pour le fonctionnement de base — voir B1 §6 pour le hors-périmètre Mobile Money).

## 3. Exigences Fonctionnelles — Vue d'Ensemble

Le détail exhaustif par module est en section F (Spécifications par Module). Cette vue d'ensemble liste les capacités système de haut niveau, avec identifiant traçable :

| ID | Exigence |
|---|---|
| SRS-F-01 | Le système DOIT permettre la saisie journalière des mouvements d'élevage (achat, naissance, mort, don, vente) par catégorie d'âge, pour 5 filières distinctes |
| SRS-F-02 | Le système DOIT calculer automatiquement l'effectif par catégorie à partir des mouvements saisis, sans saisie manuelle de l'effectif |
| SRS-F-03 | Le système DOIT permettre l'enregistrement d'une vente au comptoir avec décrémentation immédiate et atomique du stock correspondant |
| SRS-F-04 | Le système DOIT répercuter toute vente d'un animal sur le compteur de vente du jour de la fiche d'élevage de l'espèce concernée |
| SRS-F-05 | Le système DOIT permettre l'annulation d'une vente avec restitution du stock |
| SRS-F-06 | Le système DOIT permettre le CRUD complet (créer/lire/modifier/supprimer avec confirmation) sur les articles de stock et d'intrants |
| SRS-F-07 | Le système DOIT générer une facture imprimable pour toute vente validée |
| SRS-F-08 | Le système DOIT permettre la clôture d'un exercice comptable avec verrouillage des écritures et report à nouveau vers l'exercice suivant |
| SRS-F-09 | Le système DOIT restreindre l'accès aux écrans selon le rôle de l'utilisateur connecté (Admin/Caissier/Animalier/Comptable) |

## 4. Exigences Non-Fonctionnelles — Vue d'Ensemble

Détail complet en B5 (NFRS). Résumé des catégories couvertes : performance, fiabilité des calculs, utilisabilité, sécurité des données locales, maintenabilité, portabilité (Windows prioritaire), scalabilité des volumes de données dans le temps.

## 5. Contraintes de Conception

- Architecture Clean 3-couches obligatoire (Doc C1)
- Persistance SQLite locale via Drift obligatoire (Doc D1)
- Fidélité visuelle au prototype HTML — contrainte de conception de premier ordre, pas secondaire (Master Prompt)
- Langue française exclusive pour toute interface utilisateur

## 6. Hypothèses et Dépendances

- Le poste de travail dispose de Windows avec Visual C++ Redistributable (requis par `sqlite3_flutter_libs`)
- Une imprimante est disponible pour l'exigence SRS-F-07 (à défaut, export PDF vers fichier comme repli — voir Doc E9)
- Le personnel a reçu une formation minimale équivalente à celle donnée sur le prototype HTML déjà en phase de validation

## 7. Cas d'Utilisation Principaux (résumé — détail par écran en section F)

| Cas d'utilisation | Acteur principal | Déclencheur |
|---|---|---|
| Saisir la fiche journalière d'une espèce | Animalier | Fin de journée ou saisie en cours de journée |
| Enregistrer une vente au comptoir | Caissier | Client se présente pour achat |
| Consulter et filtrer l'historique des ventes | Caissier, Direction | Besoin de retrouver une transaction |
| Ajuster le stock après inventaire physique | Gestionnaire de stock | Écart constaté entre stock système et stock physique |
| Clôturer un exercice comptable | Comptable | Fin d'année fiscale |
| Consulter le dashboard de pilotage | Direction | Prise de décision quotidienne |
