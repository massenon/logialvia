<?php

namespace App\Livewire;

use App\Models\Facture;
use App\Models\Poste;
use App\Sync\Tables\FacturesTable;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Facturation MeCeF — factures de vente (FV) et factures d'avoir (FA) (Dart :
 * `factures_mecef_screen.dart`, `factures_mecef_view_model.dart`, `facture_mecef.dart`).
 *
 * LECTURE SEULE. Une facture est une PIECE FISCALE emise par le poste, qui detient le jeton e-MECeF
 * (coffre du systeme) et l'URL du service : **le web ne transmet RIEN a la DGI**, n'emet aucune
 * facture, ne saisit aucun code de normalisation, ne cree aucun avoir et n'exporte aucun PDF
 * (ecarts declares dans l'ecran et dans `46e_` §5). Il n'y a donc aucune methode d'ecriture, et
 * aucun droit `manage-facturation` a verifier ; la lecture exige `view-facturation` (route) et le
 * module `mecef` actif (reglage de l'entreprise).
 *
 * Les indicateurs reprennent ceux du Dart a l'identique : « Facture Net » = factures de vente
 * moins avoirs (additionner les deux gonflerait le chiffre) ; « Normalisees » exige un code
 * reellement rendu par la DGI (`estNormalisee`), jamais le seul statut.
 */
#[Layout('components.layouts.app')]
class FacturesMecef extends Component
{
    /** Chaine vide = « Toutes » ; sinon un statut de `FacturesTable::STATUTS`. */
    public string $statut = '';

    public string $recherche = '';

    public ?string $factureId = null;

    public function filtrer(string $statut): void
    {
        $this->statut = in_array($statut, FacturesTable::STATUTS, true) ? $statut : '';
    }

    public function ouvrir(string $id): void
    {
        $this->factureId = Facture::query()->whereKey($id)->exists() ? $id : null;
    }

    public function fermer(): void
    {
        $this->factureId = null;
    }

    /** Poste d'emission : son code (`P2`), ou repli sur l'identifiant tronque. */
    private function libellePoste(string $deviceId): string
    {
        $code = Poste::query()->where('device_id', $deviceId)->value('code');

        return $code ?: 'Poste '.Str::substr($deviceId, 0, 8);
    }

    /** Cumul par groupe de taxe, dans l'ordre des lettres (`totauxParGroupe`). */
    private function totauxParGroupe(Facture $facture): array
    {
        $groupes = [];
        foreach ($facture->lignes as $l) {
            $groupes[$l->groupe_taxe] ??= ['groupe' => $l->groupe_taxe, 'taux' => $l->taux_taxe, 'base' => 0.0, 'taxe' => 0.0];
            $groupes[$l->groupe_taxe]['base'] += $l->montant_ht;
            $groupes[$l->groupe_taxe]['taxe'] += $l->montant_taxe;
        }
        ksort($groupes);

        return array_values($groupes);
    }

    public function render()
    {
        $toutes = Facture::query()->get(['type', 'statut', 'total_ttc', 'code_mecef']);

        $terme = trim($this->recherche);
        $echappe = addcslashes($terme, '%_\\');
        $factures = Facture::query()
            ->when(in_array($this->statut, FacturesTable::STATUTS, true), fn ($q) => $q->where('statut', $this->statut))
            ->when($terme !== '', fn ($q) => $q->where(fn ($w) => $w
                ->whereRaw("reference like ? escape '\\'", ["%$echappe%"])
                ->orWhereRaw("client like ? escape '\\'", ["%$echappe%"])))
            ->orderByDesc('date_facture')->orderByDesc('reference')->get();

        $ouverte = $this->factureId
            ? Facture::query()->with(['lignes' => fn ($q) => $q->orderBy('designation')->orderBy('id')])->find($this->factureId)
            : null;

        return view('livewire.factures-mecef', [
            'factures' => $factures,
            // Facture net : les factures de vente moins les avoirs.
            'factureNet' => (float) $toutes->sum(fn (Facture $f) => $f->type === 'FV' ? $f->total_ttc : -$f->total_ttc),
            'aTransmettre' => $toutes->where('statut', 'a_transmettre')->count(),
            // « Normalisee » = un code reellement rendu par la DGI, pas le seul statut.
            'normalisees' => $toutes->filter(fn (Facture $f) => $f->statut === 'normalisee' && trim((string) $f->code_mecef) !== '')->count(),
            'rejetees' => $toutes->where('statut', 'rejetee')->count(),
            'ouverte' => $ouverte,
            'totauxParGroupe' => $ouverte ? $this->totauxParGroupe($ouverte) : [],
            'posteEmission' => $ouverte ? $this->libellePoste($ouverte->device_id) : null,
            'fuseau' => config('logialvia.fuseau'),
            'libellesStatut' => ['a_transmettre' => 'À transmettre', 'normalisee' => 'Normalisée', 'rejetee' => 'Rejetée'],
        ])->title('Facturation MeCeF');
    }
}
