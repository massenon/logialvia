<?php

namespace App\Services;

use App\Livewire\DashboardElevage;
use App\Models\AuditLog;
use App\Models\Achat;
use App\Models\Bande;
use App\Models\Client;
use App\Models\CycleCouveuse;
use App\Models\EcheanceProphylaxie;
use App\Models\FicheJournee;
use App\Models\LigneVente;
use App\Models\SoinCalendrier;
use App\Models\User;
use App\Models\Vente;
use App\Services\Comptabilite\LigneEcriture;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use App\Services\Comptabilite\ReportANouveau;
use App\Services\Comptabilite\Soldes;
use App\Support\FilieresElevage;
use App\Support\LibellesAudit;
use App\Support\PlanSyscohada;
use App\Support\ReperesZootechniques;
use App\Support\RetardDeSoin;
use App\Support\SuiviIncubation;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * Donnees du Tableau de Bord que le serveur sait calculer depuis ses tables synchronisees
 * (Dart : `tableau_bord_repository_drift.dart`, `tableau_bord_view_model.dart`,
 * `alertes_view_model.dart`, `CalculerResultatNet`, `ComptabiliteViewModel.tresorerie`).
 *
 * LECTURE SEULE. Aucune methode ne verifie un droit : c'est le composant qui decide quoi appeler.
 * Dates et fuseaux : l'instant « maintenant » est INJECTE (fuseau metier) ; les colonnes `date_*`
 * sont en UTC, les bornes SQL sont formatees comme `TableauDeBord::borne()`.
 *
 * ## Ecarts assumes avec le Dart
 *  - tresorerie / depenses / resultat net : le Dart les laisse a « — » au tableau de bord
 *    (« Disponible avec le module Comptabilite ») ; ils sont ici calcules avec les regles du Dart
 *    COMPTABLE (`debiteursParClasse('5')`, `CalculerResultatNet`) sur les ecritures du serveur ;
 *  - stock critique : le STOCK d'un intrant est propre a chaque poste (decision du client, jamais
 *    synchronise) : il n'existe pas sur le serveur, la donnee n'est donc PAS calculee ;
 *  - anniversaires de clients : le Dart les montre dans l'ecran Clients (fenetre de 7 jours) mais pas
 *    dans les alertes du tableau de bord ; ils sont ajoutes ici comme alerte d'attention.
 */
class TableauBordService
{
    /** Fenetre « anniversaire proche » (Dart : `ClientsViewModel.fenetreCrmJours`). */
    public const FENETRE_ANNIVERSAIRE_JOURS = 7;

    /** Fenetre « eclosion imminente » (Dart : `joursRestants <= 3`). */
    public const FENETRE_ECLOSION_JOURS = 3;

    public const CATEGORIE_COMMERCE = 'Commerce Annexe';

    private static function borne(CarbonImmutable $instant): string
    {
        return $instant->utc()->format('Y-m-d H:i:s.u');
    }

    private static function fuseau(): string
    {
        return config('logialvia.fuseau');
    }

    // ------------------------------------------------------------------ Comptabilite

    /**
     * Ecritures « courantes » de toute la comptabilite (sans a-nouveaux ni cloture : les etats se
     * lisent avant affectation), pour les calculs de periode.
     *
     * @param  Collection<int, LigneEcriture>  $livre
     * @return Collection<int, LigneEcriture>
     */
    public function ecrituresCourantes(Collection $livre): Collection
    {
        return $livre->reject(fn (LigneEcriture $e) => ReportANouveau::estDeCloture($e->journal))->values();
    }

    /**
     * Tresorerie disponible (Dart : `tresorerie => soldes.debiteursParClasse('5')`) : soldes
     * DEBITEURS de la classe 5, ouverture comprise, sur l'exercice de `$maintenant`. Ventilation :
     * caisse 571 (especes) et monnaie electronique 552 (mobile money), soldes debiteurs seulement.
     *
     * @param  Collection<int, LigneEcriture>  $livre
     * @return array{total: float, especes: float, mobile: float}
     */
    public function tresorerie(Collection $livre, CarbonImmutable $maintenant): array
    {
        $soldes = ReportANouveau::soldesDeFin($livre->all(), (int) $maintenant->year);

        return [
            'total' => $soldes->debiteursParClasse('5'),
            'especes' => max(0.0, $soldes->solde(PlanSyscohada::CAISSE)),
            'mobile' => max(0.0, $soldes->solde(PlanSyscohada::MOBILE_MONEY)),
        ];
    }

    /**
     * Charges (classe 6, net debit - credit) des ecritures courantes datees dans [debut, fin].
     * `intrants` = compte 602 (achats de matieres premieres : « intrants provende »).
     *
     * @param  Collection<int, LigneEcriture>  $courantes
     * @return array{total: float, intrants: float}
     */
    public function depenses(Collection $courantes, CarbonImmutable $debut, CarbonImmutable $fin): array
    {
        $soldes = $this->soldesDePeriode($courantes, $debut, $fin);

        return [
            'total' => $soldes->parClasse('6'),
            'intrants' => $soldes->solde(PlanSyscohada::ACHATS_MATIERES),
        ];
    }

    /**
     * Resultat net de la periode : source unique `MoteurComptable::resultatNet` (BR-CPT-005), sur les
     * seules ecritures datees dans [debut, fin]. Marge = resultat / CA ; `null` sans CA.
     *
     * @param  Collection<int, LigneEcriture>  $courantes
     * @return array{montant: float, marge: float|null}
     */
    public function resultatNet(Collection $courantes, CarbonImmutable $debut, CarbonImmutable $fin, ?float $chiffreAffaires): array
    {
        $montant = MoteurComptable::resultatNet($this->soldesDePeriode($courantes, $debut, $fin));

        return [
            'montant' => $montant,
            'marge' => ($chiffreAffaires === null || abs($chiffreAffaires) < 0.005) ? null : $montant / $chiffreAffaires * 100,
        ];
    }

    private function soldesDePeriode(Collection $courantes, CarbonImmutable $debut, CarbonImmutable $fin): Soldes
    {
        return Soldes::depuis($courantes->filter(
            fn (LigneEcriture $e) => ! $e->date->lessThan($debut) && ! $e->date->greaterThan($fin),
        ));
    }

    /**
     * Depenses (classe 6 net) par mois civil, alignees sur les cles `Y-m` fournies.
     *
     * @param  Collection<int, LigneEcriture>  $courantes
     * @param  list<string>  $cles
     * @return list<array{cle: string, depenses: float}>
     */
    public function depensesParMois(Collection $courantes, array $cles): array
    {
        $parMois = array_fill_keys($cles, 0.0);
        foreach ($courantes as $e) {
            $cle = $e->date->format('Y-m');
            if (array_key_exists($cle, $parMois) && str_starts_with($e->compte, '6')) {
                $parMois[$cle] += $e->debit - $e->credit;
            }
        }

        return array_map(fn (string $cle) => ['cle' => $cle, 'depenses' => $parMois[$cle]], $cles);
    }

    /**
     * Depenses (classe 6 net) et CA des 6 derniers jours (Dart : `evolutionJournaliere`), jour courant inclus.
     *
     * @param  Collection<int, LigneEcriture>|null  $courantes  `null` : pas de droit sur la comptabilite
     * @return list<array{libelle: string, ca: float, depenses: float|null}>
     */
    public function jours(CarbonImmutable $maintenant, ?Collection $courantes): array
    {
        $debut = $maintenant->startOfDay()->subDays(5);

        $ca = [];
        $lignes = LigneVente::query()
            ->join('ventes', 'ventes.id', '=', 'lignes_vente.vente_id')
            ->join('produits_vendables', 'produits_vendables.id', '=', 'lignes_vente.produit_id')
            ->whereBetween('ventes.date_vente', [self::borne($debut), self::borne($maintenant->endOfDay())])
            ->where('ventes.status', '!=', 'Annulée')
            ->get(['ventes.date_vente as date_vente', 'lignes_vente.qte', 'lignes_vente.pu']);
        foreach ($lignes as $l) {
            $jour = CarbonImmutable::parse($l->date_vente, 'UTC')->timezone(self::fuseau())->format('Y-m-d');
            $ca[$jour] = ($ca[$jour] ?? 0.0) + $l->qte * $l->pu;
        }

        $depenses = [];
        foreach ($courantes ?? [] as $e) {
            if (str_starts_with($e->compte, '6')) {
                $jour = $e->date->format('Y-m-d');
                $depenses[$jour] = ($depenses[$jour] ?? 0.0) + $e->debit - $e->credit;
            }
        }

        $points = [];
        for ($i = 0; $i < 6; $i++) {
            $j = $debut->addDays($i);
            $cle = $j->format('Y-m-d');
            $points[] = [
                'libelle' => $j->format('d/m'),
                'ca' => (float) ($ca[$cle] ?? 0.0),
                'depenses' => $courantes === null ? null : (float) ($depenses[$cle] ?? 0.0),
            ];
        }

        return $points;
    }

    // ------------------------------------------------------------------ Transactions

    /**
     * Les 3 dernieres ventes (Dart : `ventesRecentes`) : montant = encaisse si « Avance », sinon total.
     *
     * @return list<array{ref: string, libelle: string, montant: float, statut: string|null}>
     */
    public function ventesRecentes(): array
    {
        return Vente::query()->orderByDesc('date_vente')->limit(3)->get()
            ->map(fn (Vente $v) => [
                'ref' => (string) $v->reference,
                'libelle' => $v->reference.' · '.$v->client,
                'montant' => (float) ($v->status === 'Avance' ? $v->paye : $v->total),
                'statut' => $v->status,
            ])->all();
    }

    /**
     * Les 3 derniers achats (le Dart n'a pas cet onglet : meme forme que les ventes) : montant = total.
     *
     * @return list<array{ref: string, libelle: string, montant: float, statut: string|null}>
     */
    public function achatsRecents(): array
    {
        return Achat::query()
            ->leftJoin('fournisseurs', 'fournisseurs.id', '=', 'achats.fournisseur_id')
            ->orderByDesc('achats.date_achat')->limit(3)
            ->get(['achats.reference', 'achats.total', 'achats.statut', 'fournisseurs.nom as fournisseur'])
            ->map(fn ($a) => [
                'ref' => (string) $a->reference,
                'libelle' => $a->reference.($a->fournisseur !== null ? ' · '.$a->fournisseur : ''),
                'montant' => (float) $a->total,
                'statut' => $a->statut,
            ])->all();
    }

    /**
     * Les 3 dernieres depenses saisies (charges de classe 6 sans vente ni achat, non annulees :
     * `MoteurComptable::depenses`, la meme liste que l'ecran « Saisie des Depenses »).
     *
     * Lue sur l'exercice courant et le precedent seulement : la reconstitution des depenses apparie chaque
     * piece a sa contrepartie (cout quadratique), inutile de relire tout l'historique pour 3 lignes.
     *
     * @param  Collection<int, LigneEcriture>  $courantes
     * @return list<array{ref: string, libelle: string, montant: float, statut: string|null}>
     */
    public function depensesRecentes(Collection $courantes, int $exercice): array
    {
        $plan = LivreComptable::plan();
        $recentes = $courantes->filter(fn (LigneEcriture $e) => $e->exercice >= $exercice - 1);

        return collect(MoteurComptable::depenses($recentes, $plan))->take(3)
            ->map(fn (array $d) => [
                'ref' => $d['numero_piece'],
                'libelle' => $d['numero_piece'].' · '.$d['libelle'],
                'montant' => (float) $d['montant'],
                'statut' => $d['payee'] ? 'Payée' : 'En attente',
            ])->values()->all();
    }

    // ------------------------------------------------------------------ Elevage

    /**
     * Recensement d'une filiere (Dart : `recensementFiliere`) : la derniere journee SAISIE (toutes dates),
     * et la mortalite du mois = morts / (effectif du 1er jour saisi reconstitue + entrees du mois).
     * Source UNIQUE : `DashboardElevage` delegue ici.
     *
     * @return array<string, mixed>
     */
    public function recensement(string $espece, CarbonImmutable $maintenant): array
    {
        $config = FilieresElevage::configuration($espece);
        $base = [
            'espece' => $espece, 'libelle' => $config['libelle'], 'route' => $config['route'],
            'libelle_jeunes' => DashboardElevage::LIBELLE_JEUNES[$espece] ?? 'Jeunes',
            'effectif' => 0, 'matures' => 0, 'jeunes' => 0, 'mortalite' => 0.0, 'niveau_mortalite' => 'normal', 'a_des_donnees' => false,
        ];

        $derniere = FicheJournee::query()->where('espece', $espece)->where('is_recorded', true)->orderByDesc('date')->first();
        if ($derniere === null) {
            return $base;
        }

        $debutMois = $maintenant->startOfMonth()->format('Y-m-d');
        $jours = FicheJournee::query()->where('espece', $espece)->where('is_recorded', true)
            ->where('date', '>=', $debutMois)->orderBy('date')->get();

        $mortalite = 0.0;
        if ($jours->isNotEmpty()) {
            $morts = fn (FicheJournee $j): int => $j->mort_cat1 + $j->mort_cat2 + $j->mort_cat3 + ($j->mort_cat4 ?? 0);
            $dons = fn (FicheJournee $j): int => $j->don_cat1 + $j->don_cat2 + $j->don_cat3 + ($j->don_cat4 ?? 0);
            $premier = $jours->first();
            // Effectif EXPOSE (`47e_`) : effectif de debut de mois (reconstitue du 1er jour saisi) +
            // toutes les entrees du mois ; ignorer les entrees faisait depasser 100 %.
            $debutDeMois = $premier->effectif - $premier->achat - $premier->ne + $morts($premier) + $premier->vente + $dons($premier);
            $mortalite = ReperesZootechniques::tauxMortaliteCumule(
                (int) $jours->sum($morts), $debutDeMois, (int) $jours->sum(fn (FicheJournee $j) => $j->achat + $j->ne),
            ) ?? 0.0;
        }

        return [
            'effectif' => $derniere->effectif, 'matures' => $derniere->eff_cat3_day,
            'jeunes' => $derniere->eff_cat2_day, 'mortalite' => $mortalite, 'niveau_mortalite' => ReperesZootechniques::niveauMortaliteCumul($mortalite), 'a_des_donnees' => true,
        ] + $base;
    }

    /**
     * Filieres ACTIVES du tableau de bord, dans l'ordre du Dart : Goliaths et Pintades (permanentes), puis
     * les filieres des modules actifs (`ModulesActifsSeederEspeces.parModule`, UN SEUL libelle d'aviculture :
     * les poulets ; les pondeuses n'y figurent pas, comme au poste).
     *
     * @param  array<string, bool>  $modules  module => actif
     * @return list<string>
     */
    public function especesActives(array $modules): array
    {
        $especes = DashboardElevage::ESPECES_PERMANENTES;
        foreach (config('logialvia.modules') as $module => $espece) {
            if (($modules[$module] ?? false) === true) {
                $especes[] = $espece;
            }
        }

        return $especes;
    }

    /**
     * Cartes de recensement et effectif du cheptel des filieres actives.
     *
     * @param  list<string>  $especes
     * @return array{filieres: list<array<string, mixed>>, cheptel: array{effectif: int, libelle: string}}
     */
    public function cheptelEtFilieres(array $especes, CarbonImmutable $maintenant): array
    {
        $filieres = [];
        $effectif = 0;
        foreach ($especes as $espece) {
            $r = $this->recensement($espece, $maintenant);
            $effectif += (int) $r['effectif'];
            $filieres[] = [
                'code' => $espece,
                'nom' => $r['libelle'],
                'route' => $r['route'],
                'effectif' => (int) $r['effectif'],
                'matures' => (int) $r['matures'],
                'jeunes' => (int) $r['jeunes'],
                'libelleJeunes' => $r['libelle_jeunes'],
                // Aucune journee saisie : pas de mortalite (le Dart affiche 0 ; ici « pas de donnee »).
                'mortalite' => $r['a_des_donnees'] ? (float) $r['mortalite'] : null,
            ];
        }

        return [
            'filieres' => $filieres,
            'cheptel' => [
                'effectif' => $effectif,
                // Libelle du Dart (`detail` du KPI « Effectif Cheptel »).
                'libelle' => $effectif === 0 ? "Aucune journée d'élevage encore saisie" : 'Filières actives, tous stades',
            ],
        ];
    }

    /** @return Collection<int, CycleCouveuse> Les lots non supprimes. */
    public function lotsCouveuse(): Collection
    {
        return CycleCouveuse::query()->whereNull('supprime_le')->orderBy('date_incubation')->orderBy('code_incubation')->get();
    }

    /**
     * Statistiques de la couveuse (Dart : `statistiquesCouveuse`) : lots « En Incubation », œufs charges,
     * taux d'eclosion BRUT moyen (moyenne des poussins nes / œufs couves), perte = 100 - eclosion, et le
     * premier lot dont l'eclosion prevue tombe dans les 3 jours (duree propre a l'espece).
     *
     * @param  Collection<int, CycleCouveuse>  $lots
     * @return array{cycles: int, oeufs: int, eclosionMoy: float|null, perteMoy: float|null, eclosionProchaine: string|null}
     */
    public function couveuse(Collection $lots, CarbonImmutable $maintenant): array
    {
        $enCours = $lots->filter(fn (CycleCouveuse $l) => SuiviIncubation::enCours($l));
        $eclosion = SuiviIncubation::tauxBrutMoyen($lots);

        $jour = SuiviIncubation::jour($maintenant);
        $prochaine = null;
        foreach ($enCours as $lot) {
            $reste = (int) $jour->diffInDays(SuiviIncubation::dateEclosionPrevue($lot), false);
            if ($reste >= 0 && $reste <= self::FENETRE_ECLOSION_JOURS) {
                $prochaine = $lot->code_incubation;
                break;
            }
        }

        return [
            'cycles' => $enCours->count(),
            'oeufs' => (int) $enCours->sum('oeufs_couves'),
            'eclosionMoy' => $eclosion,
            'perteMoy' => $eclosion === null ? null : 100 - $eclosion,
            'eclosionProchaine' => $prochaine,
        ];
    }

    /**
     * Echeances de prophylaxie DUES et jamais planifiees (Dart : `RappelsProphylaxie.dues`) : pour chaque
     * bande ouverte, les echeances de sa filiere dont la date (mise en bande + jour de cycle - 1) est
     * atteinte, sans soin cree depuis elles pour cette bande.
     *
     * @return array{nombre: int, filieres: int, enRetard: int}
     */
    public function rappelsProphylaxie(CarbonImmutable $maintenant): array
    {
        $aujourdhui = $maintenant->format('Y-m-d');
        $bandes = Bande::query()->whereNull('date_cloture')->get();
        if ($bandes->isEmpty()) {
            return ['nombre' => 0, 'filieres' => 0, 'enRetard' => 0];
        }
        $echeances = EcheanceProphylaxie::query()->whereNull('archive_le')->get()->groupBy('espece');
        if ($echeances->isEmpty()) {
            return ['nombre' => 0, 'filieres' => 0, 'enRetard' => 0];
        }
        $planifies = SoinCalendrier::query()->whereNotNull('bande_id')->whereNotNull('echeance_prophylaxie_id')
            ->get(['bande_id', 'echeance_prophylaxie_id'])
            ->mapWithKeys(fn ($s) => [$s->bande_id.'|'.$s->echeance_prophylaxie_id => true]);

        $nombre = $enRetard = 0;
        $especes = [];
        foreach ($bandes as $bande) {
            $debut = CarbonImmutable::createFromFormat('!Y-m-d', substr((string) $bande->date_mise_en_bande, 0, 10), self::fuseau());
            foreach ($echeances->get($bande->espece, []) as $e) {
                if ($planifies->has($bande->id.'|'.$e->id)) {
                    continue;
                }
                $prevue = $debut->addDays((int) $e->jour_cycle - 1)->format('Y-m-d');
                if ($prevue > $aujourdhui) {
                    continue;
                }
                $nombre++;
                $especes[$bande->espece] = true;
                if ($prevue < $aujourdhui) {
                    $enRetard++;
                }
            }
        }

        return ['nombre' => $nombre, 'filieres' => count($especes), 'enRetard' => $enRetard];
    }

    /** Soins veterinaires EN RETARD (Dart : `nombreAlertesSanitaires`, meme regle `RetardDeSoin`). */
    public function soinsEnRetard(CarbonImmutable $maintenant): int
    {
        $aujourdhui = $maintenant->format('Y-m-d');

        return SoinCalendrier::query()->whereIn('statut', ['En retard', 'Planifié'])->get()
            ->filter(fn (SoinCalendrier $s) => RetardDeSoin::estEnRetard($s, $aujourdhui))->count();
    }

    // ------------------------------------------------------------------ Clients

    /**
     * Anniversaires dans les 7 prochains jours, aujourd'hui compris (Dart : `ClientsViewModel.evenements`).
     *
     * @return list<array{nom: string, jours: int}> les plus proches d'abord
     */
    public function anniversaires(CarbonImmutable $maintenant): array
    {
        $aujourdhui = $maintenant->startOfDay();
        $evenements = [];
        foreach (Client::query()->whereNull('supprime_le')->whereNotNull('date_naissance')->get(['nom', 'date_naissance']) as $c) {
            $prochain = $aujourdhui->setDate($aujourdhui->year, $c->date_naissance->month, $c->date_naissance->day);
            if ($prochain->lessThan($aujourdhui)) {
                $prochain = $aujourdhui->setDate($aujourdhui->year + 1, $c->date_naissance->month, $c->date_naissance->day);
            }
            $jours = (int) $aujourdhui->diffInDays($prochain, false);
            if ($jours <= self::FENETRE_ANNIVERSAIRE_JOURS) {
                $evenements[] = ['nom' => (string) $c->nom, 'jours' => $jours];
            }
        }
        usort($evenements, fn (array $a, array $b) => $a['jours'] <=> $b['jours'] ?: strcmp($a['nom'], $b['nom']));

        return $evenements;
    }

    // ------------------------------------------------------------------ Alertes

    /**
     * Alertes du panneau « Alertes Critiques » (Dart : `AlertesViewModel.rafraichir`, meme ordre et memes
     * messages), chacune filtree par le droit de sa donnee. L'alerte de STOCK n'existe pas : le stock des
     * intrants n'est pas sur le serveur.
     *
     * @return list<array{niveau: string, icone: string, texte: string}>
     */
    public function alertes(bool $voirVentes, bool $voirElevage, array $couveuse, int $soldesNombre, CarbonImmutable $maintenant): array
    {
        $alertes = [];

        if ($voirElevage && $couveuse['eclosionProchaine'] !== null) {
            $alertes[] = [
                'niveau' => 'critique', 'icone' => 'eclosion',
                'texte' => 'Éclosion imminente — Cycle '.$couveuse['eclosionProchaine'].', sous 3 jours.',
            ];
        }

        if ($voirVentes && $soldesNombre > 0) {
            $alertes[] = [
                'niveau' => 'attention', 'icone' => 'solde',
                'texte' => "Soldes restant dus — $soldesNombre vente(s) en avance non soldée(s).",
            ];
        }

        if ($voirElevage) {
            $rappels = $this->rappelsProphylaxie($maintenant);
            if ($rappels['nombre'] > 0) {
                $alertes[] = [
                    'niveau' => 'critique', 'icone' => 'soin',
                    'texte' => "{$rappels['nombre']} échéance(s) de prophylaxie non planifiée(s) sur {$rappels['filieres']} filière(s)"
                        .($rappels['enRetard'] > 0 ? ", dont {$rappels['enRetard']} en retard" : '').'.',
                ];
            }

            $soins = $this->soinsEnRetard($maintenant);
            if ($soins > 0) {
                $alertes[] = ['niveau' => 'critique', 'icone' => 'soin', 'texte' => "$soins soin(s) vétérinaire(s) en retard."];
            }
        }

        if ($voirVentes) {
            $anniversaires = $this->anniversaires($maintenant);
            if ($anniversaires !== []) {
                $noms = array_map(
                    fn (array $a) => $a['nom'].' ('.($a['jours'] === 0 ? "aujourd'hui" : ($a['jours'] === 1 ? 'demain' : 'dans '.$a['jours'].' j')).')',
                    array_slice($anniversaires, 0, 3),
                );
                $reste = count($anniversaires) - count($noms);
                $alertes[] = [
                    'niveau' => 'attention', 'icone' => 'anniversaire',
                    'texte' => 'Anniversaire client — '.implode(', ', $noms).($reste > 0 ? " et $reste autre(s)" : '').'.',
                ];
            }
        }

        return $alertes;
    }

    // ------------------------------------------------------------------ Activites

    /**
     * Fil « Activites du Jour » (Dart : `activitesDuJour`) : les traces du journal d'audit du serveur
     * depuis minuit (fuseau metier), les plus recentes d'abord.
     *
     * @return list<array{heure: string, texte: string, auteur: string|null}>
     */
    public function activites(CarbonImmutable $maintenant, int $limite = 10): array
    {
        $lignes = AuditLog::query()
            ->where('created_at', '>=', $maintenant->startOfDay()->utc()->format('Y-m-d H:i:s'))
            ->orderByDesc('created_at')->orderByDesc('id')->limit($limite)->get();

        $auteurs = User::withTrashed()->whereIn('id', $lignes->pluck('utilisateur_id')->filter()->unique()->all())->pluck('name', 'id');

        return $lignes->map(fn (AuditLog $l) => [
            'heure' => $l->created_at->timezone(self::fuseau())->format('H:i'),
            'texte' => LibellesAudit::action($l->action),
            'auteur' => $auteurs[$l->utilisateur_id] ?? ($l->identifiant !== null && $l->identifiant !== '' ? $l->identifiant : null),
        ])->all();
    }
}
