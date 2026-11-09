<?php

namespace App\Support;

/**
 * Plan comptable SYSCOHADA revise (Acte uniforme OHADA 2017, en vigueur depuis le 1er janvier 2018) :
 * l'UNIQUE endroit du serveur qui porte des numeros de compte. PORT du Dart
 * `logialvia_app/lib/comptabilite/domain/plan_syscohada.dart` (le Dart est la source) : ce fichier est
 * compare au Dart par `tests/Feature/ConformitePlanSyscohadaDartTest.php` (constantes, plan, table de
 * correspondance). Doc `47p_PLAN_COMPTABLE_SYSCOHADA.md`.
 *
 * Numeros et libelles RECONSTITUES de la connaissance du plan revise et recoupes avec un plan public
 * tiers ; NON VERIFIES contre le texte officiel de l'OHADA (decision a valider par l'expert-comptable).
 */
final class PlanSyscohada
{
    /** Version du plan portee par les lots d'ecritures et par le plan : 1 = ancien (prototype), 2 = SYSCOHADA. */
    public const VERSION = 2;
    public const CAPITAL = '101';
    public const RESERVE_LEGALE = '111';
    public const AUTRES_RESERVES = '118';
    public const REPORT_CREDITEUR = '121';
    public const REPORT_DEBITEUR = '129';
    public const RESULTAT_BENEFICE = '131';
    public const RESULTAT_PERTE = '139';
    public const STOCK_MARCHANDISES = '31';
    public const STOCK_MATIERES = '32';
    public const FOURNISSEURS = '401';
    public const CLIENTS = '411';
    public const CLIENTS_AVANCES = '419';
    public const TVA_COLLECTEE = '4431';
    public const TVA_COLLECTEE_SERVICES = '4432';
    public const TVA_DEDUCTIBLE = '4452';
    public const DIVIDENDES_A_PAYER = '465';
    public const MOBILE_MONEY = '552';
    public const CAISSE = '571';
    public const ACHATS_MARCHANDISES = '601';
    public const ACHATS_MATIERES = '602';
    public const FRAIS_VETERINAIRES = '604';
    public const TRANSPORTS = '618';
    public const LOCATIONS = '622';
    public const ASSURANCES = '625';
    public const CHARGES_DIVERSES = '658';
    public const VENTES_MARCHANDISES = '701';
    public const VENTES_PRODUITS_FINIS = '702';
    public const PRODUITS_ACCESSOIRES = '707';
    public const FRAIS_LIVRAISON = '7071';

    /** Charges reputees fixes (KPI « Charges Fixes ») : locations et assurances. */
    public const COMPTES_CHARGES_FIXES = [self::LOCATIONS, self::ASSURANCES];

    /** Compte de tresorerie du mode de reglement : Mobile Money → 552, le reste → 571. */
    public static function tresoreriePour(?string $mode): string
    {
        return $mode === 'Mobile Money' ? self::MOBILE_MONEY : self::CAISSE;
    }

    /**
     * TVA extraite d'un montant TTC, arrondie au franc (le FCFA n'a pas de decimale) ; 0 pour un groupe
     * exonere (le montant n'est alors pas arrondi). Meme arrondi que le Dart (`roundToDouble`).
     */
    public static function tvaDuTtc(float $ttc, float $taux): float
    {
        return $taux > 0 ? round($ttc * $taux / (100 + $taux)) : 0.0;
    }

    /** Le plan applicable de la ferme : sous-ensemble utile du plan officiel. @var list<array{0: string, 1: string, 2: string}> numero, libelle, classe */
    public const COMPTES = [
        ['101', 'Capital social', '1'],
        ['111', 'Réserve légale', '1'],
        ['118', 'Autres réserves', '1'],
        ['121', 'Report à nouveau créditeur', '1'],
        ['129', 'Report à nouveau débiteur', '1'],
        ['131', 'Résultat net de l\'exercice : bénéfice', '1'],
        ['139', 'Résultat net de l\'exercice : perte', '1'],
        ['162', 'Emprunts et dettes auprès des établissements de crédit', '1'],
        ['231', 'Bâtiments industriels, agricoles, administratifs et commerciaux sur sol propre', '2'],
        ['242', 'Matériel et outillage agricole', '2'],
        ['244', 'Matériel et mobilier', '2'],
        ['245', 'Matériel de transport', '2'],
        ['246', 'Actifs biologiques', '2'],
        ['283', 'Amortissements des bâtiments, installations techniques et agencements', '2'],
        ['284', 'Amortissements du matériel', '2'],
        ['31', 'Marchandises', '3'],
        ['32', 'Matières premières et fournitures liées', '3'],
        ['36', 'Produits finis', '3'],
        ['401', 'Fournisseurs, dettes en compte', '4'],
        ['409', 'Fournisseurs débiteurs : avances et acomptes versés', '4'],
        ['411', 'Clients', '4'],
        ['419', 'Clients créditeurs, avances et acomptes reçus', '4'],
        ['421', 'Personnel, avances et acomptes', '4'],
        ['422', 'Personnel, rémunérations dues', '4'],
        ['431', 'Sécurité sociale', '4'],
        ['4431', 'TVA facturée sur ventes', '4'],
        ['4432', 'TVA facturée sur prestations de services', '4'],
        ['4441', 'État, TVA due', '4'],
        ['4449', 'État, crédit de TVA à reporter', '4'],
        ['4451', 'État, TVA récupérable sur immobilisations', '4'],
        ['4452', 'État, TVA récupérable sur achats', '4'],
        ['465', 'Associés, dividendes à payer', '4'],
        ['552', 'Monnaie électronique : téléphone portable', '5'],
        ['571', 'Caisse siège social', '5'],
        ['601', 'Achats de marchandises', '6'],
        ['602', 'Achats de matières premières et fournitures liées', '6'],
        ['604', 'Achats stockés de matières et fournitures consommables', '6'],
        ['605', 'Autres achats', '6'],
        ['611', 'Transports sur achats', '6'],
        ['612', 'Transports sur ventes', '6'],
        ['618', 'Autres frais de transport', '6'],
        ['622', 'Locations et charges locatives', '6'],
        ['624', 'Entretien, réparations et maintenance', '6'],
        ['625', 'Primes d\'assurance', '6'],
        ['628', 'Frais de télécommunications', '6'],
        ['631', 'Frais bancaires', '6'],
        ['632', 'Rémunérations d\'intermédiaires et de conseils', '6'],
        ['641', 'Impôts et taxes directs', '6'],
        ['658', 'Charges diverses', '6'],
        ['661', 'Rémunérations directes versées au personnel national', '6'],
        ['664', 'Charges sociales', '6'],
        ['671', 'Intérêts des emprunts', '6'],
        ['681', 'Dotations aux amortissements d\'exploitation', '6'],
        ['701', 'Ventes de marchandises', '7'],
        ['702', 'Ventes de produits finis', '7'],
        ['706', 'Services vendus', '7'],
        ['707', 'Produits accessoires', '7'],
        ['7071', 'Ports, emballages perdus et autres frais facturés', '7'],
        ['758', 'Produits divers', '7'],
        ['771', 'Intérêts de prêts et créances diverses', '7'],
    ];

    /** Libelles de l'ANCIEN plan (prototype) : un libelle encore d'origine est remplace par l'officiel. */
    public const LIBELLES_ANCIENS = [
        '31' => 'Stocks de Marchandises (Commerce Annexe)',
        '32' => 'Stocks de Matières (Intrants Provende)',
        '401' => 'Fournisseurs',
        '411' => 'Clients',
        '419' => 'Clients — Avances Reçues',
        '512' => 'Banques — Mobile Money',
        '531' => 'Caisse',
        '601' => 'Achats de Matières (Intrants Provende)',
        '602' => 'Achats de Marchandises (Commerce Annexe)',
        '622' => 'Frais Vétérinaires',
        '701' => 'Ventes de Produits Avicoles',
        '707' => 'Ventes de Marchandises (Commerce Annexe)',
        '101' => 'Capital Social',
        '121' => 'Report à Nouveau',
        '131' => 'Résultat de l\'Exercice',
        '613' => 'Locations',
        '616' => 'Assurances',
        '624' => 'Transports',
        '628' => 'Charges Diverses de Gestion',
        '111' => 'Réserve Légale',
        '118' => 'Autres Réserves',
        '129' => 'Report à Nouveau — Solde Débiteur',
        '139' => 'Résultat Net : Perte',
        '465' => 'Associés — Dividendes à Payer',
    ];

    /**
     * Table de correspondance ancien → nouveau (comptes dont le numero CHANGE), appliquee en deux temps.
     * La regle specialisee (frais de livraison) passe AVANT la regle generale du 707.
     *
     * @var list<array{ancien: string, nouveau: string, libelle_ancien: string, frais_livraison_seulement: bool}>
     */
    public const CORRESPONDANCE = [
        ['ancien' => '531', 'nouveau' => '571', 'libelle_ancien' => 'Caisse', 'frais_livraison_seulement' => false],
        ['ancien' => '512', 'nouveau' => '552', 'libelle_ancien' => 'Banques — Mobile Money', 'frais_livraison_seulement' => false],
        ['ancien' => '601', 'nouveau' => '602', 'libelle_ancien' => 'Achats de Matières (Intrants Provende)', 'frais_livraison_seulement' => false],
        ['ancien' => '602', 'nouveau' => '601', 'libelle_ancien' => 'Achats de Marchandises (Commerce Annexe)', 'frais_livraison_seulement' => false],
        ['ancien' => '622', 'nouveau' => '604', 'libelle_ancien' => 'Frais Vétérinaires', 'frais_livraison_seulement' => false],
        ['ancien' => '613', 'nouveau' => '622', 'libelle_ancien' => 'Locations', 'frais_livraison_seulement' => false],
        ['ancien' => '616', 'nouveau' => '625', 'libelle_ancien' => 'Assurances', 'frais_livraison_seulement' => false],
        ['ancien' => '624', 'nouveau' => '618', 'libelle_ancien' => 'Transports', 'frais_livraison_seulement' => false],
        ['ancien' => '628', 'nouveau' => '658', 'libelle_ancien' => 'Charges Diverses de Gestion', 'frais_livraison_seulement' => false],
        ['ancien' => '701', 'nouveau' => '702', 'libelle_ancien' => 'Ventes de Produits Avicoles', 'frais_livraison_seulement' => false],
        ['ancien' => '707', 'nouveau' => '7071', 'libelle_ancien' => 'Ventes de Marchandises (Commerce Annexe)', 'frais_livraison_seulement' => true],
        ['ancien' => '707', 'nouveau' => '701', 'libelle_ancien' => 'Ventes de Marchandises (Commerce Annexe)', 'frais_livraison_seulement' => false],
    ];

    /**
     * Nouveau numero d'une ligne de l'ANCIEN plan (fonction pure, source de verite de la verification) :
     * `$axe` et `$venteRef` distinguent les frais de livraison (707 sans centre, piece de vente) des ventes
     * de marchandises (707 au centre « Commerce Annexe »).
     *
     * @param  list<array{ancien: string, nouveau: string, libelle_ancien: string, frais_livraison_seulement: bool}>|null  $regles
     */
    public static function nouveauNumero(string $ancien, ?string $axe = null, ?string $venteRef = null, ?array $regles = null): string
    {
        foreach ($regles ?? self::CORRESPONDANCE as $r) {
            if ($r['ancien'] !== $ancien) {
                continue;
            }
            if ($r['frais_livraison_seulement'] && ! ($axe === null && $venteRef !== null)) {
                continue;
            }

            return $r['nouveau'];
        }
        // Les sous-comptes suivent leur compte : 6011 (sous 601 matieres) devient 6021 (sous 602).
        foreach ($regles ?? self::CORRESPONDANCE as $r) {
            if ($r['frais_livraison_seulement']) {
                continue;
            }
            if (strlen($ancien) > strlen($r['ancien']) && str_starts_with($ancien, $r['ancien'])) {
                return $r['nouveau'].substr($ancien, strlen($r['ancien']));
            }
        }

        return $ancien;
    }
}
