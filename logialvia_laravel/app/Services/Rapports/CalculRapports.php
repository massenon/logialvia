<?php

namespace App\Services\Rapports;

use App\Models\Achat;
use App\Models\Client;
use App\Models\Fournisseur;
use App\Models\PlanComptable;
use App\Models\Vente;
use App\Services\Comptabilite\LigneEcriture;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * Rapports & Etats : calculs de lecture des onglets Recettes/Depenses, Tresorerie, Creances et Dettes
 * (Dart : `RapportsRepositoryDrift`, `rapports.dart`, `RapportsViewModel`). LECTURE SEULE.
 *
 * Le Dart est la source : memes bornes de periode, memes agregats, memes libelles. Les ecritures viennent
 * de `LivreComptable::toutes()` (le livre du serveur, tous postes) : ce service ne recalcule rien du
 * moteur comptable. Chaque ecart avec le poste est affiche dans l'ecran (vue `rapports/_ecarts`).
 */
final class CalculRapports
{
    public const AVICULTURE = 'Aviculture';

    public const COMMERCE_ANNEXE = 'Commerce Annexe';

    public const CHARGE_GENERALE = 'Charge Générale';

    public const MOIS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

    /** Statuts reels du serveur (le Dart de `rapports_repository_drift.dart` comparait « Annulée » pour un achat). */
    public const ACHAT_ANNULE = 'Annulé';

    public const VENTE_ANNULEE = 'Annulée';

    // ------------------------------------------------------------------ Utilitaires

    /** Centre de profit deduit du numero de compte (Dart : `CentresProfit.pourCompte`). */
    public static function centrePourCompte(string $compte): string
    {
        if (str_starts_with($compte, '701') || str_starts_with($compte, '601') || str_starts_with($compte, '622')) {
            return self::AVICULTURE;
        }
        if (str_starts_with($compte, '707') || str_starts_with($compte, '602')) {
            return self::COMMERCE_ANNEXE;
        }

        return self::CHARGE_GENERALE;
    }

    /** `531` -> « Caisse », `512` -> « Mobile Money », sinon le numero (Dart : `CompteTresorerie.libelleCourt`). */
    public static function libelleCourtCompte(string $numero): string
    {
        if (str_starts_with($numero, '531')) {
            return 'Caisse';
        }
        if (str_starts_with($numero, '512')) {
            return 'Mobile Money';
        }

        return $numero;
    }

    /** « Août 2026 » ou « Juillet 2026 — Août 2026 » (Dart : `_libellePeriode`). */
    public static function libellePeriode(CarbonImmutable $debut, CarbonImmutable $fin): string
    {
        $a = self::MOIS[$debut->month - 1].' '.$debut->year;
        if ($debut->year === $fin->year && $debut->month === $fin->month) {
            return $a;
        }

        return $a.' — '.self::MOIS[$fin->month - 1].' '.$fin->year;
    }

    /** Jours civils (fuseau metier) entre l'echeance et aujourd'hui, jamais negatif (Dart : `joursDeRetard`). */
    public static function joursDeRetard(?CarbonImmutable $echeance, CarbonImmutable $aujourdhui): int
    {
        if ($echeance === null) {
            return 0;
        }
        $tz = config('logialvia.fuseau');
        $due = CarbonImmutable::parse($echeance->timezone($tz)->format('Y-m-d'), 'UTC')->getTimestamp();
        $auj = CarbonImmutable::parse($aujourdhui->timezone($tz)->format('Y-m-d'), 'UTC')->getTimestamp();
        $retard = intdiv($auj - $due, 86400);

        return $retard > 0 ? $retard : 0;
    }

    private static function code(string $prefixe, ?string $id): string
    {
        return $id === null ? '—' : $prefixe.'-'.strtoupper(substr(str_replace('-', '', $id), 0, 8));
    }

    // ------------------------------------------------- Onglet 1 : Recettes et Depenses

    /**
     * Une ligne PAR COMPTE de gestion mouvemente (classe 7 = produits credites, classe 6 = charges debitees).
     * Les comptes de tresorerie et de tiers ne sont ni recette ni depense : les compter doublerait les totaux.
     *
     * @param  Collection<int, LigneEcriture>  $ecritures  tout le livre, dans l'ordre de `LivreComptable::toutes()`
     * @param  Collection<string, PlanComptable>  $plan
     * @return list<array{periode: string, numero_piece: string, numero: string, categorie: string, centre: string, encaissement: float, decaissement: float}>
     */
    public static function recettesDepenses(Collection $ecritures, Collection $plan, CarbonImmutable $debut, CarbonImmutable $fin): array
    {
        $enc = $dec = $pieces = [];

        foreach ($ecritures as $e) {
            if ($e->date->lessThan($debut) || $e->date->greaterThan($fin)) {
                continue;
            }
            $c = (string) $e->compte;
            if (str_starts_with($c, '7')) {
                $enc[$c] = ($enc[$c] ?? 0.0) + $e->credit - $e->debit;
            } elseif (str_starts_with($c, '6')) {
                $dec[$c] = ($dec[$c] ?? 0.0) + $e->debit - $e->credit;
            } else {
                continue;
            }
            // Premiere piece rencontree (ordre chronologique) : le Dart garde la premiere de son parcours.
            $pieces[$c] ??= $e->numeroPiece ?? '—';
        }

        // Tri TEXTE des numeros (Dart : `List<String>.sort`) : les cles numeriques de tableau deviennent des entiers en PHP.
        $numeros = array_map('strval', array_keys($enc + $dec));
        sort($numeros, SORT_STRING);

        $periode = self::libellePeriode($debut, $fin);

        return array_map(fn (string $n) => [
            'periode' => $periode,
            'numero_piece' => $pieces[$n] ?? '—',
            'numero' => $n,
            'categorie' => $n.' - '.($plan->get($n)?->libelle ?? 'Compte inconnu'),
            'centre' => self::centrePourCompte($n),
            'encaissement' => $enc[$n] ?? 0.0,
            'decaissement' => $dec[$n] ?? 0.0,
        ], $numeros);
    }

    /**
     * Totaux et solde cumule de l'onglet 1. Les totaux portent sur TOUTES les lignes ; le cumul sur les lignes
     * AFFICHEES (filtrer par centre donne le cumul de ce centre, comme le poste).
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return array{lignes: list<array<string, mixed>>, total_recettes: float, total_depenses: float, resultat_net: float, taux_marge: ?float, maximum: float}
     */
    public static function syntheseRecettes(array $lignes, ?string $centre): array
    {
        $recettes = array_sum(array_column($lignes, 'encaissement'));
        $depenses = array_sum(array_column($lignes, 'decaissement'));
        $net = $recettes - $depenses;

        $affichees = array_values(array_filter($lignes, fn (array $l) => $centre === null || $l['centre'] === $centre));
        $cumul = 0.0;
        foreach ($affichees as $i => $l) {
            $cumul += $l['encaissement'] - $l['decaissement'];
            $affichees[$i]['cumul'] = $cumul;
        }

        return [
            'lignes' => $affichees,
            'total_recettes' => (float) $recettes,
            'total_depenses' => (float) $depenses,
            'resultat_net' => (float) $net,
            'taux_marge' => abs($recettes) < 0.01 ? null : $net / $recettes * 100,
            'maximum' => (float) max($recettes, $depenses, 0.0),
        ];
    }

    // ------------------------------------------------------- Onglet 2 : Tresorerie

    /**
     * Ordre DETERMINISTE des ecritures de meme jour (decision 46f_ : l'`id` est devenu un UUID, son ordre est
     * arbitraire). Ordre retenu : date de l'ecriture, puis ordre de saisie de la PIECE (celui du livre :
     * `LivreComptable::toutes()`), puis numero de piece et identifiant de piece, puis ENTREE avant SORTIE (au
     * poste, la ligne debitee d'une piece est inseree la premiere), puis `id`.
     *
     * @param  Collection<int, LigneEcriture>  $ecritures
     * @return list<LigneEcriture>
     */
    public static function ordreTresorerie(Collection $ecritures): array
    {
        $rang = [];
        foreach ($ecritures->values() as $i => $e) {
            $rang[$e->pieceId] ??= $i;
        }
        $liste = $ecritures->values()->all();
        usort($liste, fn (LigneEcriture $a, LigneEcriture $b) => $a->date <=> $b->date
            ?: $rang[$a->pieceId] <=> $rang[$b->pieceId]
            ?: strcmp((string) $a->numeroPiece, (string) $b->numeroPiece)
            ?: strcmp($a->pieceId, $b->pieceId)
            ?: (($b->debit > 0) <=> ($a->debit > 0))
            ?: strcmp($a->id, $b->id));

        return $liste;
    }

    /** « Vente POS », « Décaissement Achat »… deduits de l'origine reelle de l'ecriture (Dart : `_typeOperation`). */
    public static function typeOperation(?string $venteRef, ?string $achatRef, bool $estEntree): string
    {
        if ($venteRef !== null) {
            return $estEntree ? 'Vente POS' : 'Annulation Vente';
        }
        if ($achatRef !== null) {
            return $estEntree ? 'Remboursement Achat' : 'Décaissement Achat';
        }

        return $estEntree ? 'Encaissement Divers' : 'Décaissement Divers';
    }

    /**
     * Etat de tresorerie : comptes de classe 5 avec leur solde AVANT la periode, mouvements de la periode,
     * solde de cloture par libelle court, solde progressif PAR COMPTE (jamais un cumul melant Caisse et Mobile Money).
     *
     * @param  Collection<int, LigneEcriture>  $ecritures
     * @param  Collection<string, PlanComptable>  $plan
     * @return array{comptes: list<array{numero: string, libelle: string, court: string, ouverture: float}>, libelles: list<string>, clotures: array<string, float>, nette: float, ouvertures: list<array{court: string, ouverture: float}>, mouvements: list<array<string, mixed>>}
     */
    public static function tresorerie(Collection $ecritures, Collection $plan, CarbonImmutable $debut, CarbonImmutable $fin, ?string $filtreCompte): array
    {
        $comptes = [];
        foreach ($plan as $numero => $c) {
            if ((string) $c->classe !== '5') {
                continue;
            }
            $numero = (string) $numero;
            $solde = 0.0;
            foreach ($ecritures as $e) {
                if ((string) $e->compte === $numero && $e->date->lessThan($debut)) {
                    $solde += $e->debit - $e->credit;
                }
            }
            $comptes[] = ['numero' => $numero, 'libelle' => $c->libelle, 'court' => self::libelleCourtCompte($numero), 'ouverture' => $solde];
        }

        $libelles = array_values(array_unique(array_column($comptes, 'court')));
        $ouvertureDe = fn (string $court) => (float) array_sum(array_column(array_filter($comptes, fn ($c) => $c['court'] === $court), 'ouverture'));

        $periode = $ecritures->filter(fn (LigneEcriture $e) => ! $e->date->lessThan($debut) && ! $e->date->greaterThan($fin)
            && str_starts_with((string) $e->compte, '5'));

        $soldes = [];
        foreach ($libelles as $l) {
            $soldes[$l] = $ouvertureDe($l);
        }
        $clotures = $soldes;
        $mouvements = [];
        foreach (self::ordreTresorerie($periode) as $e) {
            $court = self::libelleCourtCompte((string) $e->compte);
            $soldes[$court] = ($soldes[$court] ?? 0.0) + $e->debit - $e->credit;
            $clotures[$court] = ($clotures[$court] ?? 0.0) + $e->debit - $e->credit;
            if ($filtreCompte === null || $court === $filtreCompte) {
                $mouvements[] = [
                    'date' => $e->date,
                    'compte' => $court,
                    'type' => self::typeOperation($e->venteRef, $e->achatRef, $e->debit > 0),
                    'libelle' => $e->libelle,
                    'entree' => $e->debit,
                    'sortie' => $e->credit,
                    'solde' => $soldes[$court],
                ];
            }
        }

        $ouvertures = [];
        foreach ($comptes as $c) {
            if ($filtreCompte === null || $c['court'] === $filtreCompte) {
                $ouvertures[] = ['court' => $c['court'], 'ouverture' => $ouvertureDe($c['court'])];
            }
        }

        return [
            'comptes' => $comptes,
            'libelles' => $libelles,
            'clotures' => $clotures,
            'nette' => (float) array_sum($clotures),
            'ouvertures' => $ouvertures,
            'mouvements' => $mouvements,
        ];
    }

    // ------------------------------------------------------- Onglet 3 : Creances

    /**
     * Ventes non soldees (`paye < total`), hors annulees : une vente annulee n'est plus une creance, son
     * encours est contrepasse (BR-CPT-003).
     *
     * @return list<array<string, mixed>>
     */
    public static function creances(CarbonImmutable $aujourdhui): array
    {
        $tz = config('logialvia.fuseau');
        $clients = Client::query()->get(['id', 'nom']);
        $parId = $clients->keyBy('id');
        $parNom = $clients->keyBy('nom');

        $lignes = [];
        $ventes = Vente::query()->whereColumn('paye', '<', 'total')->where('status', '!=', self::VENTE_ANNULEE)
            ->orderBy('date_vente')->orderBy('reference')->get();

        foreach ($ventes as $v) {
            $client = ($v->client_id !== null ? $parId->get($v->client_id) : null) ?? $parNom->get($v->client);
            $echeance = $v->echeance === null ? null : CarbonImmutable::instance($v->echeance)->timezone($tz);
            $retard = self::joursDeRetard($echeance, $aujourdhui);
            $lignes[] = [
                'code' => self::code('CLI', $client?->id),
                'client' => $v->client,
                'facture' => $v->reference,
                'date_vente' => CarbonImmutable::instance($v->date_vente)->timezone($tz),
                'echeance' => $echeance,
                'initial' => (float) $v->total,
                'acomptes' => (float) $v->paye,
                'solde' => (float) $v->total - (float) $v->paye,
                'retard' => $retard,
                'en_retard' => $retard > 0,
                // « Sans echeance » n'est pas « A echoir » : aucune date fixee ne se dit en clair.
                'statut' => $echeance === null ? 'Sans échéance' : ($retard > 0 ? 'En Retard' : 'À Échoir'),
            ];
        }

        return $lignes;
    }

    /**
     * @param  list<array<string, mixed>>  $lignes
     * @return array{en_cours: float, en_retard: float, clients: int, taux: ?float}
     */
    public static function syntheseCreances(array $lignes): array
    {
        $initial = array_sum(array_column($lignes, 'initial'));

        return [
            'en_cours' => (float) array_sum(array_column($lignes, 'solde')),
            'en_retard' => (float) array_sum(array_column(array_filter($lignes, fn ($l) => $l['en_retard']), 'solde')),
            // Nombre de CLIENTS debiteurs, pas de factures.
            'clients' => count(array_unique(array_column($lignes, 'client'))),
            'taux' => abs($initial) < 0.01 ? null : array_sum(array_column($lignes, 'acomptes')) / $initial * 100,
        ];
    }

    // --------------------------------------------------------- Onglet 4 : Dettes

    /**
     * Achats non regles (`paye < total`), hors annules.
     *
     * @return list<array<string, mixed>>
     */
    public static function dettes(CarbonImmutable $aujourdhui): array
    {
        $tz = config('logialvia.fuseau');
        $fournisseurs = Fournisseur::query()->get(['id', 'nom'])->keyBy('id');

        $lignes = [];
        $achats = Achat::query()->whereColumn('paye', '<', 'total')->where('statut', '!=', self::ACHAT_ANNULE)
            ->orderBy('date_achat')->orderBy('reference')->get();

        foreach ($achats as $a) {
            $echeance = $a->echeance === null ? null : CarbonImmutable::instance($a->echeance)->timezone($tz);
            $retard = self::joursDeRetard($echeance, $aujourdhui);
            $lignes[] = [
                'code' => self::code('FRN', $a->fournisseur_id),
                'fournisseur' => $fournisseurs->get($a->fournisseur_id)?->nom ?? 'Fournisseur inconnu',
                'reference' => $a->reference,
                'date_achat' => CarbonImmutable::instance($a->date_achat)->timezone($tz),
                'echeance' => $echeance,
                'total' => (float) $a->total,
                'regle' => (float) $a->paye,
                'solde' => (float) $a->total - (float) $a->paye,
                'retard' => $retard,
                'urgente' => $retard > 0,
                'statut' => $echeance === null ? 'Sans échéance' : ($retard > 0 ? 'Urgent' : 'Normal'),
            ];
        }

        return $lignes;
    }

    /**
     * @param  list<array<string, mixed>>  $lignes
     * @return array{total: float, urgentes: float, fournisseurs: int}
     */
    public static function syntheseDettes(array $lignes): array
    {
        return [
            'total' => (float) array_sum(array_column($lignes, 'solde')),
            'urgentes' => (float) array_sum(array_column(array_filter($lignes, fn ($l) => $l['urgente']), 'solde')),
            'fournisseurs' => count(array_unique(array_column($lignes, 'fournisseur'))),
        ];
    }
}
