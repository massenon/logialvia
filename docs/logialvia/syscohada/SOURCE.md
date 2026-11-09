# Source du plan comptable SYSCOHADA révisé — état au 2026-11-09

**Statut : plan vérifié contre le PDF fourni par le client** (`plan-comptable-syscohada-revise_fourni-2026-11-09.pdf`).

| Élément | Valeur |
|---|---|
| Document | « Plan comptable SYSCOHADA révisé — liste complète des comptes (AUDCIF, applicable depuis le 1er janvier 2018) », 31 pages, 1323 comptes, 9 classes |
| Origine | fourni par le client ; mis en page par plan-comptable-ohada.com (reprise de l'Acte uniforme OHADA). Ce n'est pas le Journal officiel OHADA lui-même |
| Vérification | comparaison automatique des 60 comptes du plan retenu au texte du PDF (numéros + libellés) |
| Résultat | **59 numéros sur 60 présents et de même nature** ; libellés identiques (casse et accents près) hors différences d'écriture ci-dessous |

Écarts :
- **246** : libellé officiel « Actifs biologiques » (repris dans le code, Dart et PHP) ; numéro inchangé.
- **611** « Transports sur achats » : **absent du PDF fourni** (la classe 61 y liste 612, 613, 614, 616, 618). Compte conservé, aucun code ne l'écrit ; à confirmer ou retirer.
- Libellés abrégés ou précisés par nous, numéros conformes : 131/139 (« de l'exercice »), 231, 409, 419, 4451/4452 (« État, »), 465, 601/602.

Aucun numéro n'a changé : la migration v48 et la garde `plan_version = 2` restent valables.
