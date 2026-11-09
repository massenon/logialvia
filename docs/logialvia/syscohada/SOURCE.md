# Source du plan comptable SYSCOHADA révisé — état au 2026-11-09

**Statut : texte officiel NON obtenu.** Voir `../47p_PLAN_COMPTABLE_SYSCOHADA.md` §1.

| Élément | Valeur |
|---|---|
| Source officielle visée | site de l'OHADA (`https://www.ohada.org/`), Journal officiel OHADA (AUDCIF révisé, 2017) |
| Résultat | **inaccessible** depuis l'environnement (connexion refusée par le proxy), aucun fichier officiel enregistré |
| Source tierce consultée | plan SYSCOHADA du dépôt public Odoo, branche 17.0 : `addons/l10n_syscohada/data/template/account.account-syscohada.csv` (hébergé sur `raw.githubusercontent.com`) |
| Date de consultation | 2026-11-09 |
| Format | CSV (`id`, `name`, `code`, `account_type`, `reconcile`, `name@fr`), 131 369 caractères |
| Lecture | par un outil de lecture web qui **résume** : les 100 000 premiers caractères ont été vus en deux passes ; le CSV brut n'est **pas** stocké ici |
| Fiabilité | **faible pour les libellés** (traductions automatiques, libellés fautifs) ; utile pour la **numérotation** seulement |

Fichier du dépôt : `plan_syscohada_revise_ferme.csv` — le plan retenu, **reconstitué de la connaissance du SYSCOHADA révisé,
non vérifié contre le texte officiel** (généré depuis `plan_syscohada.dart`).

Numéros recoupés avec le plan tiers (présents et de même nature) : 111, 121, 131, 139, 4431, 4432, 4441, 4449, 4451, 4452,
5711, 552 (« monnaie électronique : téléphone portable »), 601x, 602x, 604x, 6181, 622x, 624x, 625x, 6324, 658x, 7011, 7021,
7071 (« frais de port… facturés »), 7061 (services vendus). Non confirmés par ce plan tiers (connaissance seule) : 162, 242,
246, 283, 284, 409, 421, 422, 431, 521 (non semé), 36, 605, 611, 612, 631, 632, 641, 661, 664, 671, 681, 758, 771.
