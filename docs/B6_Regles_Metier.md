# B6 — Règles Métier (Business Rules)

Catalogue numéroté des règles métier du système, référençable depuis tout autre document. Le détail technique d'implémentation des règles de calcul d'élevage est en Doc 05 (Logique de Calcul) — ce document donne la règle métier elle-même, formulée indépendamment de l'implémentation.

---

## Catégorie ÉLEVAGE

| ID | Règle |
|---|---|
| BR-ELV-001 | L'effectif d'une catégorie d'âge ne peut jamais être négatif. Toute opération qui produirait un effectif négatif est plafonnée à zéro. |
| BR-ELV-002 | Les achats et les naissances alimentent exclusivement la catégorie la plus jeune de l'espèce concernée. |
| BR-ELV-003 | Les ventes sont exclusivement déduites de la catégorie commercialisée de l'espèce (celle destinée à la vente : Lapin de Chair, Poulet, Porc Marchand, Pondeuse, Goliathau, Pintadau, Juvénile selon l'espèce). |
| BR-ELV-004 | Une mortalité ou un don saisi sur une catégorie précise n'affecte que cette catégorie — jamais de répartition proportionnelle sur les autres catégories. |
| BR-ELV-005 | L'effectif total d'une espèce à un jour donné est la somme de ses sous-effectifs par catégorie à ce même jour. |
| BR-ELV-006 | Toute modification d'un jour déjà saisi déclenche un recalcul en cascade de tous les jours postérieurs déjà enregistrés, jusqu'au premier jour non encore saisi. |
| BR-ELV-007 | Le champ Effectif n'est jamais une donnée saisie directement par l'utilisateur — c'est toujours une valeur dérivée des mouvements (achat/naissance/vente/mort/don). |
| BR-ELV-008 | (Pondeuses uniquement) Le Stock d'ouverture du jour (SRH) d'une journée est égal au Stock Final de la journée précédente — pas au Total Stock (TS) de la journée précédente. Ces deux valeurs ne coïncident que lorsqu'aucune sortie de plateaux n'a eu lieu la veille. |
| BR-ELV-009 | (Pondeuses uniquement) La ration de provende totale du jour est la somme des rations de chacune des 4 catégories (Poussin Ponte, Croissance, Poulette, Pondeuse), jamais celle d'une seule catégorie. |
| BR-ELV-010 | Le compteur "Ventes (POS)" affiché sur une fiche journalière additionne les ventes historiques déjà modélisées et les ventes réelles enregistrées via le module Ventes pour la même espèce et la même date exacte. |

## Catégorie VENTES / STOCK

| ID | Règle |
|---|---|
| BR-VTE-001 | Une vente ne peut être validée si la quantité demandée dépasse le stock disponible du produit au moment de la validation. |
| BR-VTE-002 | La validation d'une vente est une opération atomique : soit l'ensemble (création vente + lignes + décrément stock + incrément fiche élevage) réussit, soit rien n'est appliqué. |
| BR-VTE-003 | Une remise appliquée à une vente réduit le total enregistré ; le total enregistré n'est jamais recalculé automatiquement à partir de la seule somme brute des lignes une fois une remise appliquée. |
| BR-VTE-004 | L'annulation d'une vente restitue intégralement le stock des lignes annulées ; elle ne restitue pas les mouvements déjà comptabilisés dans l'historique zootechnique du jour (une vente annulée reste visible dans l'historique de mouvement de la fiche d'élevage, seul l'aspect commercial est défait). |
| BR-VTE-005 | Un article ne peut être définitivement supprimé du stock sans confirmation explicite de l'utilisateur avec avertissement d'irréversibilité. |
| BR-VTE-006 | Les produits vendables (catalogue commercial) et les intrants (provende, produits vétérinaires) constituent deux catégories de stock distinctes, gérées indépendamment. |

## Catégorie COMPTABILITÉ

| ID | Règle |
|---|---|
| BR-CPT-001 | Une écriture appartenant à un exercice comptable clôturé ne peut plus être modifiée. |
| BR-CPT-002 | La clôture d'un exercice génère automatiquement les écritures de Report à Nouveau (RAN) qui devient le solde d'ouverture de l'exercice suivant, pour chaque compte de bilan. |
| BR-CPT-003 | Toute transaction commerciale génère automatiquement ses écritures comptables équilibrées (total des débits = total des crédits) au moment de sa validation. |
| BR-CPT-004 | La somme de tous les Soldes Finaux Débiteurs de la Balance Générale doit toujours être égale à la somme de tous les Soldes Finaux Créditeurs. Tout écart signale une anomalie de saisie à corriger avant toute clôture. *(Doc F6 §3)* |
| BR-CPT-005 | Le Résultat Net (Compte de Résultat, solde du compte 13 au Bilan, point de départ du TAFIRE) doit être calculé depuis une source unique, jamais trois implémentations indépendantes pouvant diverger. *(Doc F6 §5)* |
| BR-CPT-006 | Une écriture appartenant à un mois clôturé (clôture périodique) ne peut plus être modifiée, sauf déblocage exceptionnel par un utilisateur `admin` (action journalisée, BR-ADM-003). Ce mécanisme n'existe pas pour la clôture annuelle, strictement définitive (BR-CPT-001). *(Doc F6 §6)* |

## Catégorie ADMINISTRATION / SÉCURITÉ

| ID | Règle |
|---|---|
| BR-ADM-001 | Un utilisateur ne voit et n'accède qu'aux modules et écrans autorisés pour son rôle (matrice complète : Doc I1). |
| BR-ADM-002 | La désactivation d'un module retire son accès à la navigation sans supprimer les données historiques déjà associées à ce module. |
| BR-ADM-003 | Toute action de suppression significative (article de stock, fiche, utilisateur) est journalisée avec l'identité de l'utilisateur, l'horodatage, et l'élément concerné. |
| BR-ADM-004 | Le module de conformité fiscale MeCeF (Machine Électronique Certifiée Fiscalement) ne peut être activé tant que l'Identifiant Fiscal Unique (IFU) et le Registre du Commerce (RCCM) de l'entreprise ne sont pas renseignés dans les Paramètres Généraux. *(Découvert par audit réel de `parametres-generaux.html`, Doc F8 — absent de la version initiale de ce catalogue.)* |

---

## Traçabilité

Chaque règle métier (BR-XXX) doit être référencée explicitement par son identifiant dans le code source (commentaire au-dessus de l'implémentation, ex. `// BR-ELV-008: SRH(J+1) = StockFinal(J)`), pour qu'un futur développeur ou auditeur puisse remonter instantanément de l'implémentation à la règle métier documentée qui la justifie.
