<?php

namespace App\Services\Comptabilite;

use App\Models\PlanComptable;
use Illuminate\Support\Collection;

/**
 * Moteur comptable du web — PORT FIDELE de `moteur_comptable.dart`, `bilan_entreprise.dart` et
 * des agregats du `ComptabiliteViewModel`. Le Dart est la source : memes regles, memes libelles.
 * `tests/Feature/Web/ChiffresComptablesDartTest.php` rejoue un jeu d'ecritures construit a la main
 * et compare les chiffres a ceux calcules par le Dart.
 *
 * Un poste de bilan est un tableau `{libelle, montant, total, sous_total, detail}`.
 */
final class MoteurComptable
{
    public const TOLERANCE = 0.01;

    // ------------------------------------------------------------ Resultat net

    /** Source UNIQUE du Resultat Net (BR-CPT-005) : produits (classe 7) − charges (classe 6). */
    public static function resultatNet(Soldes $s): float
    {
        return -$s->parClasse('7') - $s->parClasse('6');
    }

    public static function produits(Soldes $s): float
    {
        return -$s->parClasse('7');
    }

    public static function charges(Soldes $s): float
    {
        return $s->parClasse('6');
    }

    private static function poste(string $libelle, float $montant, array $options = []): array
    {
        return array_merge([
            'libelle' => $libelle, 'montant' => $montant, 'total' => false, 'sous_total' => false, 'detail' => null,
        ], $options);
    }

    // ------------------------------------------------------------------- Bilan

    /** @return array{actif: list<array>, passif: list<array>, total_actif: float, total_passif: float, equilibre: bool} */
    public static function bilan(Soldes $s): array
    {
        $resultatNet = self::resultatNet($s);

        $chargesImmobilisees = $s->parPrefixe('20');
        $incorporelles = $s->parPrefixe('21');
        $corporelles = $s->parPrefixe('22') + $s->parPrefixe('23') + $s->parPrefixe('24');
        $financieres = $s->parPrefixe('26') + $s->parPrefixe('27');
        $totalImmobilise = $chargesImmobilisees + $incorporelles + $corporelles + $financieres;

        $stocks = $s->parClasse('3');
        $creances = $s->debiteursParClasse('4');
        $totalCirculant = $stocks + $creances;

        $tresorerieActif = $s->debiteursParClasse('5');

        $totalActif = $totalImmobilise + $totalCirculant + $tresorerieActif;
        $actif = [
            self::poste('Charges Immobilisées', $chargesImmobilisees, ['detail' => 'Comptes 20']),
            self::poste('Immobilisations Incorporelles', $incorporelles, ['detail' => 'Comptes 21']),
            self::poste('Immobilisations Corporelles', $corporelles, ['detail' => 'Comptes 22 à 24']),
            self::poste('Immobilisations Financières', $financieres, ['detail' => 'Comptes 26-27']),
            self::poste('Total Actif Immobilisé', $totalImmobilise, ['sous_total' => true]),
            self::poste('Stocks', $stocks, ['detail' => 'Classe 3']),
            self::poste('Créances et Emplois Assimilés', $creances, ['detail' => 'Classe 4, soldes débiteurs']),
            self::poste('Total Actif Circulant', $totalCirculant, ['sous_total' => true]),
            self::poste('Trésorerie-Actif', $tresorerieActif, ['detail' => 'Classe 5, soldes débiteurs']),
            self::poste('TOTAL GÉNÉRAL ACTIF', $totalActif, ['total' => true]),
        ];

        $capital = -$s->parPrefixe('10');
        $reserves = -($s->parPrefixe('11') + $s->parPrefixe('12'));
        $capitauxPropres = $capital + $reserves + $resultatNet;

        $dettesFinancieres = -($s->parPrefixe('16') + $s->parPrefixe('17') + $s->parPrefixe('18') + $s->parPrefixe('19'));
        $ressourcesStables = $capitauxPropres + $dettesFinancieres;

        $dettesCirculantes = $s->crediteursParClasse('4');
        $tresoreriePassif = $s->crediteursParClasse('5');

        $totalPassif = $ressourcesStables + $dettesCirculantes + $tresoreriePassif;
        $passif = [
            self::poste('Capital', $capital, ['detail' => 'Compte 10']),
            self::poste('Réserves et Report à Nouveau', $reserves, ['detail' => 'Comptes 11-12']),
            self::poste('Résultat Net de l\'Exercice', $resultatNet, ['detail' => 'Compte 13 — source unique']),
            self::poste('Total Capitaux Propres', $capitauxPropres, ['sous_total' => true]),
            self::poste('Dettes Financières', $dettesFinancieres, ['detail' => 'Comptes 16-19']),
            self::poste('Total Ressources Stables', $ressourcesStables, ['sous_total' => true]),
            self::poste('Dettes Circulantes', $dettesCirculantes, ['detail' => 'Classe 4, soldes créditeurs']),
            self::poste('Total Passif Circulant', $dettesCirculantes, ['sous_total' => true]),
            self::poste('Trésorerie-Passif', $tresoreriePassif, ['detail' => 'Classe 5, soldes créditeurs']),
            self::poste('TOTAL GÉNÉRAL PASSIF', $totalPassif, ['total' => true]),
        ];

        return [
            'actif' => $actif,
            'passif' => $passif,
            'total_actif' => $totalActif,
            'total_passif' => $totalPassif,
            'equilibre' => abs($totalActif - $totalPassif) < self::TOLERANCE,
        ];
    }

    // ------------------------------------------------------ Compte de resultat

    /** @return array{postes: list<array>, resultat_net: float} */
    public static function compteResultat(Soldes $s): array
    {
        $ventesMarchandises = -$s->parPrefixe('707');
        $ventesProduits = -$s->parPrefixe('701');
        $ventesTotales = -$s->parPrefixe('70');

        $achatsMarchandises = $s->parPrefixe('602');
        $achatsMatieres = $s->parPrefixe('601');

        $margeCommerciale = $ventesMarchandises - $achatsMarchandises;
        $consommationsTiers = $achatsMatieres + $s->parPrefixe('61') + $s->parPrefixe('62');
        $valeurAjoutee = $ventesTotales - $achatsMarchandises - $consommationsTiers;

        $chargesPersonnel = $s->parPrefixe('66');
        $impotsTaxes = $s->parPrefixe('64');
        $excedentBrut = $valeurAjoutee - $chargesPersonnel - $impotsTaxes;

        $autresProduits = -$s->parPrefixe('75');
        $autresCharges = $s->parPrefixe('65');
        $dotations = $s->parPrefixe('68');
        $resultatExploitation = $excedentBrut + $autresProduits - $autresCharges - $dotations;

        $produitsFinanciers = -$s->parPrefixe('77');
        $chargesFinancieres = $s->parPrefixe('67');
        $resultatFinancier = $produitsFinanciers - $chargesFinancieres;
        $resultatOrdinaires = $resultatExploitation + $resultatFinancier;

        $produitsHao = -$s->parPrefixe('78');
        $chargesHao = $s->parPrefixe('83');
        $resultatHao = $produitsHao - $chargesHao;

        $participation = $s->parPrefixe('87');
        $impotSocietes = $s->parPrefixe('89');

        // Le Resultat Net vient de la SOURCE UNIQUE, pas de la fin de cascade.
        $resultatNet = self::resultatNet($s);

        return [
            'resultat_net' => $resultatNet,
            'postes' => [
                self::poste('Ventes de Marchandises', $ventesMarchandises, ['detail' => 'Compte 707']),
                self::poste('Achats de Marchandises Consommés', -$achatsMarchandises, ['detail' => 'Compte 602']),
                self::poste('MARGE COMMERCIALE', $margeCommerciale, ['sous_total' => true]),
                self::poste('Ventes de Produits Avicoles', $ventesProduits, ['detail' => 'Compte 701']),
                self::poste('Consommations en Provenance des Tiers', -$consommationsTiers, ['detail' => 'Comptes 601, 61, 62']),
                self::poste('VALEUR AJOUTÉE', $valeurAjoutee, ['sous_total' => true]),
                self::poste('Charges de Personnel', -$chargesPersonnel, ['detail' => 'Classe 66']),
                self::poste('Impôts et Taxes', -$impotsTaxes, ['detail' => 'Classe 64']),
                self::poste('EXCÉDENT BRUT D\'EXPLOITATION', $excedentBrut, ['sous_total' => true]),
                self::poste('Autres Produits', $autresProduits),
                self::poste('Autres Charges', -$autresCharges),
                self::poste('Dotations aux Amortissements et Provisions', -$dotations, ['detail' => 'Classe 68']),
                self::poste('RÉSULTAT D\'EXPLOITATION', $resultatExploitation, ['sous_total' => true]),
                self::poste('Résultat Financier', $resultatFinancier, ['detail' => 'Classe 77 − Classe 67']),
                self::poste('RÉSULTAT DES ACTIVITÉS ORDINAIRES', $resultatOrdinaires, ['sous_total' => true]),
                self::poste('Résultat Hors Activités Ordinaires', $resultatHao),
                self::poste('Participation des Travailleurs', -$participation),
                self::poste('Impôt sur les Sociétés', -$impotSocietes),
                self::poste('RÉSULTAT NET DE L\'EXERCICE', $resultatNet, ['total' => true]),
            ],
        ];
    }

    // ------------------------------------------------------------------ TAFIRE

    /** @return array{flux_exploitation: float, flux_investissement: float, flux_financement: float, tresorerie_ouverture: float, tresorerie_cloture: float, variation: float, postes: list<array>} */
    public static function tafire(Soldes $s, Soldes $ouverture): array
    {
        $resultatNet = self::resultatNet($s);
        $dotations = $s->parPrefixe('68');

        $bfr = fn (Soldes $x) => $x->parClasse('3') + $x->debiteursParClasse('4') - $x->crediteursParClasse('4');
        $variationBfr = $bfr($s) - $bfr($ouverture);

        $fluxExploitation = $resultatNet + $dotations - $variationBfr;

        $acquisitions = $s->parClasse('2') - $ouverture->parClasse('2');
        $fluxInvestissement = -$acquisitions;

        $financement = -($s->parClasse('1') - $ouverture->parClasse('1'));
        $fluxFinancement = $financement - $resultatNet;

        $tresorerieOuverture = $ouverture->parClasse('5');
        $variation = $fluxExploitation + $fluxInvestissement + $fluxFinancement;

        return [
            'flux_exploitation' => $fluxExploitation,
            'flux_investissement' => $fluxInvestissement,
            'flux_financement' => $fluxFinancement,
            'tresorerie_ouverture' => $tresorerieOuverture,
            'variation' => $variation,
            'tresorerie_cloture' => $tresorerieOuverture + $variation,
            'postes' => [
                self::poste('Résultat Net de l\'Exercice', $resultatNet),
                self::poste('Dotations aux Amortissements', $dotations, ['detail' => 'Charge non décaissée']),
                self::poste('Variation du Besoin en Fonds de Roulement', -$variationBfr),
                self::poste('FLUX NET DE TRÉSORERIE D\'EXPLOITATION', $fluxExploitation, ['sous_total' => true]),
                self::poste('Acquisitions d\'Immobilisations', -$acquisitions),
                self::poste('FLUX NET DE TRÉSORERIE D\'INVESTISSEMENT', $fluxInvestissement, ['sous_total' => true]),
                self::poste('Apports en Capital et Emprunts', $fluxFinancement),
                self::poste('FLUX NET DE TRÉSORERIE DE FINANCEMENT', $fluxFinancement, ['sous_total' => true]),
                self::poste('VARIATION DE TRÉSORERIE DE LA PÉRIODE', $variation, ['total' => true]),
            ],
        ];
    }

    // ------------------------------------------------- Bilan de l'entreprise

    /** @return array{actif: list<array>, passif: list<array>, total_actif: float, total_passif: float, ecart: float, equilibre: bool, vide: bool} */
    public static function bilanEntreprise(Soldes $s): array
    {
        $stocks = $s->parPrefixe('31') + $s->parPrefixe('32');
        $clients = $s->parPrefixe('411');
        $banques = $s->parPrefixe('512');
        $caisse = $s->parPrefixe('531');

        $actif = [
            ['libelle' => 'Stocks (Intrants + Marchandises)', 'compte' => '31/32', 'montant' => $stocks],
            ['libelle' => 'Clients (Solde Restant Dû)', 'compte' => '411', 'montant' => $clients],
            ['libelle' => 'Banques — Mobile Money', 'compte' => '512', 'montant' => $banques],
            ['libelle' => 'Caisse', 'compte' => '531', 'montant' => $caisse],
        ];
        $totalActif = $stocks + $clients + $banques + $caisse;

        // Le capital est LU au compte 101, jamais deduit : l'ecart est affiche en clair.
        $capital = -$s->parPrefixe('101');
        $resultatNet = self::resultatNet($s);
        $fournisseurs = -$s->parPrefixe('401');

        $passif = [
            ['libelle' => 'Capital Initial', 'compte' => '101', 'montant' => $capital],
            ['libelle' => 'Résultat de l\'Exercice', 'compte' => '13', 'montant' => $resultatNet],
            ['libelle' => 'Fournisseurs (Dettes)', 'compte' => '401', 'montant' => $fournisseurs],
        ];
        $totalPassif = $capital + $resultatNet + $fournisseurs;
        $ecart = $totalActif - $totalPassif;

        return [
            'actif' => $actif,
            'passif' => $passif,
            'total_actif' => $totalActif,
            'total_passif' => $totalPassif,
            'ecart' => $ecart,
            'equilibre' => abs($ecart) < self::TOLERANCE,
            'vide' => abs($totalActif) < self::TOLERANCE && abs($totalPassif) < self::TOLERANCE,
        ];
    }

    // ----------------------------------------------------------------- Balance

    /**
     * Balance generale a 6 colonnes (Dart : `BalanceCalculator`).
     *
     * @param  Collection<string, PlanComptable>  $plan
     * @param  iterable<LigneEcriture>  $anterieures  forment les soldes d'ouverture
     * @param  iterable<LigneEcriture>  $periode
     * @return list<array{numero: string, libelle: string, ouverture_debit: float, ouverture_credit: float, mouvements_debit: float, mouvements_credit: float, final_debit: float, final_credit: float}>
     */
    public static function balance(Collection $plan, iterable $anterieures, iterable $periode): array
    {
        $ant = [];
        foreach ($anterieures as $e) {
            $ant[$e->compte][] = $e;
        }
        $per = [];
        foreach ($periode as $e) {
            $per[$e->compte][] = $e;
        }

        $lignes = [];
        foreach ($plan as $numero => $compte) {
            $numero = (string) $numero;
            if (empty($ant[$numero]) && empty($per[$numero])) {
                continue;
            }
            $ouvertureNet = 0.0;
            foreach ($ant[$numero] ?? [] as $e) {
                $ouvertureNet += $e->debit - $e->credit;
            }
            $mouvementsDebit = 0.0;
            $mouvementsCredit = 0.0;
            foreach ($per[$numero] ?? [] as $e) {
                $mouvementsDebit += $e->debit;
                $mouvementsCredit += $e->credit;
            }
            $finalNet = $ouvertureNet + $mouvementsDebit - $mouvementsCredit;

            $lignes[] = [
                'numero' => $numero,
                'libelle' => $compte->libelle,
                // Un solde n'apparait que d'un seul cote : positif au debit, negatif au credit.
                'ouverture_debit' => $ouvertureNet > 0 ? $ouvertureNet : 0.0,
                'ouverture_credit' => $ouvertureNet < 0 ? -$ouvertureNet : 0.0,
                'mouvements_debit' => $mouvementsDebit,
                'mouvements_credit' => $mouvementsCredit,
                'final_debit' => $finalNet > 0 ? $finalNet : 0.0,
                'final_credit' => $finalNet < 0 ? -$finalNet : 0.0,
            ];
        }

        usort($lignes, fn ($a, $b) => strcmp($a['numero'], $b['numero']));

        return $lignes;
    }

    /** Ecart debit − credit des soldes finaux (BR-CPT-004). */
    public static function ecartBalance(array $lignes): float
    {
        return array_sum(array_column($lignes, 'final_debit')) - array_sum(array_column($lignes, 'final_credit'));
    }

    public static function balanceEquilibree(array $lignes): bool
    {
        return abs(self::ecartBalance($lignes)) < self::TOLERANCE;
    }

    // -------------------------------------------------------------- Grand livre

    /**
     * Grand livre d'un compte (Dart : `GrandLivreCalculator`) : solde progressif dans le sens
     * NATUREL du compte (BR-CPT-007).
     *
     * @param  iterable<LigneEcriture>  $ecritures  de ce compte, dans la periode
     * @return list<array{ecriture: LigneEcriture, solde: float}>
     */
    public static function grandLivre(PlanComptable $compte, float $soldeOuverture, iterable $ecritures): array
    {
        $triees = collect($ecritures)->sortBy(fn (LigneEcriture $e) => $e->date->getTimestamp())->values();

        $solde = $soldeOuverture;
        $lignes = [];
        foreach ($triees as $e) {
            $solde += $compte->estDebiteurParNature() ? ($e->debit - $e->credit) : ($e->credit - $e->debit);
            $lignes[] = ['ecriture' => $e, 'solde' => $solde];
        }

        return $lignes;
    }

    // ---------------------------------------------------------------- Analytique

    /**
     * Centres de profit, ventiles depuis l'AXE analytique des ecritures (explicite, prime
     * toujours), a defaut depuis le numero de compte. Une ligne comptee par l'axe n'est
     * JAMAIS recomptee par l'heuristique. Invariant : Σ marges + produits non affectes
     * − charges non affectees = resultat net.
     *
     * @param  iterable<LigneEcriture>  $ecritures  de l'exercice
     * @return array{centres: list<array{nom: string, detail: string, revenus: float, couts: float}>, charges_non_affectees: float, produits_non_affectes: float}
     */
    public static function analytique(iterable $ecritures): array
    {
        $ecritures = collect($ecritures);
        $imputee = fn (LigneEcriture $e) => $e->axe !== null && trim($e->axe) !== '';

        $soldeNonImpute = fn (string $prefixe) => $ecritures
            ->filter(fn (LigneEcriture $e) => str_starts_with($e->compte, $prefixe) && ! $imputee($e))
            ->sum(fn (LigneEcriture $e) => $e->debit - $e->credit);
        $classeNonImputee = fn (string $classe) => $ecritures
            ->filter(fn (LigneEcriture $e) => str_starts_with($e->compte, $classe) && ! $imputee($e))
            ->sum(fn (LigneEcriture $e) => $e->debit - $e->credit);

        // Revenus et couts par axe.
        $parAxe = [];
        foreach ($ecritures as $e) {
            if (! $imputee($e)) {
                continue;
            }
            $axe = trim($e->axe);
            $parAxe[$axe] ??= ['revenus' => 0.0, 'couts' => 0.0];
            if (str_starts_with($e->compte, '7')) {
                $parAxe[$axe]['revenus'] += $e->credit - $e->debit;
            } elseif (str_starts_with($e->compte, '6')) {
                $parAxe[$axe]['couts'] += $e->debit - $e->credit;
            }
        }

        $avicoleRevenus = -$soldeNonImpute('701');
        $avicoleCouts = $soldeNonImpute('601') + $soldeNonImpute('622');
        $commerceRevenus = -$soldeNonImpute('707');
        $commerceCouts = $soldeNonImpute('602');

        $centres = [];
        $noms = array_keys($parAxe);
        sort($noms, SORT_STRING);
        foreach ($noms as $nom) {
            $part = $parAxe[$nom];
            $estCommerce = $nom === 'Commerce Annexe';
            $centres[] = [
                'nom' => $nom,
                'detail' => $estCommerce && (abs($commerceRevenus) + abs($commerceCouts)) >= 0.01
                    ? 'Imputation analytique + comptes 707 et 602'
                    : 'Imputation analytique',
                'revenus' => $part['revenus'] + ($estCommerce ? $commerceRevenus : 0.0),
                'couts' => $part['couts'] + ($estCommerce ? $commerceCouts : 0.0),
            ];
        }

        if (! array_key_exists('Commerce Annexe', $parAxe)
            && (abs($commerceRevenus) >= 0.01 || abs($commerceCouts) >= 0.01)) {
            $centres[] = [
                'nom' => 'Commerce Annexe', 'detail' => 'Comptes 707 et 602',
                'revenus' => $commerceRevenus, 'couts' => $commerceCouts,
            ];
        }

        if (abs($avicoleRevenus) >= 0.01 || abs($avicoleCouts) >= 0.01) {
            $centres[] = [
                'nom' => 'Avicole — filière non précisée',
                'detail' => 'Comptes 701, 601 et 622 sans imputation analytique',
                'revenus' => $avicoleRevenus, 'couts' => $avicoleCouts,
            ];
        }

        return [
            'centres' => $centres,
            'charges_non_affectees' => $classeNonImputee('6') - $soldeNonImpute('601') - $soldeNonImpute('602') - $soldeNonImpute('622'),
            'produits_non_affectes' => -($classeNonImputee('7') - $soldeNonImpute('701') - $soldeNonImpute('707')),
        ];
    }

    // ----------------------------------------------------------------- Depenses

    /** Comptes de charges FIXES (`saisie-depenses.html`) : locations et assurances. */
    public const COMPTES_FIXES = ['613', '616'];

    /**
     * Les depenses d'un exercice, reconstruites depuis leurs ecritures : ligne au debit d'un
     * compte de classe 6, sans `vente_ref` ni `achat_ref` (les achats d'intrants ont leur ecran).
     * Une depense ANNULEE (contrepassee) n'en est plus une.
     *
     * @param  iterable<LigneEcriture>  $ecritures  de l'exercice
     * @param  Collection<string, PlanComptable>  $plan
     * @return list<array{numero_piece: string, piece_id: string, date: \Carbon\CarbonImmutable, libelle: string, compte: string, libelle_compte: string, montant: float, compte_regle: string, centre: ?string, payee: bool}>
     */
    public static function depenses(iterable $ecritures, Collection $plan): array
    {
        $ecritures = collect($ecritures);
        $annulees = $ecritures->whereNotNull('contrepasseDe')->pluck('contrepasseDe')->flip();

        $parPiece = [];
        foreach ($ecritures as $e) {
            if ($e->achatRef !== null || $e->venteRef !== null) {
                continue;
            }
            if ($e->contrepasseDe !== null || $annulees->has($e->pieceId)) {
                continue;
            }
            if ($e->numeroPiece === null) {
                continue;
            }
            $compte = $plan->get($e->compte);
            if ($compte === null || $compte->classe !== '6') {
                continue;
            }
            if ($e->debit <= 0) {
                continue;
            }
            $parPiece[$e->numeroPiece][] = $e;
        }

        $depenses = [];
        foreach ($parPiece as $piece => $lignes) {
            $contreparties = $ecritures->filter(fn (LigneEcriture $e) => $e->numeroPiece === $piece && $e->credit > 0);
            $compteCredite = $contreparties->isEmpty() ? '—' : $contreparties->first()->compte;
            $premiere = $lignes[0];

            $depenses[] = [
                'numero_piece' => (string) $piece,
                'piece_id' => $premiere->pieceId,
                'date' => $premiere->date,
                'libelle' => $premiere->libelle,
                'compte' => $premiere->compte,
                'libelle_compte' => $plan->get($premiere->compte)?->libelle ?? '',
                'montant' => array_sum(array_map(fn (LigneEcriture $e) => $e->debit, $lignes)),
                'compte_regle' => $compteCredite,
                'centre' => $premiere->axe,
                // Une charge soldee par 401 n'est pas decaissee : elle reste due.
                'payee' => ! str_starts_with($compteCredite, '40'),
            ];
        }

        usort($depenses, fn ($a, $b) => $b['date']->getTimestamp() <=> $a['date']->getTimestamp());

        return $depenses;
    }
}
