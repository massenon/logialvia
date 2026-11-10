<?php

namespace App\Services\Rapports;

use App\Models\BaremeRation;
use App\Models\CycleCouveuse;
use App\Models\EntreeInfirmerie;
use App\Models\FicheJournee;
use App\Models\SoinCalendrier;
use App\Models\TauxRationPoids;
use App\Support\FilieresElevage;
use App\Support\SuiviIncubation;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/**
 * Rapports & Etats, onglet « Rapport Elevage » (Dart : `RapportsRepositoryDrift._recensement`,
 * `_mouvementsElevage`, `_couvoir`, `_effectifTotal`, `_sujetsMalades`, `_cyclesEnCours`, `_tauxEclosionMoyen`).
 * LECTURE SEULE sur les fiches, soins, infirmerie, couveuse et ventes du serveur.
 *
 * Statuts : le Dart comparait des libelles perimes (`Réalisé`, `Sorti`, `En cours` pour un cycle, `Éclos`) que
 * AUCUNE ligne ne porte : « Traitement administré » restait toujours vide, « Sujets Malades » comptait aussi les
 * sujets sortis ou decedes, « Cycles en Cours » valait toujours 0. Le web lit les statuts reels du serveur
 * (constantes ci-dessous) ; l'ecart est declare dans l'ecran.
 */
final class RapportElevage
{
    /** Ordre des filieres du Dart (`_filieres`) : il differe de celui des fiches. */
    public const ORDRE = ['goliaths', 'pintades', 'lapins', 'escargots', 'bovins', 'poissons-chats', 'poulets', 'pondeuses'];

    public const SOIN_EFFECTUE = 'Effectué';

    public const INFIRMERIE_EN_COURS = 'En cours';

    /** Duree d'incubation : la pintade incube 28 jours (corrige par la Gerante, comme l'ecran Couveuse). */
    private static function dureeIncubation(string $espece): int
    {
        return SuiviIncubation::duree(str_contains(strtolower($espece), 'pintade') ? 'pintade' : 'goliath');
    }

    /** Sujets en infirmerie, pas encore sortis (reintegres ou decedes exclus). */
    private static function malades(?string $espece = null): int
    {
        return EntreeInfirmerie::query()->where('statut', self::INFIRMERIE_EN_COURS)
            ->when($espece !== null, fn ($q) => $q->where('espece', $espece))->count();
    }

    /**
     * @return array{effectif_total: int, malades: int, cycles_en_cours: int, taux_eclosion: ?float, recensement: list<array<string, mixed>>, mouvements: list<array<string, mixed>>, couvoir: list<array<string, mixed>>}
     */
    public static function calculer(CarbonImmutable $debut, CarbonImmutable $fin): array
    {
        $du = $debut->format('Y-m-d');
        $au = $fin->format('Y-m-d');

        $fiches = FicheJournee::query()->whereBetween('date', [$du, $au])->orderBy('date')->get()->groupBy('espece');
        $recensement = $mouvements = [];

        // Les baremes (actifs : une pierre tombale `archive_le` n'est plus un bareme) pilotent « Provende servie ».
        $baremes = BaremeRation::query()->whereNull('archive_le')->get();
        $taux = TauxRationPoids::query()->whereNull('archive_le')->orderBy('poids_min_g')->get();

        foreach (self::ORDRE as $espece) {
            $journees = $fiches->get($espece);
            if ($journees === null || $journees->isEmpty()) {
                continue;
            }
            $conf = FilieresElevage::configuration($espece);
            $categories = $conf['categories'];
            $n = count($categories);
            $derniere = $journees->last();
            $effectifs = [(int) $derniere->eff_cat1_day, (int) $derniere->eff_cat2_day, (int) $derniere->eff_cat3_day, (int) ($derniere->eff_cat4_day ?? 0)];

            // « Geniteurs / Matures » = derniere categorie ; « Jeunes » = toutes les autres categories de la filiere.
            $indexMature = $n - 1;
            $jeunes = 0;
            foreach (array_slice($effectifs, 0, $n) as $i => $eff) {
                if ($i !== $indexMature) {
                    $jeunes += $eff;
                }
            }

            $morts = $dons = $vendus = 0;
            foreach ($journees as $j) {
                $morts += (int) $j->mort_cat1 + (int) $j->mort_cat2 + (int) $j->mort_cat3 + (int) ($j->mort_cat4 ?? 0);
                $dons += (int) $j->don_cat1 + (int) $j->don_cat2 + (int) $j->don_cat3 + (int) ($j->don_cat4 ?? 0);
                $vendus += (int) $j->vente;
            }

            $recensement[] = [
                'lot' => $conf['libelle'],
                'effectif_total' => (int) $derniere->effectif,
                'matures' => $effectifs[$indexMature],
                'jeunes' => $jeunes,
                'morts' => $morts,
                'dons' => $dons,
                'malades' => self::malades($espece),
            ];

            $mouvements[] = [
                'lot' => $conf['libelle'],
                'vendus' => $vendus,
                'montant' => self::montantVentes($espece, $debut, $fin),
                'effectif_final' => (int) $derniere->effectif,
                'traitement' => self::dernierTraitement($espece, $du, $au),
                'signes' => self::signesObserves($espece, $du, $au),
                'provende' => self::provende(
                    $espece,
                    $categories,
                    $effectifs,
                    $derniere->poids_general_g === null ? null : (int) $derniere->poids_general_g,
                    $baremes->where('espece', $espece)->pluck('ration_grammes_par_jour', 'stade')->all(),
                    $taux->where('espece', $espece)->values()->all(),
                ),
            ];
        }

        $cycles = CycleCouveuse::query()->whereNull('supprime_le')->orderByDesc('date_incubation')->orderBy('code_incubation')->get();
        $couvoir = [];
        foreach ($cycles as $c) {
            $mise = SuiviIncubation::jour($c->date_incubation);
            $nes = $c->poussins_nes === null ? null : (int) $c->poussins_nes;
            $couves = (int) $c->oeufs_couves;
            $couvoir[] = [
                'code' => $c->code_incubation,
                'mise' => $mise,
                'eclosion' => $mise->addDays(self::dureeIncubation($c->espece)),
                'couves' => $couves,
                'nes' => $nes,
                'taux' => ($nes === null || $couves <= 0) ? null : $nes / $couves * 100,
                'morts' => $nes === null ? null : $couves - $nes,
                'statut' => $c->statut,
                'eclos' => $c->statut === SuiviIncubation::ECLOSION_EFFECTUEE,
            ];
        }

        // Taux d'eclosion moyen : cycles ECLOS (nes saisis), œufs couves cumules ; `null` sans eclosion.
        $eclos = $cycles->filter(fn (CycleCouveuse $c) => $c->poussins_nes !== null);
        $couvesEclos = (int) $eclos->sum('oeufs_couves');
        $tauxMoyen = ($eclos->isEmpty() || $couvesEclos === 0) ? null : (int) $eclos->sum('poussins_nes') / $couvesEclos * 100;

        // Effectif total : derniere fiche de chaque filiere, QUELLE QUE SOIT la periode.
        $effectifTotal = 0;
        foreach (self::ORDRE as $espece) {
            $effectifTotal += (int) FicheJournee::query()->where('espece', $espece)->orderByDesc('date')->value('effectif');
        }

        return [
            'effectif_total' => $effectifTotal,
            'malades' => self::malades(),
            'cycles_en_cours' => $cycles->where('statut', SuiviIncubation::EN_INCUBATION)->count(),
            'taux_eclosion' => $tauxMoyen,
            'recensement' => $recensement,
            'mouvements' => $mouvements,
            'couvoir' => $couvoir,
        ];
    }

    /** Montant REEL des ventes de l'espece (lignes de vente non annulees), jamais un prix moyen. */
    private static function montantVentes(string $espece, CarbonImmutable $debut, CarbonImmutable $fin): float
    {
        $borne = fn (CarbonImmutable $t) => $t->utc()->format('Y-m-d H:i:s.u');

        return (float) DB::table('lignes_vente')
            ->join('ventes', 'ventes.id', '=', 'lignes_vente.vente_id')
            ->where('lignes_vente.espece', $espece)
            ->whereBetween('ventes.date_vente', [$borne($debut), $borne($fin)])
            ->where('ventes.status', '!=', CalculRapports::VENTE_ANNULEE)
            ->get(['lignes_vente.qte', 'lignes_vente.pu'])
            ->sum(fn ($l) => $l->qte * $l->pu);
    }

    /** Dernier soin REALISE de la periode (pas un soin planifie, pas encore administre). */
    private static function dernierTraitement(string $espece, string $du, string $au): string
    {
        $soin = SoinCalendrier::query()->where('espece', $espece)->where('statut', self::SOIN_EFFECTUE)
            ->whereBetween('date_prevue', [$du, $au])
            ->orderByDesc('date_prevue')->orderByDesc('updated_at')->orderBy('id')->first();

        if ($soin === null) {
            return 'Aucun traitement administré';
        }

        return ($soin->produit === null || $soin->produit === '') ? $soin->type_soin : "{$soin->type_soin} ({$soin->produit})";
    }

    /** Motifs REELLEMENT saisis a l'Infirmerie sur la periode. */
    private static function signesObserves(string $espece, string $du, string $au): string
    {
        $cas = EntreeInfirmerie::query()->where('espece', $espece)->whereBetween('date_entree', [$du, $au])
            ->orderByDesc('date_entree')->orderByDesc('updated_at')->orderBy('id')->get();

        if ($cas->isEmpty()) {
            return 'Aucun signe observé';
        }

        return $cas->count().' sujet(s) — '.$cas->pluck('motif')->unique()->implode(', ');
    }

    /**
     * Provende servie, en g/jour (Dart : `CalculFicheJournaliere.provendeTotaleGrammes`). Rations par categorie
     * = bareme actif du stade, sinon ration par defaut de la filiere. Filiere rationnee sur le poids vif
     * (bovins, poissons-chats) : poids moyen = pesee / effectif, classe qui le contient, provende = pesee x taux ;
     * REPLI sur la ration par tete sans pesee, sans effectif ou sans classe.
     *
     * @param  list<array{0: string, 1: int, 2: bool, 3: bool}>  $categories
     * @param  list<int>  $effectifs
     * @param  array<string, int>  $rations  stade => g/jour
     * @param  list<TauxRationPoids>  $taux
     */
    public static function provende(string $espece, array $categories, array $effectifs, ?int $poidsTotalG, array $rations, array $taux): int
    {
        $total = 0;
        $parTete = 0;
        foreach ($categories as $i => [$libelle, $defaut]) {
            $eff = $effectifs[$i] ?? 0;
            $total += $eff;
            $parTete += $eff * (int) ($rations[$libelle] ?? $defaut);
        }

        if (isset(FilieresElevage::POIDS_VIF[$espece]) && $poidsTotalG !== null && $poidsTotalG > 0 && $total > 0) {
            $moyen = $poidsTotalG / $total;
            foreach ($taux as $classe) {
                if ($moyen >= $classe->poids_min_g && ($classe->poids_max_g === null || $moyen < $classe->poids_max_g)) {
                    return (int) round($poidsTotalG * $classe->taux_pourcent / 100);
                }
            }
        }

        return $parTete;
    }
}
