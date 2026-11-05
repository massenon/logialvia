# B1 — BRS — Business Requirements Specification

## 1. Contexte de l'Entreprise

**ALLMANY ET COMPAGNIE**, Natitingou, Bénin. Activité principale : élevage avicole (Goliaths, Pintades, Poulets de chair, Poules pondeuses) avec incubation/couvoir, complétée par de la cuniculture (Lapins) et de la pisciculture (Poissons-Chats). L'entreprise exerce en parallèle une activité de commerce annexe (fournitures scolaires, textile) au même point de vente que les produits d'élevage.

À la date de rédaction, l'exploitation gère un effectif réel de 31 sujets Goliath matures et 28 sujets Pintade matures, avec une trésorerie de fonctionnement et des indicateurs de stock déjà modélisés dans le système existant (ex. Maïs en dessous du seuil critique à 18kg).

## 2. Problème Métier à Résoudre

Avant ce projet, la gestion de l'exploitation reposait sur des supports manuscrits (fiches de suivi papier par espèce, cahier de ventes) sans consolidation ni calcul automatique — source d'erreurs de report, d'absence de traçabilité historique, et d'impossibilité de croiser rapidement les données (ex : combien de Goliaths matures reste-t-il en stock vendable après les ventes du jour ?).

Un prototype numérique (HTML/JS, 31 écrans) a été conçu et validé pour répondre à ce besoin, avec une conception centrée sur la **fidélité aux pratiques réelles de la ferme** (reproduction fidèle des colonnes et calculs des fiches manuscrites existantes). Ce projet Flutter est la mise en production durable de ce prototype validé.

## 3. Parties Prenantes

| Rôle | Intérêt dans le projet |
|---|---|
| Direction ALLMANY ET COMPAGNIE | Pilotage global, rentabilité, fiabilité des chiffres pour décision |
| Animalier(s) | Saisie quotidienne des fiches d'élevage — doit être rapide, sans ambiguïté, exploitable même par un utilisateur peu familier de l'informatique |
| Caissier / Vendeur | Encaissement au comptoir (POS), doit être fluide et rapide face à un client qui attend |
| Comptable | Cohérence des écritures, clôture d'exercice, rapports fiables |
| PAEB (Projet d'Appui à l'Entrepreneuriat au Bénin) | Programme d'accompagnement dans lequel s'inscrit potentiellement ce type d'outil (cohérence avec le cadre AgriERP déjà établi pour un autre bénéficiaire du même programme) |

## 4. Objectifs Métier (mesurables)

| # | Objectif | Mesure de succès |
|---|---|---|
| OB-1 | Éliminer la ressaisie manuelle des fiches d'élevage papier | 100% des mouvements journaliers (achats, naissances, morts, dons, ventes) saisis directement dans l'application, zéro registre papier parallèle après déploiement |
| OB-2 | Garantir l'exactitude du stock vendable en temps réel | Une vente enregistrée décrémente le stock affiché immédiatement, sans écart entre stock système et stock physique constaté |
| OB-3 | Réduire le temps d'encaissement au comptoir | Flux de vente complet (sélection produit → encaissement → reçu) en moins de 60 secondes pour une transaction simple |
| OB-4 | Fournir une vision consolidée multi-espèces sans recalcul manuel | Dashboard Élevage affichant effectifs, mortalité, ventes du jour toutes espèces confondues sans intervention de l'utilisateur |
| OB-5 | Assurer la continuité de service hors connexion internet | Fonctionnement 100% opérationnel sans accès réseau (élevage en zone rurale, connectivité non garantie) |

## 5. Périmètre — Dans le Champ du Projet

- Suivi journalier des 5 filières d'élevage (Goliaths, Pintades, Lapins, Poulets/Pondeuses, Poissons-Chats) avec calculs automatiques par catégorie d'âge
- Suivi du cycle de couvoir/incubation
- Calendrier de soins vétérinaires
- Point de vente (POS) avec panier, remise, mode de paiement, avance/créance
- Gestion des stocks (produits vendables + intrants/provende)
- Gestion des achats et fournisseurs
- Comptabilité (journal, plan comptable, analytique, clôture d'exercice, bilan)
- Rapports et exports
- Gestion des rôles et permissions (Admin, Caissier, Animalier, Comptable)
- Gestion des modules actifs (activation/désactivation de filières selon l'évolution de l'exploitation)

## 6. Hors Périmètre (explicitement)

- Intégration à une passerelle de paiement Mobile Money réelle (le mode "Mobile Money" est enregistré comme information de traçabilité, pas comme transaction bancaire réelle à ce stade)
- Synchronisation multi-postes / multi-sites en temps réel (persistance locale par poste, pas de serveur central pour cette phase — voir Doc C1 Architecture)
- Module de paie et ressources humaines (non présent dans le prototype de référence)
- Application mobile (le prototype et cette conversion ciblent Desktop uniquement)

## 7. Contraintes Métier Connues

- Personnel utilisateur potentiellement peu familier des outils numériques → exigence d'ergonomie simple, cohérente avec l'existant papier (colonnes et libellés des fiches numériques calqués sur les fiches manuscrites réelles)
- Connectivité internet non garantie sur le site → fonctionnement hors-ligne obligatoire (Master Prompt §5)
- Devise unique : Franc CFA
