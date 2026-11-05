# H1 — Spécifications Fonctionnelles Détaillées — Onglets de `ventes_screen.dart`

4 onglets internes (`TabController`, Doc E3 §4). Chaque onglet documenté avec KPIs, Formulaires & Validations, Boutons, DataTables — fidèle à l'implémentation réelle déjà construite et validée côté web.

---

## Onglet 1 — Enregistrer Vente (POS)

### KPIs
Aucun KPI dédié à cet onglet (les KPIs globaux de `ventes_screen` restent visibles au-dessus des onglets, Doc F4).

### Structure (2 colonnes : grille produits 2/3, panier 1/3)

**Grille Produits (gauche)**
- Barre de recherche produit (filtrage en direct, Doc G1 §3)
- Filtre par catégorie (dropdown : Avicole / Commerce Annexe)
- Grille de cartes produit (2-3 colonnes selon largeur) : nom, catégorie+unité, badge stock (rouge si `stock ≤ threshold`), prix. Carte désactivée (griséе, non cliquable) si `stock == 0`.

**Panier (droite, panneau fixe)**
- Liste des lignes du panier : désignation, prix unitaire × unité, contrôles quantité (`−` / valeur / `+`), bouton retirer (×)
- Champ Client (texte libre, optionnel — défaut "Client Comptant")
- Sélecteur Mode de Règlement (Espèces / Mobile Money / Avance)
- Total affiché en gros caractères, couleur `successDeep`
- Bouton "Encaisser la Vente" (primaire, pleine largeur, bas du panneau)

### Formulaires & Validations
| Champ | Validation |
|---|---|
| Quantité par ligne | Ne peut dépasser le stock disponible du produit (FRS-VTE-02) — message "Stock insuffisant (X disponible)." |
| Panier avant encaissement | Non vide (Doc E6 §4) |
| Montant reçu (si mode Avance) | > 0, requis |

### Boutons
| Bouton | Position | Action |
|---|---|---|
| Carte produit (clic) | Grille | Ajoute 1 unité au panier (ou incrémente si déjà présent) |
| `+` / `−` sur ligne panier | Panier | Ajuste la quantité, borné par le stock disponible |
| × sur ligne panier | Panier | Retire la ligne |
| Encaisser la Vente | Bas du panneau panier | Valide (FRS-VTE-03) : transaction atomique, vide le panier, affiche toast succès avec référence, rafraîchit la grille produits (stock à jour) |

### DataTable
Aucune sur cet onglet (c'est la grille produits + panier qui en tient lieu, pas un tableau classique).

---

## Onglet 2 — Devis Prestations

### KPIs
Aucun.

### Structure
- Formulaire de génération de devis : Client, Objet/Prestation, Montant Estimé, Validité (jours)
- `DataTable` des devis émis : Référence, Client, Objet, Montant

### Formulaires & Validations
| Champ | Validation |
|---|---|
| Client | Requis, non vide |
| Objet | Requis, non vide |
| Montant | Requis, > 0 |
| Validité | Nombre entier ≥ 1, défaut 15 |

### Boutons
| Bouton | Action |
|---|---|
| Générer le Devis | Valide → crée l'entrée dans la liste des devis émis (persistance locale, Doc D1 — table à ajouter si le module Devis doit dépasser le stade prototype, actuellement stocké séparément de `VENTES` côté web) → réinitialise le formulaire |

### DataTable
Colonnes : Référence, Client, Objet, Montant. Pas de pagination nécessaire au vu du volume attendu (peu de devis par rapport aux ventes).

---

## Onglet 3 — Historique des Ventes

### KPIs
Aucun dédié (KPIs globaux de l'écran).

### Structure
- En-tête : recherche (Référence/Client) + filtre Statut (Payée/Avance/Annulée)
- `DataTable` (Doc E4) : Référence, Date, Client, Montant, Statut (`StatusBadge`, Doc E2 §4), Actions
- Clic sur une ligne → `OffcanvasPanel` (Doc E4 §4) avec détail complet + bouton Imprimer PDF (Doc E9)

### Formulaires & Validations
Modale d'annulation (déclenchée par l'action "Annuler" d'une ligne non-annulée) :
| Champ | Validation |
|---|---|
| Motif d'annulation | Requis, sélection dans une liste (Erreur de saisie / Client non honoré / Produit indisponible / Autre) |

### Boutons
| Bouton | Position | Action |
|---|---|---|
| Annuler (icône, par ligne) | Colonne Actions, visible uniquement si `status≠'Annulée'` | Ouvre la modale de motif → confirme → `AnnulerVenteUseCase` (restitue stock, FRS-VTE-05) |
| Imprimer la Facture | Dans l'Offcanvas de détail | Déclenche `imprimerFacture()` (Doc E9 §4) |

### DataTable — widgets complets
- En-tête : recherche + filtre (Doc E4 §5)
- Corps : lignes zébrées, `StatusBadge` coloré par statut
- Pied : pagination standard (Doc E4)
- Ligne : clic → Offcanvas ; icône Annuler conditionnelle

---

## Onglet 4 — Retours et Avoirs

### KPIs
Aucun.

### Structure
`DataTable` en lecture seule des ventes en statut `'Annulée'` uniquement — alimentée automatiquement par les annulations faites depuis l'onglet Historique (Onglet 3), **pas de saisie directe possible sur cet onglet**.

### Colonnes
Référence, Date, Client, Montant, Motif d'Annulation.

### Boutons
Aucun bouton d'action sur cet onglet — vue de consultation pure, fidèle au comportement déjà implémenté côté web (`renderRetoursTable()` lit `LogiALVIASync.getVentes().filter(status==='Annulée')`, aucune écriture depuis cet écran).
