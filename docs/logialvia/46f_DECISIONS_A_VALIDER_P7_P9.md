# 46f — Décisions à valider par le client (tranches P7 à P9)

Les tranches P7a à P9 ont été réalisées sans interroger le client : chaque choix métier douteux a pris l'option la plus prudente et
est consigné dans le doc de sa tranche. **Rien ci-dessous n'est validé.** À relire avec le client avant la mise en service.

| Doc | Sujet | Décisions (voir le § « Décisions à valider » du doc) |
|---|---|---|
| `46a_` §6 | Fiches d'élevage, bandes | D1 même jour sur deux postes : la saisie la plus récente gagne en bloc ; D2 pas de recalcul des jours voisins ; D4 deux bandes de même code hors ligne : la seconde est refusée, aucun écran pour la recoder ; D10 remise à zéro serveur efface fiches et bandes |
| `46b_` §3 | Couveuse | D1 incubateurs = faits ; D4 suppression d'un lot par pierre tombale ; D5 dernier écrivain gagne sur le lot entier ; D3 codes de lot préfixés par le poste |
| `46c_` §7 | Soins, paramètres d'élevage | D1 le décès se déclare au poste seulement ; D5 droit de modifier la numérotation (incohérence poste/serveur) ; D6 suppression par pierre tombale ; D10 soins et infirmerie jamais supprimés |
| `46d_` §7 | Comptabilité | D1 une pièce transmise s'annule, ne se modifie pas ; D2 clôture annuelle réservée à l'administratrice ; D3 écriture refusée pour période clôturée : reste visible, marquée ; D4 qui clôt / rouvre un mois ; D8 la remise à zéro rouvre les exercices. **Doute majeur** : le Dart ne cumule pas l'ouverture dans bilan / résultat / TAFIRE, et le report à nouveau n'est codé nulle part — à arbitrer avant la première clôture réelle |
| `46e_` §7 | Factures MeCeF | D1 le NIM part au serveur ; D2 seul le poste émetteur transmet ; D3 double normalisation : le serveur garde la première ; D4 le poste garde ses factures normalisées à la remise à zéro ; D6 une seule facture de vente par vente |

Limites communes : aucun essai contre le **vrai** serveur Laravel pour ces tables (le faux serveur de test rejoue les règles mais a été écrit
de la même main) ; `/rapports` ordonne les mouvements de trésorerie du même jour par `id`, devenu un UUID (ordre stable mais arbitraire).

## Écrans Inventaire et Rapports (W5)

- **Corrigé au poste (bugs trouvés en comparant avec le serveur)** : l'inventaire cherchait le statut `En incubation` (réel : `En Incubation`) ;
  les rapports comparaient des libellés périmés : achat `Annulée` (réel `Annulé`, les annulés comptaient dans les dettes), soin `Réalisé`
  (réel `Effectué`), infirmerie `Sorti` (les sujets malades sont `En cours`), cycle `En cours` (réel `En Incubation`), cycle `Éclos` (réel
  `Éclosion Effectuée`), incubation de la pintade 27 j (réel 28 j). Poste et web donnent désormais les mêmes chiffres.
- **À valider** : codes `CLI-xxxxxxxx` / `FRN-xxxxxxxx` au web (le rang séquentiel du poste n'est pas reconstructible côté serveur) ;
  le comptable voit les six onglets des rapports avec le seul droit `view-rapports` (comme au poste) ; « Achats livrés » se calcule sur la
  date de commande (la date de réception n'est pas synchronisée) ; les œufs en incubation s'affichent en ligne à l'inventaire web (le poste
  ne les met que sur le PDF).

## Parité web ↔ poste (docs 47a_ à 47u_)

Chaque doc `47*_` porte sa propre section de décisions à valider. À arbitrer EN PRIORITÉ avant toute mise en service :

- **Plan comptable non conforme au SYSCOHADA révisé** (hérité du prototype, signalé par deux agents) : 601/602 inversés, 701 = « marchandises »
  au plan officiel, caisse en 531 au lieu de 571, banque 512 vs 52x, 613/616/624/628 mal numérotés, 622 « frais vétérinaires » = location
  au plan officiel, TVA (443/445) jamais ventilée, frais de livraison en 707. Une renumérotation demande une migration coordonnée
  poste + serveur + historique : **à valider avec l'expert-comptable du client avant la première déclaration fiscale** (`47a_` §6 D4, `47c_` §5).
- **Report à nouveau** (`47c_`) : 131/139 pour le résultat, affectation décidée à la clôture dans l'écran (en droit : l'Assemblée en N+1), pas de réserve légale codée.
- **Fiches d'élevage divergentes** (`47e_`) : la plus récente reste courante, l'autre est conservée et le choix est explicite (plus de perte silencieuse).
- **Transmission des factures web** (`47a2_` A3) : n'importe quel poste avec `manage-facturation` peut transmettre, un seul à la fois (réservation 15 min).
- **Rôles** (`47u_` D1) : le web attribue aussi Administrateur et Comptable, le Dart seulement agent de vente et d'élevage.
- **Poste appairé à un compte sans droits** (`47h_` D6) : il propose tout son semis, ~74 demandes refusées restent en conflit.

## 2e vague (docs 47g_, 47n_, 47p_, 47r_, 47s_)

- **PLAN COMPTABLE (priorité absolue, `47p_` §9)** : renuméroté mais **NON vérifié contre le texte officiel** (voir `syscohada/SOURCE.md`). À faire relire
  par l'expert-comptable contre le Journal officiel OHADA AVANT toute déclaration : mobile money en 552, produits des filières en 702, soins
  vétérinaires en 604, TVA de la livraison, arrondi de TVA par ligne, ventes historiques conservées TTC.
- **TVA des achats** : câblée à taux 0 tant que les intrants n'ont pas de groupe de taxe (colonne à créer, touche achats et stock).
- **Droits** (`47g_`) : compte sans droits → le semis reste en file et l'écran le dit ; tolérance d'horloge 5 min, avertissement dès 2 min ;
  à la reprise les instants sont bornés à l'heure du serveur (l'ordre relatif des saisies faites pendant l'avance est perdu).
- **Stock ciblé** (`47s_`) : poste de stock facultatif par défaut (`STOCK_CIBLE_OBLIGATOIRE`), vente sur stock insuffisant appliquée avec plancher à 0
  et avertissement, annulation d'une réception avec PMP inverse, poste révoqué : l'effet ne s'applique jamais.
- **Réseau/MySQL** (`47r_`) : le job CI `mysql.yml` n'a jamais tourné sur GitHub ; à surveiller à son premier passage ; configuration d'hébergement
  recommandée au §5 (`.htaccess`, `php.ini`, `DB_TIMEZONE=+00:00`).
