<?php

namespace App\Services;

use App\Livewire\Catalogue;
use App\Models\Bande;
use App\Models\FicheJournee;
use App\Models\FicheVentesJour;
use App\Support\CalculFicheJournaliere;
use App\Support\FilieresElevage;
use App\Support\UuidDeterministe;
use App\Sync\Tables\BandesTable;
use App\Sync\Tables\FichesJourneeTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Fiches d'elevage d'UNE filiere : lecture, saisie d'une journee (avec la cascade) et bandes.
 * PORT de `fiche_elevage_repository_drift.dart`, `enregistrer_journee_usecase.dart` et
 * `bandes_repository_drift.dart` (le Dart est la source).
 *
 * ## Ecriture
 * Toute ecriture passe par `TableSync::absorber` de la table (device `POSTE_WEB`) : la meme
 * validation et la meme regle « dernier ecrivain gagne » que pour un poste. L'instant de
 * saisie est le plus tardif de (maintenant, instant de la ligne connue + 1 microseconde) :
 * la saisie de l'utilisatrice du web est POSTERIEURE a ce qu'elle voyait a l'ecran, meme si
 * l'horloge d'un poste avait de l'avance. Sans cela, sa saisie serait ignoree sans bruit.
 */
class FichesElevage
{
    public const MESSAGE_ECHEC = "Impossible d'enregistrer la saisie du jour. Réessayez.";

    public function __construct(public readonly string $espece)
    {
        abort_unless(FilieresElevage::existe($espece), 404);
    }

    public function nombreCategories(): int
    {
        return FilieresElevage::nombreCategories($this->espece);
    }

    // ----------------------------------------------------------------- Lecture

    public function journee(string $jour): ?FicheJournee
    {
        return FicheJournee::query()->where('espece', $this->espece)->where('date', $jour)->first();
    }

    /** @return Collection<int, FicheJournee> Les journees du mois, indexees par numero de jour. */
    public function mois(int $annee, int $mois): Collection
    {
        $debut = CarbonImmutable::create($annee, $mois, 1)->format('Y-m-d');
        $fin = CarbonImmutable::create($annee, $mois, 1)->endOfMonth()->format('Y-m-d');

        return FicheJournee::query()->where('espece', $this->espece)
            ->whereBetween('date', [$debut, $fin])->orderBy('date')->get()
            ->keyBy(fn (FicheJournee $f) => (int) substr($f->date, 8, 2));
    }

    /** Derniere journee SAISIE strictement avant `$jour`, quel que soit le mois (BR-ELV-006). */
    public function veille(string $jour): ?FicheJournee
    {
        return FicheJournee::query()->where('espece', $this->espece)->where('is_recorded', true)
            ->where('date', '<', $jour)->orderByDesc('date')->first();
    }

    /**
     * Ventes du jour : la SOMME des compteurs de tous les postes (une ligne par poste,
     * `46a_`). Un poste ne compte que ses propres ventes ; rien n'est compte deux fois.
     */
    public function venteDuJour(string $jour): int
    {
        return (int) FicheVentesJour::query()->where('espece', $this->espece)->where('date', $jour)->sum('qte');
    }

    /**
     * Une journee en tableaux indexes par categorie.
     *
     * @return array<string, mixed>
     */
    public function versDomaine(FicheJournee $f): array
    {
        $n = $this->nombreCategories();
        $extraire = fn (int $c1, int $c2, int $c3, ?int $c4): array => array_slice([$c1, $c2, $c3, $c4 ?? 0], 0, $n);

        return [
            'achat' => $f->achat, 'ne' => $f->ne, 'vente' => $f->vente,
            'morts' => $extraire($f->mort_cat1, $f->mort_cat2, $f->mort_cat3, $f->mort_cat4),
            'dons' => $extraire($f->don_cat1, $f->don_cat2, $f->don_cat3, $f->don_cat4),
            'effectif' => $f->effectif,
            'effectifs' => $extraire($f->eff_cat1_day, $f->eff_cat2_day, $f->eff_cat3_day, $f->eff_cat4_day),
            'is_recorded' => $f->is_recorded,
            'poids_general_g' => $f->poids_general_g,
            'traitement_obs' => $f->traitement_obs,
            'traitement_valide' => $f->traitement_valide,
            'srh' => $f->srh, 'ts' => $f->ts, 'stock_final_oeufs' => $f->stock_final_oeufs,
            'oeufs_pondus' => $f->oeufs_pondus, 'oeufs_casses' => $f->oeufs_casses,
            'sorties_plateaux' => $f->sorties_plateaux,
        ];
    }

    // ------------------------------------------------------------- Validation

    /**
     * Validations du formulaire journalier (Dart : `valider`). Messages du Dart.
     *
     * @param  array{achat: int, ne: int, vente: int, morts: list<int>, dons: list<int>}  $mouvements
     * @param  array{pondus: int, casses: int, sorties: int}|null  $oeufs
     * @return list<string>
     */
    public function valider(array $mouvements, ?array $oeufs = null): array
    {
        $erreurs = [];

        if ($oeufs !== null) {
            if ($oeufs['pondus'] < 0) {
                $erreurs[] = 'Les œufs pondus ne peuvent être négatifs.';
            }
            if ($oeufs['casses'] < 0) {
                $erreurs[] = 'Les œufs cassés ne peuvent être négatifs.';
            }
            if ($oeufs['casses'] > $oeufs['pondus']) {
                $erreurs[] = "Les œufs cassés ({$oeufs['casses']}) ne peuvent dépasser les œufs pondus ({$oeufs['pondus']}).";
            }
            if ($oeufs['sorties'] < 0) {
                $erreurs[] = 'Les sorties ne peuvent être négatives.';
            }
        }

        if ($mouvements['achat'] < 0 || $mouvements['ne'] < 0 || $mouvements['vente'] < 0) {
            $erreurs[] = 'Les mouvements ne peuvent être négatifs.';
        }
        $categories = FilieresElevage::configuration($this->espece)['categories'];
        foreach ($mouvements['morts'] as $i => $morts) {
            if ($morts < 0) {
                $erreurs[] = 'Mortalité '.($categories[$i][0] ?? '').' invalide.';
            }
        }
        foreach ($mouvements['dons'] as $i => $dons) {
            if ($dons < 0) {
                $erreurs[] = 'Dons '.($categories[$i][0] ?? '').' invalide.';
            }
        }

        return $erreurs;
    }

    // ----------------------------------------------------------------- Saisie

    /**
     * Enregistre une journee puis propage la cascade (Doc 05 §5) : effectifs recalcules,
     * jamais saisis ; les jours suivants deja saisis sont recalcules jusqu'au premier trou.
     *
     * @param  array{achat: int, ne: int, vente: int, morts: list<int>, dons: list<int>}  $mouvements
     * @param  array{pondus: int, casses: int, sorties: int}|null  $oeufs  Pondeuses uniquement
     * @return string|null Le motif d'echec, ou `null` si la journee est enregistree.
     */
    public function enregistrer(string $jour, array $mouvements, ?int $poidsG, ?string $observation, bool $traitementValide, ?array $oeufs): ?string
    {
        $erreurs = $this->valider($mouvements, $oeufs);
        if ($erreurs !== []) {
            return $erreurs[0];
        }

        try {
            DB::transaction(function () use ($jour, $mouvements, $poidsG, $observation, $traitementValide, $oeufs) {
                $veille = $this->veille($jour);
                $veilleDomaine = $veille ? $this->versDomaine($veille) : null;
                $effectifsVeille = $veilleDomaine['effectifs'] ?? array_fill(0, $this->nombreCategories(), 0);

                $effectifs = CalculFicheJournaliere::calculerJour(
                    $this->espece, $effectifsVeille, $veilleDomaine['effectif'] ?? 0, $mouvements,
                );

                $stock = $oeufs === null ? null : CalculFicheJournaliere::stockOeufs(
                    $veilleDomaine['stock_final_oeufs'] ?? 0, $oeufs['pondus'], $oeufs['casses'], $oeufs['sorties'],
                );

                $this->ecrireJournee($jour, [
                    'achat' => $mouvements['achat'], 'ne' => $mouvements['ne'], 'vente' => $mouvements['vente'],
                    'morts' => $mouvements['morts'], 'dons' => $mouvements['dons'],
                    'effectif' => $effectifs['effectif_total'], 'effectifs' => $effectifs['par_categorie'],
                    'is_recorded' => true,
                    'poids_general_g' => $poidsG,
                    'traitement_obs' => $observation,
                    'traitement_valide' => $traitementValide,
                    'srh' => $stock['srh'] ?? null, 'ts' => $stock['total_stock'] ?? null,
                    'stock_final_oeufs' => $stock['stock_final'] ?? null,
                    'oeufs_pondus' => $oeufs['pondus'] ?? null, 'oeufs_casses' => $oeufs['casses'] ?? null,
                    'sorties_plateaux' => $oeufs['sorties'] ?? null,
                ]);

                $this->recalculerCascade($jour);
            });
        } catch (\Throwable $e) {
            report($e);

            return self::MESSAGE_ECHEC;
        }

        return null;
    }

    /** Recalcule les jours suivants deja saisis, en s'arretant au premier jour non saisi. */
    private function recalculerCascade(string $depuis): void
    {
        $suivantes = FicheJournee::query()->where('espece', $this->espece)->where('date', '>', $depuis)
            ->orderBy('date')->get();

        $precedente = $this->journee($depuis);
        foreach ($suivantes as $suivante) {
            if ($precedente === null || ! $suivante->is_recorded) {
                break;
            }
            $p = $this->versDomaine($precedente);
            $j = $this->versDomaine($suivante);

            $effectifs = CalculFicheJournaliere::calculerJour($this->espece, $p['effectifs'], $p['effectif'], [
                'achat' => $j['achat'], 'ne' => $j['ne'], 'vente' => $j['vente'], 'morts' => $j['morts'], 'dons' => $j['dons'],
            ]);

            // Pondeuses : la cascade recalcule AUSSI SRH / TS / Stock Final (Doc 05 §5).
            $stock = null;
            if ($j['oeufs_pondus'] !== null || $j['oeufs_casses'] !== null || $j['sorties_plateaux'] !== null) {
                $stock = CalculFicheJournaliere::stockOeufs(
                    $p['stock_final_oeufs'] ?? 0, $j['oeufs_pondus'] ?? 0, $j['oeufs_casses'] ?? 0, $j['sorties_plateaux'] ?? 0,
                );
            }

            $recalculee = $j;
            $recalculee['effectif'] = $effectifs['effectif_total'];
            $recalculee['effectifs'] = $effectifs['par_categorie'];
            if ($stock !== null) {
                $recalculee['srh'] = $stock['srh'];
                $recalculee['ts'] = $stock['total_stock'];
                $recalculee['stock_final_oeufs'] = $stock['stock_final'];
            }
            $this->ecrireJournee($suivante->date, $recalculee);
            $precedente = $this->journee($suivante->date);
        }
    }

    /** @param array<string, mixed> $j Une journee au format de `versDomaine`. */
    private function ecrireJournee(string $jour, array $j): void
    {
        $n = $this->nombreCategories();
        $existante = $this->journee($jour);
        $cat = fn (array $valeurs, int $i): int => $valeurs[$i] ?? 0;

        $ligne = [
            'id' => UuidDeterministe::ficheJournee($this->espece, $jour),
            'espece' => $this->espece,
            'date' => $jour,
            'achat' => $j['achat'], 'ne' => $j['ne'], 'vente' => $j['vente'],
            'mort_cat1' => $cat($j['morts'], 0), 'mort_cat2' => $cat($j['morts'], 1), 'mort_cat3' => $cat($j['morts'], 2),
            'mort_cat4' => $n > 3 ? $cat($j['morts'], 3) : null,
            'don_cat1' => $cat($j['dons'], 0), 'don_cat2' => $cat($j['dons'], 1), 'don_cat3' => $cat($j['dons'], 2),
            'don_cat4' => $n > 3 ? $cat($j['dons'], 3) : null,
            'effectif' => $j['effectif'],
            'eff_cat1_day' => $cat($j['effectifs'], 0), 'eff_cat2_day' => $cat($j['effectifs'], 1), 'eff_cat3_day' => $cat($j['effectifs'], 2),
            'eff_cat4_day' => $n > 3 ? $cat($j['effectifs'], 3) : null,
            'srh' => $j['srh'], 'ts' => $j['ts'], 'stock_final_oeufs' => $j['stock_final_oeufs'],
            'oeufs_pondus' => $j['oeufs_pondus'], 'oeufs_casses' => $j['oeufs_casses'], 'sorties_plateaux' => $j['sorties_plateaux'],
            'poids_general_g' => $j['poids_general_g'],
            'traitement_obs' => $j['traitement_obs'],
            'traitement_valide' => (bool) $j['traitement_valide'],
            'is_recorded' => (bool) $j['is_recorded'],
            'updated_at' => self::instantApres($existante?->updated_at),
        ];

        $motif = (new FichesJourneeTable)->absorber(Catalogue::POSTE_WEB, $ligne);
        if ($motif !== null) {
            throw new \RuntimeException("Fiche refusée : $motif");
        }
    }

    // ------------------------------------------------------------------ Bandes

    /**
     * La bande qui couvre cette date : la plus recente des bandes ouvertes ce jour-la
     * (deux bandes peuvent se chevaucher). `null` plutot que la derniere bande connue :
     * le cycle d'une bande cloturee donnerait un jour de cycle faux.
     */
    public function bandeCouvrant(string $jour): ?Bande
    {
        return Bande::query()->where('espece', $this->espece)
            ->where('date_mise_en_bande', '<=', $jour)
            ->where(fn ($q) => $q->whereNull('date_cloture')->orWhere('date_cloture', '>=', $jour))
            ->orderByDesc('date_mise_en_bande')->orderByDesc('updated_at')->orderByDesc('id')->first();
    }

    /** Code propose : prefixe `B` + premier numero libre (prefixe des Parametres Elevage : au poste). */
    public function prochainCodeBande(): string
    {
        $pris = Bande::query()->where('espece', $this->espece)->pluck('code')->all();
        $n = count($pris) + 1;
        while (in_array("B$n", $pris, true)) {
            $n++;
        }

        return "B$n";
    }

    /** @return string|null Le motif du refus, ou `null` si la bande est declaree. */
    public function declarerBande(string $code, string $miseEnPlace, ?int $effectif, ?string $observations): ?string
    {
        if (trim($code) === '') {
            return 'Le code de la bande est obligatoire.';
        }

        return (new BandesTable)->absorber(Catalogue::POSTE_WEB, [
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'espece' => $this->espece,
            'code' => $code, // rogne par BandesTable
            'date_mise_en_bande' => $miseEnPlace,
            'effectif_initial' => $effectif,
            'date_cloture' => null,
            'observations' => $observations === null || trim($observations) === '' ? null : trim($observations),
            'updated_at' => self::instantApres(null),
        ]);
    }

    /** @return string|null Le motif du refus, ou `null` si la bande est cloturee. */
    public function cloturerBande(Bande $bande, string $date): ?string
    {
        return (new BandesTable)->absorber(Catalogue::POSTE_WEB, [
            'id' => $bande->id,
            'espece' => $bande->espece,
            'code' => $bande->code,
            'date_mise_en_bande' => $bande->date_mise_en_bande,
            'effectif_initial' => $bande->effectif_initial,
            'date_cloture' => $date,
            'observations' => $bande->observations,
            'updated_at' => self::instantApres($bande->updated_at),
        ]);
    }

    /** Jour de cycle a la date donnee (J1 = jour de mise en place). */
    public static function jourDeCycle(Bande $bande, string $jour): int
    {
        $debut = CarbonImmutable::createFromFormat('!Y-m-d', $bande->date_mise_en_bande);
        $date = CarbonImmutable::createFromFormat('!Y-m-d', $jour);

        return (int) $debut->diffInDays($date, false) + 1;
    }

    // ------------------------------------------------------------------ Outils

    /**
     * Instant de saisie d'une ecriture du web : maintenant, ou 1 microseconde apres la ligne
     * connue si l'horloge d'un poste avait de l'avance.
     */
    public static function instantApres(?\DateTimeInterface $connu): string
    {
        $maintenant = CarbonImmutable::now('UTC');
        if ($connu !== null) {
            $connu = CarbonImmutable::instance($connu)->utc();
            if ($connu->greaterThanOrEqualTo($maintenant)) {
                $maintenant = $connu->addMicrosecond();
            }
        }

        return $maintenant->format('Y-m-d\TH:i:s.u\Z');
    }
}
