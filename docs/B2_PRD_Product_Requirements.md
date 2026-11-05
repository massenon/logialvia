# B2 — PRD — Product Requirements Document

## 1. Vision Produit

LogiALVIA est l'outil de gestion quotidienne d'une exploitation agricole multi-filières, pensé pour qu'un animalier ou un caissier sans formation informatique préalable puisse l'utiliser dès le premier jour — parce que sa structure reproduit fidèlement les fiches papier et le fonctionnement du comptoir déjà connus du personnel, sans imposer de nouvelle façon de penser le travail.

## 2. Personas

### Animalier — utilisateur principal des fiches d'élevage
- Saisit quotidiennement : achats, naissances, morts, dons, ventes par catégorie d'animal
- N'a pas besoin de comprendre la mécanique de calcul sous-jacente (répartition par catégorie, cascade) — le système la fait pour lui, il saisit des faits observés
- Besoin critique : ne jamais avoir à ressaisir une donnée déjà entrée, ne jamais voir un chiffre incohérent avec ce qu'il a physiquement compté

### Caissier — utilisateur principal du POS
- Encaisse les ventes au comptoir face à un client qui attend
- Besoin critique : rapidité (sélection produit → quantité → encaissement en un minimum de clics), gestion simple des avances/créances pour les clients réguliers

### Comptable — utilisateur des modules financiers
- Consulte le journal, ajuste le plan comptable, clôture les exercices
- Besoin critique : traçabilité complète, aucune écriture orpheline, cohérence entre les mouvements de stock/vente et les écritures comptables générées

### Direction — utilisateur des dashboards
- Consulte les indicateurs consolidés sans naviguer dans le détail
- Besoin critique : chiffres fiables au premier coup d'œil, sans avoir à croiser plusieurs écrans manuellement

## 3. Portée Fonctionnelle par Module (vue produit, détail technique en section F)

| Module | Fonctionnalités clés |
|---|---|
| Élevage | Saisie journalière par espèce, tableau mensuel 31 jours, calcul automatique des effectifs par catégorie, suivi du cycle de couvoir, calendrier de soins, alerte de mortalité anormale |
| Ventes | POS avec panier et remise, génération de devis, historique consultable et filtrable, annulation avec restitution de stock, facture imprimable |
| Stocks | Suivi des produits vendables et des intrants séparément, CRUD complet, alerte de seuil critique, mouvements tracés |
| Achats | Commandes fournisseurs, suivi des livraisons |
| Comptabilité | Journal, plan comptable, comptabilité analytique, clôture d'exercice avec report à nouveau, bilan |
| Rapports | Exports consolidés multi-modules |
| Administration | Rôles et permissions, activation/désactivation de modules selon l'évolution de l'exploitation |

## 4. Exigence Produit Transversale — Continuité avec le Prototype

**Contrainte produit non négociable** (rappelée du Master Prompt) : structure de page, ordre des sections, espacements, position des boutons, emplacement des CTA, animations, structure des KPI et DataTables — identiques au prototype validé. Ce n'est pas une contrainte esthétique secondaire, c'est une exigence produit de premier ordre : le personnel de terrain a déjà commencé à se familiariser avec cette interface pendant la phase de validation du prototype, un changement de structure imposerait une nouvelle courbe d'apprentissage non justifiée.

## 5. Hors Périmètre Produit (rappel, détaillé en B1)

Paiement Mobile Money réel, multi-site synchronisé, module RH/paie, version mobile.

## 6. Métriques de Succès Produit

| Métrique | Cible |
|---|---|
| Temps de saisie d'une fiche journalière complète | < 3 minutes par espèce |
| Temps d'une transaction POS simple (1 à 2 articles) | < 60 secondes |
| Taux d'écrans avec données réellement persistées (vs mock) | 100% avant mise en production |
| Nombre de re-saisies papier parallèles constatées après déploiement | 0 |

## 7. Phasage Recommandé (dérivé de l'ordre de dépendance technique, Doc INDEX_MAITRE)

1. **Phase 1 — Fondations** : Architecture, Base de données, Design System, Composants
2. **Phase 2 — Élevage** : les 5 fiches + Couvoir + Soins (module le plus complexe fonctionnellement, cœur du métier)
3. **Phase 3 — Commercial** : POS, Catalogue, Clients, Stocks, Achats
4. **Phase 4 — Comptabilité** : Journal, Plan, Analytique, Clôture, Bilan
5. **Phase 5 — Transversal** : Rapports, Paramètres, RBAC, Rapports finaux
