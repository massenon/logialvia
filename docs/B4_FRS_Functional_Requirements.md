# B4 — FRS — Functional Requirements Specification

Exigences fonctionnelles détaillées et testables, organisées par module. Chaque exigence a un identifiant traçable et un critère de vérification explicite.

---

## Module : Élevage (5 fiches + Couvoir + Soins)

| ID | Exigence | Critère de vérification |
|---|---|---|
| FRS-ELV-01 | Le formulaire journalier de chaque fiche DOIT proposer les champs Achat, Naissances (Né), Ventes, Morts par catégorie, Dons par catégorie | Tous les champs présents et saisissables, correspondant exactement aux colonnes du prototype HTML source |
| FRS-ELV-02 | Le champ Effectif DOIT être en lecture seule, jamais saisissable manuellement | Tentative de saisie directe rejetée par l'interface (champ désactivé) |
| FRS-ELV-03 | La catégorie la plus jeune DOIT recevoir Achat + Naissances, jamais les autres catégories | Test : saisir Achat=5 sur un jour, vérifier que seule la catégorie jeune augmente de 5, les autres inchangées |
| FRS-ELV-04 | La catégorie commercialisée DOIT être seule déduite des Ventes | Test : saisir Vente=3, vérifier que seule la catégorie commercialisée diminue de 3 |
| FRS-ELV-05 | Chaque catégorie DOIT perdre uniquement ses propres Morts/Dons saisis, jamais une part des Morts/Dons d'une autre catégorie | Test : saisir une mort sur catégorie A uniquement, vérifier que B et C restent inchangées |
| FRS-ELV-06 | La modification d'un jour déjà saisi DOIT recalculer en cascade tous les jours suivants déjà enregistrés | Test : modifier le jour 5 d'un mois où les jours 6 à 10 sont déjà saisis, vérifier que 6 à 10 reflètent la nouvelle base |
| FRS-ELV-07 | La fiche Pondeuses DOIT gérer 4 catégories (Poussin Ponte / Croissance / Poulette / Pondeuse), pas 3 | Vérification visuelle du tableau de Rationnement — 4 lignes |
| FRS-ELV-08 | Le calcul du Stock Hier (SRH) du jour J+1 DOIT être égal au Stock Final du jour J, jamais au Total Stock (TS) | Test : jour avec sortie de plateaux (OS>0), vérifier SRH(J+1) ≠ TS(J) mais = StockFinal(J) |
| FRS-ELV-09 | Le total de provende servie DOIT sommer les 4 catégories de la fiche Pondeuses, pas uniquement la catégorie Pondeuse | Test : vérifier que le total change quand on modifie l'effectif de Poussin Croissance |
| FRS-ELV-10 | Le champ "Ventes (POS)" de chaque fiche journalière DOIT afficher la somme des ventes historiques modélisées ET des ventes réelles enregistrées via le module Ventes pour cette espèce et cette date | Test : enregistrer une vente réelle sur une espèce, vérifier que le compteur du jour correspondant augmente en conséquence |

---

## Module : Ventes (POS, Devis, Historique, Retours)

| ID | Exigence | Critère de vérification |
|---|---|---|
| FRS-VTE-01 | Le POS DOIT afficher le stock disponible de chaque produit vendable en temps réel | Après une vente, le stock affiché sur la grille produit reflète immédiatement la décrémentation |
| FRS-VTE-02 | Une tentative d'ajout au panier au-delà du stock disponible DOIT être rejetée avec message explicite | Test : produit à stock=2, tenter d'ajouter une 3ᵉ unité, vérifier le rejet |
| FRS-VTE-03 | La validation d'une vente DOIT, dans une seule transaction atomique : créer l'enregistrement de vente, créer les lignes de vente, décrémenter le stock de chaque ligne, incrémenter le compteur de vente du jour de l'espèce concernée si applicable | Test d'intégration : vérifier les 4 effets après un seul appel de validation |
| FRS-VTE-04 | Une remise appliquée au comptoir DOIT être respectée dans le total enregistré, jamais recalculée à partir de la seule somme des lignes | Test : appliquer une remise de 500 FCFA, vérifier que le total persisté = somme des lignes − 500 |
| FRS-VTE-05 | L'annulation d'une vente DOIT restituer le stock de chaque ligne annulée | Test : annuler une vente, vérifier que le stock des produits concernés augmente du montant vendu |
| FRS-VTE-06 | L'historique des ventes DOIT être filtrable par statut, mode de paiement, client | Vérification des 3 filtres fonctionnels simultanément combinables |
| FRS-VTE-07 | Chaque vente DOIT générer une facture imprimable reprenant client, date, lignes, total | Vérification du contenu de la facture générée contre les données de la vente |

---

## Module : Stocks

| ID | Exigence | Critère de vérification |
|---|---|---|
| FRS-STK-01 | Les produits vendables (catalogue POS) et les intrants (provende, vétérinaire) DOIVENT être gérés comme deux entités distinctes | Vérification structurelle : deux tables/écrans séparés, pas de confusion des deux concepts |
| FRS-STK-02 | Un article dont le stock est inférieur ou égal à son seuil d'alerte DOIT afficher un badge "Critique" | Test visuel sur un article à stock=seuil |
| FRS-STK-03 | La suppression d'un article DOIT toujours passer par une confirmation explicite avec avertissement d'irréversibilité | Aucun chemin de suppression directe sans modale de confirmation |
| FRS-STK-04 | Un ajustement d'inventaire (stock théorique vs physique) DOIT persister la nouvelle valeur, pas seulement l'afficher temporairement | Test : ajuster, rafraîchir/rouvrir l'écran, vérifier la persistance |

---

## Module : Comptabilité

| ID | Exigence | Critère de vérification |
|---|---|---|
| FRS-CPT-01 | La clôture d'un exercice DOIT verrouiller toutes les écritures de l'exercice clôturé contre toute modification ultérieure | Test : tenter de modifier une écriture d'un exercice clôturé, vérifier le rejet |
| FRS-CPT-02 | La clôture DOIT générer automatiquement les écritures de report à nouveau (RAN) sur l'exercice suivant | Vérification de la présence et du solde des écritures RAN générées |
| FRS-CPT-03 | Chaque transaction commerciale (vente, achat, dépense) DOIT générer ses écritures comptables équilibrées associées | Test : vérifier qu'une vente génère bien Débit Caisse / Crédit Ventes, montants égaux |

---

## Module : Administration (RBAC, Modules Actifs)

| ID | Exigence | Critère de vérification |
|---|---|---|
| FRS-ADM-01 | Un utilisateur avec le rôle "Animalier" NE DOIT PAS accéder aux écrans de Comptabilité | Test : connexion en rôle Animalier, tentative de navigation vers `/comptabilite`, vérifier la redirection |
| FRS-ADM-02 | La désactivation d'un module (ex : filière Poissons-Chats) DOIT retirer son entrée de la navigation sans supprimer les données historiques déjà saisies | Test : désactiver, vérifier absence dans le menu ET présence intacte des données en base |

---

## Note de Traçabilité

Chaque ID de ce document (FRS-XXX-NN) doit être référencé dans la spécification de module correspondante (section F) au moment de sa rédaction détaillée, pour garantir qu'aucune exigence fonctionnelle n'est silencieusement oubliée lors du passage à la spécification écran par écran.
