<?php

namespace App\Livewire;

use App\Models\Devis as DevisModele;
use App\Support\ExportXlsx;
use App\Sync\Tables\DevisTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Devis de prestations (Dart : onglet « Devis Prestations » de `ventes_screen.dart`, `47a2_`).
 *
 * Ouvert sur `/ventes/devis` (le composant `Ventes` n'est pas modifie : voir `partiels/lien-devis`).
 * Les devis sont des FAITS (dernier ecrivain gagne). Le web ecrit par `DevisTable::absorber` (device web),
 * jamais par un update direct : meme validation, memes regles que pour un poste.
 *
 * Regles (celles du poste) : numero `DV-WEB-AAAA-NNN` (maximum numerique, suppressions comprises, jamais
 * renumerote) ; seul un devis EMIS se modifie ; un devis ACCEPTE est fige et ne se supprime pas ; supprimer =
 * pierre tombale ; « Expire » se deduit de la date. Un devis n'est ni une vente ni une ecriture comptable.
 * Le droit `manage-ventes` est verifie dans CHAQUE methode d'ecriture, `export-ventes` pour l'export.
 */
#[Layout('components.layouts.app')]
class Devis extends Component
{
    public string $recherche = '';

    /** Vide = « Tous » ; sinon emis, accepte, refuse, expire. */
    public string $filtre = '';

    public bool $formulaire = false;

    public ?string $devisId = null;

    public string $client = '';

    public string $objet = '';

    public string $montant = '';

    public string $validite = '15';

    public ?string $erreur = null;

    public ?string $message = null;

    public ?string $aSupprimer = null;

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-ventes'), 403);
    }

    private function maintenant(): string
    {
        return CarbonImmutable::now('UTC')->format('Y-m-d\TH:i:s.u\Z');
    }

    public function filtrer(string $filtre): void
    {
        $this->filtre = in_array($filtre, ['emis', 'accepte', 'refuse', 'expire'], true) ? $filtre : '';
    }

    public function nouveau(): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['devisId', 'client', 'objet', 'montant', 'erreur', 'message']);
        $this->validite = '15';
        $this->formulaire = true;
    }

    public function modifier(string $id): void
    {
        $this->verifierDroitDeGerer();
        $devis = $this->vivant($id);
        if ($devis === null) {
            return;
        }
        if ($devis->statut !== 'emis') {
            $this->message = "Le devis {$devis->reference} n'est plus « émis » : il ne se modifie plus. Établissez un nouveau devis.";

            return;
        }
        $this->reset(['erreur', 'message']);
        $this->devisId = $devis->id;
        $this->client = $devis->client;
        $this->objet = $devis->objet;
        $m = (float) $devis->montant_estime;
        $this->montant = fmod($m, 1.0) == 0.0 ? (string) (int) $m : (string) $m;
        $this->validite = (string) $devis->validite_jours;
        $this->formulaire = true;
    }

    public function annuler(): void
    {
        $this->formulaire = false;
        $this->aSupprimer = null;
        $this->erreur = null;
    }

    public function enregistrer(): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;

        $montant = str_replace([' ', "\u{202f}", "\u{a0}"], '', $this->montant);
        $montant = str_replace(',', '.', $montant);
        if (trim($this->client) === '') {
            $this->erreur = 'Le client est obligatoire.';

            return;
        }
        if (trim($this->objet) === '') {
            $this->erreur = "L'objet est obligatoire.";

            return;
        }
        if (! is_numeric($montant) || (float) $montant <= 0) {
            $this->erreur = 'Le montant doit être supérieur à 0.';

            return;
        }
        $validite = trim($this->validite) === '' ? '15' : trim($this->validite);
        if (preg_match('/^\d+$/', $validite) !== 1 || (int) $validite < 1) {
            $this->erreur = 'La validité doit être d\'au moins 1 jour.';

            return;
        }

        if ($this->devisId !== null) {
            $existant = $this->vivant($this->devisId);
            if ($existant === null) {
                $this->erreur = 'Ce devis n\'existe plus.';

                return;
            }
            if ($existant->statut !== 'emis') {
                $this->erreur = "Le devis {$existant->reference} n'est plus « émis » : il ne se modifie plus.";

                return;
            }
            $motif = $this->ecrire($this->ligneDe($existant, [
                'client' => trim($this->client),
                'objet' => trim($this->objet),
                'montant_estime' => (float) $montant,
                'validite_jours' => (int) $validite,
            ]));
            if ($motif !== null) {
                $this->erreur = $motif;

                return;
            }
            $this->message = "Devis {$existant->reference} modifié.";
        } else {
            $cree = $this->creer(trim($this->client), trim($this->objet), (float) $montant, (int) $validite);
            if (is_string($cree)) {
                $this->erreur = $cree;

                return;
            }
            $this->message = "Devis {$cree->reference} généré.";
        }

        $this->formulaire = false;
        $this->erreur = null;
    }

    public function dupliquer(string $id): void
    {
        $this->verifierDroitDeGerer();
        $devis = $this->vivant($id);
        if ($devis === null) {
            return;
        }
        $cree = $this->creer($devis->client, $devis->objet, $devis->montant_estime, $devis->validite_jours);
        $this->message = is_string($cree) ? $cree : "Devis {$cree->reference} généré (copie de {$devis->reference}).";
    }

    public function changerStatut(string $id, string $statut): void
    {
        $this->verifierDroitDeGerer();
        $devis = $this->vivant($id);
        if ($devis === null || ! in_array($statut, DevisTable::STATUTS, true)) {
            return;
        }
        if ($devis->statut === $statut) {
            return;
        }
        $motif = $this->ecrire($this->ligneDe($devis, ['statut' => $statut]));
        $this->message = $motif ?? "Devis {$devis->reference} : statut « ".$this->libelleStatut($statut).' ».';
    }

    public function demanderSuppression(string $id): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $devis = $this->vivant($id);
        if ($devis !== null && $devis->statut === 'accepte') {
            $this->message = "Le devis {$devis->reference} est accepté : il engage l'entreprise et ne se supprime pas.";
            $this->aSupprimer = null;

            return;
        }
        $this->aSupprimer = $devis?->id;
    }

    public function confirmerSuppression(): void
    {
        $this->verifierDroitDeGerer();
        $devis = $this->aSupprimer ? $this->vivant($this->aSupprimer) : null;
        $this->aSupprimer = null;
        if ($devis === null) {
            return;
        }
        if ($devis->statut === 'accepte') {
            $this->message = "Le devis {$devis->reference} est accepté : il ne se supprime pas.";

            return;
        }
        $instant = $this->maintenant();
        $motif = $this->ecrire($this->ligneDe($devis, ['supprime_le' => $instant]) + ['updated_at' => $instant]);
        $this->message = $motif ?? "Devis {$devis->reference} supprimé.";
    }

    /** Export XLSX de la liste telle qu'elle est affichee (filtres compris). */
    public function exporter(): StreamedResponse
    {
        abort_unless(Auth::user()?->can('export-ventes'), 403);

        $fuseau = config('logialvia.fuseau');
        $lignes = [['Référence', 'Client', 'Objet', 'Montant estimé (FCFA)', 'Émis le', 'Expire le', 'Statut']];
        foreach ($this->devisFiltres() as $d) {
            $lignes[] = [
                $d->reference,
                $d->client,
                $d->objet,
                (int) round($d->montant_estime),
                $d->date_emission->timezone($fuseau)->format('d/m/Y'),
                $d->dateExpiration()->timezone($fuseau)->format('d/m/Y'),
                $this->libelleAffiche($d),
            ];
        }

        return ExportXlsx::telecharger($lignes, 'devis-prestations.xlsx', 'Devis');
    }

    // ------------------------------------------------------------------ interne

    private function vivant(string $id): ?DevisModele
    {
        return DevisModele::query()->whereNull('supprime_le')->find($id);
    }

    /** La ligne COMPLETE du devis (le serveur absorbe des lignes entieres), avec ce qui change. */
    private function ligneDe(DevisModele $d, array $changements): array
    {
        return array_merge([
            'id' => $d->id,
            'reference' => $d->reference,
            'client' => $d->client,
            'objet' => $d->objet,
            'montant_estime' => $d->montant_estime,
            'validite_jours' => $d->validite_jours,
            'date_emission' => $d->date_emission->utc()->format('Y-m-d\TH:i:s.u\Z'),
            'statut' => $d->statut,
            'supprime_le' => null,
            'updated_at' => $this->maintenant(),
        ], $changements);
    }

    private function ecrire(array $ligne): ?string
    {
        return (new DevisTable)->absorber(Catalogue::POSTE_WEB, $ligne);
    }

    /** `DV-WEB-AAAA-NNN` : maximum NUMERIQUE de l'annee, devis supprimes compris. */
    private function prochaineReference(int $annee): string
    {
        $prefixe = "DV-WEB-$annee-";
        $maximum = 0;
        foreach (DevisModele::query()->where('reference', 'like', $prefixe.'%')->pluck('reference') as $reference) {
            $numero = substr($reference, strlen($prefixe));
            if (ctype_digit($numero) && (int) $numero > $maximum) {
                $maximum = (int) $numero;
            }
        }

        return $prefixe.str_pad((string) ($maximum + 1), 3, '0', STR_PAD_LEFT);
    }

    /** @return DevisModele|string Le devis cree, ou le motif du refus. */
    private function creer(string $client, string $objet, float $montant, int $validite): DevisModele|string
    {
        $annee = (int) CarbonImmutable::now(config('logialvia.fuseau'))->format('Y');
        $motif = null;
        // Deux ecrans qui creent en meme temps : la contrainte d'unicite tranche, on reprend le numero.
        for ($essai = 0; $essai < 3; $essai++) {
            $id = (string) Str::uuid();
            $instant = $this->maintenant();
            $motif = $this->ecrire([
                'id' => $id,
                'reference' => $this->prochaineReference($annee),
                'client' => $client,
                'objet' => $objet,
                'montant_estime' => $montant,
                'validite_jours' => $validite,
                'date_emission' => $instant,
                'statut' => 'emis',
                'supprime_le' => null,
                'updated_at' => $instant,
            ]);
            if ($motif === null) {
                return DevisModele::query()->findOrFail($id);
            }
            if ($motif !== DevisTable::MOTIF_REFERENCE) {
                break;
            }
        }

        return $motif ?? 'Le devis n\'a pas pu être généré.';
    }

    private function libelleStatut(string $statut): string
    {
        return ['emis' => 'Émis', 'accepte' => 'Accepté', 'refuse' => 'Refusé'][$statut] ?? $statut;
    }

    private function estExpire(DevisModele $d): bool
    {
        return $d->statut === 'emis' && CarbonImmutable::now('UTC')->greaterThan($d->dateExpiration());
    }

    private function libelleAffiche(DevisModele $d): string
    {
        return $this->estExpire($d) ? 'Expiré' : $this->libelleStatut($d->statut);
    }

    private function devisFiltres()
    {
        $terme = trim($this->recherche);

        return DevisModele::query()->whereNull('supprime_le')
            ->tap(fn ($q) => \App\Support\RechercheLike::appliquer($q, ['reference', 'client', 'objet'], $terme))
            ->orderByDesc('date_emission')->orderByDesc('reference')->get()
            ->filter(fn (DevisModele $d) => match ($this->filtre) {
                'expire' => $this->estExpire($d),
                'emis' => $d->statut === 'emis' && ! $this->estExpire($d),
                'accepte', 'refuse' => $d->statut === $this->filtre,
                default => true,
            })->values();
    }

    public function render()
    {
        $tous = DevisModele::query()->whereNull('supprime_le')->get();

        return view('livewire.devis', [
            'devis' => $this->devisFiltres(),
            'nombre' => $tous->count(),
            'enAttente' => $tous->filter(fn (DevisModele $d) => $d->statut === 'emis' && ! $this->estExpire($d))->count(),
            'accepte' => (float) $tous->where('statut', 'accepte')->sum('montant_estime'),
            'peutGerer' => Auth::user()?->can('manage-ventes') ?? false,
            'peutExporter' => Auth::user()?->can('export-ventes') ?? false,
            'fuseau' => config('logialvia.fuseau'),
            'aConfirmer' => $this->aSupprimer ? DevisModele::query()->find($this->aSupprimer) : null,
            'libelles' => fn (DevisModele $d) => $this->libelleAffiche($d),
            'expire' => fn (DevisModele $d) => $this->estExpire($d),
        ])->title('Devis Prestations');
    }
}
