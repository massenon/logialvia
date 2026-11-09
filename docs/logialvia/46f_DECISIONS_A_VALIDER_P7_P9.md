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
