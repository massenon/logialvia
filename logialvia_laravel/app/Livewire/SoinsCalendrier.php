<?php

namespace App\Livewire;

use App\Models\EntreeInfirmerie;
use App\Services\FichesElevage;
use App\Models\SoinCalendrier;
use App\Support\FilieresElevage;
use App\Sync\Tables\InfirmerieTable;
use App\Sync\Tables\SoinsCalendrierTable;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Soins & Calendrier (Dart : `soins_calendrier_screen.dart`). Deux FAITS : le registre des
 * soins et l'infirmerie.
 *
 * Toute ecriture passe par `TableSync::absorber` de la table (device `Catalogue::POSTE_WEB`,
 * `updated_at` = maintenant a la microseconde) : les MEMES validations, le meme dernier
 * ecrivain gagne que pour un poste ; la ligne redescend ensuite vers les postes.
 *
 * ECARTS declares avec le Dart (voir `46c_`) :
 *  - pas d'export PDF ;
 *  - pas de lien de bande (les bandes ne sont pas synchronisees) ;
 *  - « Deces » reste au poste : il porte la perte sur la fiche d'elevage, ce que le web
 *    ne peut pas faire (fiches non synchronisees) ; le web ne propose que « Reintegrer ».
 *  - la liste des filieres proposees pour une saisie est limitee aux filieres actives.
 */
#[Layout('components.layouts.app')]
class SoinsCalendrier extends Component
{
    public string $onglet = 'registre';

    public string $filtreType = '';

    public string $filtreEspece = '';

    /** Modale ouverte : `soin`, `intervention`, `entree` ou `null`. */
    public ?string $modale = null;

    public string $espece = '';

    public string $dateSoin = '';

    /** Bande du soin (facultatif) : le lien soin -> bande voyage avec le soin (`47e_`). */
    public string $bandeId = '';

    public string $typeSoin = '';

    public string $produit = '';

    public string $dose = '';

    public string $remanence = '0';

    public string $veterinaire = '';

    public string $symptomes = '';

    public string $cout = '0';

    public bool $dejaEffectue = false;

    public string $intervention = '';

    public string $sujet = '';

    public string $motif = '';

    public string $niveau = 'Simple surveillance';

    /** Entree dont on declare le deces (la categorie d'effectif se choisit avant de confirmer). */
    public ?string $decesEntreeId = null;

    /** Index de la categorie d'effectif ou porter la perte ; `''` = ne pas toucher la fiche. */
    public string $decesCategorie = '';

    public ?string $erreur = null;

    public ?string $message = null;

    // ------------------------------------------------------------------ outils

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-elevage'), 403);
    }

    private function maintenant(): CarbonImmutable
    {
        return CarbonImmutable::now(config('logialvia.fuseau'));
    }

    private function aujourdhui(): string
    {
        return $this->maintenant()->format('Y-m-d');
    }

    /** Instant de saisie du web, toujours posterieur a la version qu'il remplace. */
    private function instant(?CarbonInterface $apres = null): string
    {
        $t = CarbonImmutable::now('UTC');
        if ($apres !== null && ! $t->greaterThan($apres)) {
            $t = CarbonImmutable::instance($apres)->utc()->addMicrosecond();
        }

        return $t->format('Y-m-d\TH:i:s.u\Z');
    }

    private function entier(string $valeur): ?int
    {
        $valeur = trim(str_replace(' ', '', $valeur));

        return $valeur === '' ? 0 : (preg_match('/^-?\d+$/', $valeur) ? (int) $valeur : null);
    }

    private function texte(string $valeur): ?string
    {
        $valeur = trim($valeur);

        return $valeur === '' ? null : $valeur;
    }

    // ---------------------------------------------------------------- navigation

    public function choisirOnglet(string $onglet): void
    {
        $this->onglet = in_array($onglet, ['registre', 'calendrier', 'infirmerie'], true) ? $onglet : 'registre';
    }

    public function annuler(): void
    {
        $this->modale = null;
        $this->erreur = null;
    }

    private function ouvrir(string $modale): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['espece', 'typeSoin', 'produit', 'dose', 'veterinaire', 'symptomes', 'dejaEffectue', 'intervention', 'sujet', 'motif', 'erreur', 'message']);
        $this->remanence = '0';
        $this->cout = '0';
        $this->niveau = InfirmerieTable::NIVEAUX[0];
        $this->dateSoin = $this->aujourdhui();
        $this->modale = $modale;
    }

    public function nouveauSoin(): void
    {
        $this->ouvrir('soin');
    }

    public function nouvelleIntervention(): void
    {
        $this->ouvrir('intervention');
    }

    public function nouvelleEntree(): void
    {
        $this->ouvrir('entree');
    }

    // -------------------------------------------------------------------- soins

    /** @return array<string, mixed> */
    private function ligneSoin(string $id, string $statut, string $type, int $remanence, int $cout): array
    {
        return [
            'id' => $id,
            'espece' => $this->espece,
            'date_prevue' => $this->dateSoin,
            'type_soin' => $type,
            'statut' => $statut,
            'observations' => null,
            'produit' => $this->texte($this->produit),
            'dose' => $this->texte($this->dose),
            'remanence_jours' => $remanence,
            'veterinaire' => $this->texte($this->veterinaire),
            'symptomes' => $this->texte($this->symptomes),
            'cout_fcfa' => $cout,
            'echeance_prophylaxie_id' => null,
            'bande_id' => $this->bandeId !== '' ? $this->bandeId : null,
            'updated_at' => $this->instant(),
        ];
    }

    /** Changer de lot efface la bande choisie : elle appartenait a l'ancienne filiere. */
    public function updatedEspece(): void
    {
        $this->bandeId = '';
    }

    private function ecrireSoin(array $ligne): ?string
    {
        return app(SoinsCalendrierTable::class)->absorber(Catalogue::POSTE_WEB, $ligne);
    }

    private function especeValide(): bool
    {
        return $this->espece !== '' && array_key_exists($this->espece, FilieresElevage::LIBELLES);
    }

    public function enregistrerSoin(): void
    {
        $this->verifierDroitDeGerer();

        // Les memes controles, dans le meme ordre, que le ViewModel du poste.
        if (! $this->especeValide()) {
            $this->erreur = 'Le lot / la bande est obligatoire.';

            return;
        }
        if (! $this->dateValide()) {
            $this->erreur = 'La date du soin est obligatoire.';

            return;
        }
        if ($this->bandeId !== '' && ! \App\Models\Bande::query()->where('espece', $this->espece)->whereKey($this->bandeId)->exists()) {
            $this->erreur = 'Cette bande n\'appartient pas à cette filière.';

            return;
        }
        if (trim($this->typeSoin) === '') {
            $this->erreur = 'Le type d\'action est obligatoire.';

            return;
        }
        $remanence = $this->entier($this->remanence);
        if ($remanence === null || $remanence < 0) {
            $this->erreur = 'Le délai d\'attente ne peut être négatif.';

            return;
        }
        $cout = $this->entier($this->cout);
        if ($cout === null || $cout < 0) {
            $this->erreur = 'Le coût ne peut être négatif.';

            return;
        }

        $motif = $this->ecrireSoin($this->ligneSoin(
            (string) Str::uuid(),
            $this->dejaEffectue ? 'Effectué' : 'Planifié',
            trim($this->typeSoin),
            $remanence,
            $cout,
        ));
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = 'Soin enregistré avec succès.';
        $this->modale = null;
        $this->erreur = null;
    }

    public function enregistrerIntervention(): void
    {
        $this->verifierDroitDeGerer();

        if (trim($this->intervention) === '') {
            $this->erreur = 'L\'intervention est obligatoire.';

            return;
        }
        if (! $this->especeValide()) {
            $this->erreur = 'Le lot / la bande est obligatoire.';

            return;
        }
        if (! $this->dateValide()) {
            $this->erreur = 'La date du soin est obligatoire.';

            return;
        }

        // Le libelle est libre (« Vaccin Newcastle (Rappel) ») : repris tel quel.
        $motif = $this->ecrireSoin($this->ligneSoin((string) Str::uuid(), 'Planifié', trim($this->intervention), 0, 0));
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = 'Intervention « '.trim($this->intervention).' » planifiée pour le '
            .CarbonImmutable::createFromFormat('!Y-m-d', $this->dateSoin)->format('d/m/Y').'.';
        $this->modale = null;
        $this->erreur = null;
    }

    private function dateValide(): bool
    {
        if (! CarbonImmutable::canBeCreatedFromFormat($this->dateSoin, '!Y-m-d')) {
            return false;
        }

        return CarbonImmutable::createFromFormat('!Y-m-d', $this->dateSoin)->format('Y-m-d') === $this->dateSoin;
    }

    public function confirmerAdministration(string $id): void
    {
        $this->verifierDroitDeGerer();
        $soin = SoinCalendrier::query()->find($id);
        if ($soin === null) {
            return;
        }
        if ($soin->statut === 'Effectué') {
            $this->message = 'Ce soin est déjà marqué comme effectué.';

            return;
        }

        $motif = $this->ecrireSoin([
            'id' => $soin->id,
            'espece' => $soin->espece,
            'date_prevue' => $soin->date_prevue->format('Y-m-d'),
            'type_soin' => $soin->type_soin,
            'statut' => 'Effectué',
            'observations' => $soin->observations,
            'produit' => $soin->produit,
            'dose' => $soin->dose,
            'remanence_jours' => $soin->remanence_jours,
            'veterinaire' => $soin->veterinaire,
            'symptomes' => $soin->symptomes,
            'cout_fcfa' => $soin->cout_fcfa,
            'echeance_prophylaxie_id' => $soin->echeance_prophylaxie_id,
            'updated_at' => $this->instant($soin->updated_at),
        ]);

        $this->message = $motif ?? 'Administration confirmée.';
    }

    // --------------------------------------------------------------- infirmerie

    public function enregistrerEntree(): void
    {
        $this->verifierDroitDeGerer();

        if (trim($this->sujet) === '') {
            $this->erreur = 'Le lot / sujet est obligatoire.';

            return;
        }
        if (trim($this->motif) === '') {
            $this->erreur = 'Le motif est obligatoire.';

            return;
        }

        $motif = app(InfirmerieTable::class)->absorber(Catalogue::POSTE_WEB, [
            'id' => (string) Str::uuid(),
            'date_entree' => $this->aujourdhui(),
            'sujet' => trim($this->sujet),
            'motif' => trim($this->motif),
            'niveau_isolement' => $this->niveau,
            'statut' => 'En cours',
            'date_sortie' => null,
            'espece' => $this->espece !== '' ? $this->espece : null,
            'categorie_mortalite' => null,
            'updated_at' => $this->instant(),
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = 'Entrée d\'infirmerie enregistrée.';
        $this->modale = null;
        $this->erreur = null;
    }

    public function reintegrer(string $id): void
    {
        $this->verifierDroitDeGerer();
        $entree = EntreeInfirmerie::query()->find($id);
        if ($entree === null) {
            return;
        }
        if ($entree->statut !== 'En cours') {
            $this->message = 'Cette entrée est déjà clôturée.';

            return;
        }

        $sortie = max($this->aujourdhui(), $entree->date_entree->format('Y-m-d'));
        $motif = app(InfirmerieTable::class)->absorber(Catalogue::POSTE_WEB, [
            'id' => $entree->id,
            'date_entree' => $entree->date_entree->format('Y-m-d'),
            'sujet' => $entree->sujet,
            'motif' => $entree->motif,
            'niveau_isolement' => $entree->niveau_isolement,
            'statut' => 'Réintégré',
            'date_sortie' => $sortie,
            'espece' => $entree->espece,
            'categorie_mortalite' => null,
            'updated_at' => $this->instant($entree->updated_at),
        ]);

        $this->message = $motif ?? 'Entrée clôturée : réintégré.';
    }

    // -------------------------------------------------------------------- deces

    public function ouvrirDeces(string $id): void
    {
        $this->verifierDroitDeGerer();
        $this->decesEntreeId = $id;
        $this->decesCategorie = '';
        $this->message = $this->erreur = null;
    }

    public function annulerDeces(): void
    {
        $this->decesEntreeId = null;
        $this->decesCategorie = '';
    }

    /**
     * Declare le deces d'un sujet de l'infirmerie, et porte la perte sur la fiche d'elevage de la
     * filiere (cascade comprise) si une categorie est choisie. Comme le poste : la cloture est ecrite
     * AVANT le report, la marque « reportee » APRES lui — un echec en cours de route laisse une
     * entree close et non reportee (etat honnete), jamais une perte comptee deux fois.
     */
    public function declarerDeces(): void
    {
        $this->verifierDroitDeGerer();
        $this->message = $this->erreur = null;
        $entree = $this->decesEntreeId === null ? null : EntreeInfirmerie::query()->find($this->decesEntreeId);
        if ($entree === null) {
            return;
        }
        if ($entree->statut !== 'En cours') {
            $this->message = 'Cette entrée est déjà clôturée.';
            $this->decesEntreeId = null;

            return;
        }
        $categorie = trim($this->decesCategorie) === '' ? null : (ctype_digit(trim($this->decesCategorie)) ? (int) trim($this->decesCategorie) : -1);
        if ($categorie === -1) {
            $this->erreur = "Catégorie d'effectif inconnue pour cette filière.";

            return;
        }
        $espece = $entree->espece;
        if ($categorie !== null && ($espece === null || ! FilieresElevage::existe($espece))) {
            $this->erreur = 'Cette entrée ne désigne aucune filière : le décès ne peut être porté sur aucune fiche.';

            return;
        }
        if ($categorie !== null && $categorie >= FilieresElevage::nombreCategories($espece)) {
            $this->erreur = "Catégorie d'effectif inconnue pour cette filière.";

            return;
        }

        $sortie = max($this->aujourdhui(), $entree->date_entree->format('Y-m-d'));
        $ligne = [
            'id' => $entree->id,
            'date_entree' => $entree->date_entree->format('Y-m-d'),
            'sujet' => $entree->sujet, 'motif' => $entree->motif, 'niveau_isolement' => $entree->niveau_isolement,
            'statut' => 'Décédé', 'date_sortie' => $sortie, 'espece' => $espece,
            'categorie_mortalite' => null,
            'updated_at' => $this->instant($entree->updated_at),
        ];
        $motif = app(InfirmerieTable::class)->absorber(Catalogue::POSTE_WEB, $ligne);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        if ($categorie !== null) {
            $report = (new FichesElevage($espece))->reporterDeces($categorie, $this->aujourdhui());
            if ($report !== null) {
                $this->erreur = "Entrée clôturée, mais la perte n'a pas été portée sur la fiche ($report) Saisissez-la sur la fiche d'élevage.";
                $this->decesEntreeId = null;

                return;
            }
            $ligne['categorie_mortalite'] = $categorie;
            $ligne['updated_at'] = $this->instant(EntreeInfirmerie::query()->find($entree->id)->updated_at);
            $motif = app(InfirmerieTable::class)->absorber(Catalogue::POSTE_WEB, $ligne);
            if ($motif !== null) {
                $this->erreur = $motif;
                $this->decesEntreeId = null;

                return;
            }
        }

        $this->message = $categorie === null ? 'Décès enregistré : la fiche d\'élevage est inchangée.' : 'Décès enregistré : la perte est portée sur la fiche d\'élevage.';
        $this->decesEntreeId = null;
        $this->decesCategorie = '';
    }

    // -------------------------------------------------------------------- rendu

    public function render()
    {
        $maintenant = $this->maintenant();
        $aujourdhui = $maintenant->format('Y-m-d');
        $debutMois = $maintenant->startOfMonth()->format('Y-m-d');

        $tous = SoinCalendrier::query()->orderByDesc('date_prevue')->orderByDesc('serveur_modifie_le')->get();
        $entrees = EntreeInfirmerie::query()->orderByDesc('date_entree')->orderByDesc('serveur_modifie_le')->get();
        $jour = fn (SoinCalendrier $s) => $s->date_prevue->format('Y-m-d');

        // Les 4 KPI du poste (`SoinsViewModel`), a l'identique.
        $kpi = [
            'doses' => $tous->filter(fn ($s) => $s->statut === 'Effectué' && $jour($s) >= $debutMois)->count(),
            'planifiees' => $tous->filter(fn ($s) => $s->statut !== 'Effectué' && $jour($s) >= $aujourdhui)->count(),
            'quarantaine' => $entrees->where('statut', 'En cours')->count() + $tous->where('statut', 'Traitement en cours')->count(),
            'cout' => $tous->filter(fn ($s) => $jour($s) >= $debutMois)->sum('cout_fcfa'),
        ];

        // Delais d'attente en cours : produits non commercialisables.
        $remanences = $tous->filter(function (SoinCalendrier $s) use ($aujourdhui) {
            if ($s->statut !== 'Effectué' || $s->remanence_jours <= 0) {
                return false;
            }

            return $aujourdhui < $s->date_prevue->copy()->addDays($s->remanence_jours)->format('Y-m-d');
        })->values();

        $soins = $tous
            ->when($this->filtreType !== '', fn ($c) => $c->where('type_soin', $this->filtreType))
            ->when($this->filtreEspece !== '', fn ($c) => $c->where('espece', $this->filtreEspece))
            ->values();

        // Calendrier des doses : une ligne par espece ayant un soin ce mois-ci.
        $moisCourant = $tous->filter(fn ($s) => $s->date_prevue->format('Y-m') === $maintenant->format('Y-m'));
        $lignes = $moisCourant->groupBy('espece')->map(
            fn ($groupe) => $groupe->groupBy(fn ($s) => (int) $s->date_prevue->format('j')),
        );

        return view('livewire.soins-calendrier', [
            'soins' => $soins,
            'bandesDeLaFiliere' => $this->espece === '' ? collect() : \App\Models\Bande::query()->where('espece', $this->espece)->orderByDesc('date_mise_en_bande')->get(),
            'codesBande' => \App\Models\Bande::query()->pluck('code', 'id')->all(),
            'entrees' => $entrees,
            'kpi' => $kpi,
            'remanences' => $remanences,
            'lignes' => $lignes,
            'nombreJours' => $maintenant->daysInMonth,
            'jourCourant' => (int) $maintenant->format('j'),
            'moisLibelle' => $maintenant->format('m/Y'),
            'types' => SoinsCalendrierTable::TYPES,
            'niveaux' => InfirmerieTable::NIVEAUX,
            'especes' => collect(FilieresElevage::actives())->mapWithKeys(fn ($e) => [$e => FilieresElevage::libelle($e)])->all(),
            'toutesEspeces' => FilieresElevage::LIBELLES,
            'peutGerer' => Auth::user()?->can('manage-elevage') ?? false,
        ])->title('Soins & Calendrier');
    }
}
