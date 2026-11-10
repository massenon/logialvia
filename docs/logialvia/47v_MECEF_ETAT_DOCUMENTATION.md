# 47v — e-MECeF et boîtier : documentation disponible et état réel (2026-11-10)

Corrections reçues du dépôt agrierp, intégrées ici. Rien n'a été essayé contre la DGI ni contre un vrai boîtier.

## Faits
- **Boîtier (MECEF-2)** : fusionné dans `main` du dépôt agrierp, avec `47_PLAN_BOITIER_MECEF_2.md` (et non plus seulement dans la branche `claude/sleepy-dijkstra-uvt68t`). Construit contre un faux pilote, **jamais essayé sur un vrai boîtier**.
- **Prix envoyé** : tranché côté AgriERP = **TTC, montants entiers**, comme le documente le pilote (« Prix avec TVA »). Le poste LogiALVIA actuel (`transmission_mecef.dart`) envoie le **hors taxe** : **écart à corriger** (voir `41_MECEF_EMECEF.md`). Corrigé le 2026-11-10 dans LogiALVIA (voir plus bas).
- **Adresses de l'API** : **non confirmées** (paquet non officiel) : essai `developper.impots.bj/sygmef-emcf/api`, production `api.impots.bj/sygmef-emcf/api`.

## Où est la documentation (dépôt agrierp)
- `docs/logialvia/41_MECEF_EMECEF.md`, `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`, `47_PLAN_BOITIER_MECEF_2.md`
- Code de référence : `agrierp_laravel/app/Services/Mecef/` et `config/mecef.php`
- Pilote : dépôt public `issotina/eltrade-cc300-driver` (`Readme.md`, `bill.spec.json`)
- Ticket d'essai : `presentation/ticket_essai_mecef.json` et son PDF ; tests de parité du constructeur de facture

## À fournir pour valider le contrat
1. Cahier des charges officiel de l'API e-MECeF de la DGI Bénin (portail développeurs DGI ou cabinet).
2. Documentation du boîtier MeCeF (fournisseur).
3. Jeton et IFU d'essai : générés depuis le compte e-MECeF de la ferme ; **saisis au web, jamais au poste**.

## Reste à faire côté LogiALVIA
- ~~Aligner le poste sur le prix TTC entier~~ : **fait** (`ClientMecefHttp.ligneTtc`, test `mecef_prix_ttc_test.dart`, mutation HT prouvée). Reste : remise globale, avoirs, noms de champs à confirmer avec la DGI.
- Essai réel selon la procédure de `41_MECEF_EMECEF.md`.
