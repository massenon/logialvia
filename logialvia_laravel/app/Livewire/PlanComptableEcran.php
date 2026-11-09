<?php

namespace App\Livewire;

use App\Models\EcritureComptable;
use App\Models\PlanComptable;
use App\Services\Comptabilite\LivreComptable;
use App\Sync\DemandesReferentiel;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Plan Comptable (Dart : `PlanComptableScreen`, `plan_comptable_screen.dart`). REFERENTIEL : le
 * serveur fait foi.
 *
 * Toute ecriture (creer, renommer, archiver, reactiver) passe par `DemandesReferentiel::traiter`
 * (type `compte_comptable`) : les MEMES regles que pour un poste (validation, droit
 * `manage-comptabilite`, dernier ecrivain gagne, audit, historique). Le numero ne change jamais :
 * il est la cle des ecritures.
 *
 * Ecart avec le Dart : pas d'export PDF.
 */
#[Layout('components.layouts.app')]
class PlanComptableEcran extends Component
{
    public const CLASSES = [
        '1' => '1 - Capitaux', '2' => '2 - Immobilisations', '3' => '3 - Stocks', '4' => '4 - Tiers',
        '5' => '5 - Trésorerie', '6' => '6 - Charges', '7' => '7 - Produits',
    ];

    public string $recherche = '';

    public string $classe = '';

    public bool $archives = false;

    public bool $formulaire = false;

    /** Numero du compte en modification ; `null` : creation. */
    public ?string $numeroEnEdition = null;

    public string $numero = '';

    public string $libelle = '';

    public string $classeCompte = '';

    public ?string $erreur = null;

    public ?string $message = null;

    /** Compte dont l'archivage attend la confirmation. */
    public ?string $aArchiver = null;

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-comptabilite'), 403);
    }

    public function nouveau(): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['numeroEnEdition', 'numero', 'libelle', 'classeCompte', 'erreur', 'message']);
        $this->formulaire = true;
    }

    public function modifier(string $numero): void
    {
        $this->verifierDroitDeGerer();
        $c = PlanComptable::query()->find($numero);
        if ($c === null) {
            return;
        }
        $this->reset(['erreur', 'message']);
        $this->numeroEnEdition = $c->numero_compte;
        $this->numero = $c->numero_compte;
        $this->libelle = $c->libelle;
        $this->classeCompte = $c->classe;
        $this->formulaire = true;
    }

    public function annuler(): void
    {
        $this->formulaire = false;
        $this->aArchiver = null;
        $this->erreur = null;
    }

    public function enregistrer(): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $numero = trim($this->numero);
        $libelle = trim($this->libelle);
        $classe = $this->classeCompte;

        // Memes controles et memes messages que `ComptabiliteViewModel`.
        if ($this->numeroEnEdition === null) {
            if ($numero === '') {
                $this->erreur = 'Le numéro de compte est obligatoire.';

                return;
            }
            if (preg_match('/^[1-7]\d*$/', $numero) !== 1) {
                $this->erreur = 'Un numéro de compte SYSCOHADA commence par un chiffre de 1 à 7.';

                return;
            }
        } else {
            $numero = $this->numeroEnEdition;
        }
        if ($libelle === '') {
            $this->erreur = 'Le libellé est obligatoire.';

            return;
        }
        if ($classe === '') {
            $this->erreur = 'La classe est obligatoire.';

            return;
        }
        if ($this->numeroEnEdition === null && PlanComptable::query()->whereKey($numero)->exists()) {
            $this->erreur = 'Ce numéro de compte existe déjà.';

            return;
        }
        if (! str_starts_with($numero, $classe)) {
            $this->erreur = $this->numeroEnEdition === null
                ? "Le numéro doit commencer par $classe pour appartenir à cette classe."
                : "Le numéro $numero ne peut pas appartenir à la classe $classe.";

            return;
        }

        $archive = (bool) (PlanComptable::query()->find($numero)?->archive ?? false);
        $motif = $this->proposer(['numero_compte' => $numero, 'libelle' => $libelle, 'classe' => $classe, 'archive' => $archive]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = $this->numeroEnEdition === null ? "Compte $numero créé." : "Compte $numero modifié.";
        $this->formulaire = false;
        $this->erreur = null;
    }

    /** Archiver demande une confirmation ; reactiver, non (comme au poste). */
    public function basculerArchive(string $numero): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;
        $c = PlanComptable::query()->find($numero);
        if ($c === null) {
            return;
        }
        if ($c->archive) {
            $motif = $this->proposer(['numero_compte' => $c->numero_compte, 'libelle' => $c->libelle, 'classe' => $c->classe, 'archive' => false]);
            $this->message = $motif ?? "Compte {$c->numero_compte} réactivé.";

            return;
        }
        $this->aArchiver = $c->numero_compte;
    }

    public function confirmerArchivage(): void
    {
        $this->verifierDroitDeGerer();
        $c = $this->aArchiver !== null ? PlanComptable::query()->find($this->aArchiver) : null;
        $this->aArchiver = null;
        if ($c === null) {
            return;
        }
        $motif = $this->proposer(['numero_compte' => $c->numero_compte, 'libelle' => $c->libelle, 'classe' => $c->classe, 'archive' => true]);
        $this->message = $motif ?? "Compte {$c->numero_compte} archivé.";
    }

    private function proposer(array $donnees): ?string
    {
        $bilan = app(DemandesReferentiel::class)->traiter(Auth::user(), Catalogue::POSTE_WEB, [[
            'id' => (string) Str::uuid(),
            'type' => DemandesReferentiel::TYPE_COMPTE,
            'saisi_le' => now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
            'donnees' => $donnees + ['plan_version' => \App\Support\PlanSyscohada::VERSION],
        ]]);

        return $bilan['rejected'][0]['motif'] ?? null;
    }

    /** Donnees de l'ecran : la vue ET l'export XLSX lisent la meme source. */
    private function donnees(): array
    {
        $terme = mb_strtolower(trim($this->recherche));
        $comptes = PlanComptable::query()->orderBy('numero_compte')->get()
            ->filter(function (PlanComptable $c) use ($terme) {
                if (! $this->archives && $c->archive) {
                    return false;
                }
                if ($this->classe !== '' && $c->classe !== $this->classe) {
                    return false;
                }

                return $terme === ''
                    || str_contains(mb_strtolower($c->libelle), $terme)
                    || str_contains($c->numero_compte, $terme);
            })->values();

        return [
            'comptes' => $comptes,
            'classes' => self::CLASSES,
            'peutGerer' => (bool) Auth::user()?->can('manage-comptabilite'),
            'mouvements' => EcritureComptable::query()->selectRaw('numero_compte, count(*) as n')->groupBy('numero_compte')->pluck('n', 'numero_compte'),
            'exercices' => LivreComptable::exercices(),
        ];
    }

    public function render()
    {
        return view('livewire.comptabilite.plan', $this->donnees())->title('Plan Comptable');
    }

    /** Export XLSX du tableau affiche (memes filtres) : `view-comptabilite`, verifie ici. */
    public function exporter(): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        abort_unless(\Illuminate\Support\Facades\Auth::user()?->can('view-comptabilite'), 403);

        $d = $this->donnees();
        $lignes = [['Plan Comptable SYSCOHADA'], ['Compte', 'Libellé', 'Classe', 'Statut']];
        foreach ($d['comptes'] as $c) {
            $lignes[] = [$c->numero_compte, $c->libelle, $c->classe, $c->archive ? 'Archivé' : 'Actif'];
        }

        return \App\Support\ExportXlsx::telecharger($lignes, 'plan-comptable.xlsx', 'Plan Comptable');
    }
}
