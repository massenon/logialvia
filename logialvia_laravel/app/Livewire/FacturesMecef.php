<?php

namespace App\Livewire;

use App\Models\Facture;
use App\Models\Poste;
use App\Models\Vente;
use App\Support\CalculFacture;
use App\Support\ExportXlsx;
use App\Sync\Tables\FacturesTable;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use InvalidArgumentException;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Facturation MeCeF — factures de vente (FV) et factures d'avoir (FA) (Dart :
 * `factures_mecef_screen.dart`, `factures_mecef_view_model.dart`, `facture_mecef.dart`).
 *
 * Le web **emet** une facture de vente (a partir d'une vente existante, une seule par vente) et un **avoir** (sur une
 * facture de vente connue, jamais au-dela de son total), avec le calcul HT/TVA/TTC du poste (`CalculFacture`), les
 * numeros `FV-WEB-AAAA-NNN` / `FA-WEB-AAAA-NNN` (maximum numerique, jamais renumerotes) et le statut « A transmettre ».
 * Les ecritures passent par `FacturesTable::absorber` (device web), jamais par un update direct ; `manage-facturation`
 * est verifie dans CHAQUE methode d'ecriture. Une facture est IMMUABLE : aucune methode ne la modifie ni ne la supprime ;
 * un statut ne regresse jamais ; aucune ecriture comptable n'est generee (la vente l'a deja fait).
 *
 * **Le web ne transmet RIEN a la DGI et ne stocke aucun secret** : ni jeton ni URL e-MECeF, aucun client HTTP. Une
 * facture emise au web n'a pas de poste emetteur : n'importe quel poste appaire (droit `manage-facturation`) peut la
 * transmettre, apres l'avoir RESERVEE au serveur (`FacturesTable::reserverTransmission`) — voir `47a2_`.
 *
 * Les indicateurs reprennent ceux du Dart a l'identique : « Facture Net » = factures de vente moins avoirs ;
 * « Normalisees » exige un code reellement rendu par la DGI (`estNormalisee`), jamais le seul statut.
 * La vue imprimable est servie par `FactureImprimableController` (`/factures-mecef/{facture}/imprimer`).
 */
#[Layout('components.layouts.app')]
class FacturesMecef extends Component
{
    /** Chaine vide = « Toutes » ; sinon un statut de `FacturesTable::STATUTS`. */
    public string $statut = '';

    public string $recherche = '';

    public ?string $factureId = null;

    // --- Emission d'une facture de vente ---
    public bool $emission = false;

    public ?string $venteId = null;

    public string $ifu = '';

    public string $adresse = '';

    // --- Emission d'un avoir ---
    public ?string $avoirSur = null;

    public string $avoirMotif = '';

    public bool $avoirTotal = true;

    /** @var array<string, string> ligne de la facture d'origine => quantite creditee (avoir partiel) */
    public array $avoirQuantites = [];

    public ?string $erreur = null;

    public ?string $message = null;

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

    // ------------------------------------------------------------------ Ecriture

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-facturation'), 403);
    }

    private function maintenant(): string
    {
        return CarbonImmutable::now('UTC')->format('Y-m-d\TH:i:s.u\Z');
    }

    public function ouvrirEmission(): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['venteId', 'ifu', 'adresse', 'erreur', 'message', 'avoirSur']);
        $this->emission = true;
    }

    public function ouvrirAvoir(string $id): void
    {
        $this->verifierDroitDeGerer();
        $origine = Facture::query()->where('type', 'FV')->find($id);
        $this->reset(['avoirMotif', 'avoirQuantites', 'erreur', 'message', 'emission']);
        $this->avoirTotal = true;
        $this->avoirSur = $origine?->id;
    }

    public function annulerSaisie(): void
    {
        $this->emission = false;
        $this->avoirSur = null;
        $this->erreur = null;
    }

    /** Emet la facture de vente d'une vente (une seule facture de vente par vente). */
    public function emettre(): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;

        $vente = $this->venteId ? Vente::query()->find($this->venteId) : null;
        if ($vente === null) {
            $this->erreur = 'Choisissez la vente à facturer.';

            return;
        }
        if ($vente->status === 'Annulée') {
            $this->erreur = "La vente {$vente->reference} est annulée : elle ne peut pas être facturée.";

            return;
        }
        $deja = $this->factureDeLaVente($vente, $this->facturesDeVentes());
        if ($deja !== null) {
            $this->erreur = "La vente {$vente->reference} porte déjà la facture {$deja->reference}. Pour la corriger, émettez un avoir.";

            return;
        }
        $ifu = trim($this->ifu);
        $adresse = trim($this->adresse);
        if (mb_strlen($ifu) > 40 || mb_strlen($adresse) > 255) {
            $this->erreur = "L'IFU (40 caractères) ou l'adresse (255 caractères) est trop long.";

            return;
        }

        try {
            $lignes = CalculFacture::lignesDeVente($vente);
        } catch (InvalidArgumentException $e) {
            $this->erreur = $e->getMessage();

            return;
        }

        $resultat = $this->emettreLigne('FV', $vente->date_vente->utc(), [
            'vente_ref' => $vente->reference,
            'origine_ref' => null,
            'motif' => null,
            'client' => $vente->client,
            'client_ifu' => $ifu === '' ? null : $ifu,
            'client_adresse' => $adresse === '' ? null : $adresse,
        ], $lignes);
        if (is_string($resultat)) {
            $this->erreur = $resultat;

            return;
        }

        $this->message = "Facture {$resultat->reference} émise (à transmettre depuis un poste).";
        $this->emission = false;
        $this->erreur = null;
        $this->factureId = $resultat->id;
    }

    /** Emet un avoir sur une facture de vente : total, ou partiel ligne a ligne ; jamais au-dela de la facture. */
    public function emettreAvoir(): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;

        $origine = $this->avoirSur ? Facture::query()->where('type', 'FV')->find($this->avoirSur) : null;
        if ($origine === null) {
            $this->erreur = 'Facture de vente introuvable : un avoir ne se fait que sur une facture de vente.';

            return;
        }
        if ($origine->portee_reference !== '') {
            $this->erreur = "La facture {$origine->reference} n'a pas de numéro de poste (émise avant l'appairage) : son avoir s'émet depuis son poste.";

            return;
        }
        $motif = trim($this->avoirMotif);
        if ($motif === '') {
            $this->erreur = "Un avoir sans motif n'explique rien : motif requis.";

            return;
        }
        if (mb_strlen($motif) > 255) {
            $this->erreur = "Le motif de l'avoir est trop long (255 caractères).";

            return;
        }

        $quantites = null;
        if (! $this->avoirTotal) {
            $quantites = [];
            foreach ($this->avoirQuantites as $ligneId => $texte) {
                $texte = str_replace(',', '.', trim((string) $texte));
                if ($texte === '') {
                    continue;
                }
                if (! is_numeric($texte) || (float) $texte < 0) {
                    $this->erreur = 'Une quantité créditée est invalide.';

                    return;
                }
                $quantites[$ligneId] = (float) $texte;
            }
        }

        try {
            $lignes = CalculFacture::lignesAvoir($origine, $quantites);
        } catch (InvalidArgumentException $e) {
            $this->erreur = $e->getMessage();

            return;
        }

        // Un avoir ne depasse jamais la facture qu'il corrige : avec les avoirs deja emis, le cumul reste dans son
        // total TTC (tolerance d'arrondi 0,01).
        $nouveau = CalculFacture::totaux($lignes)['total_ttc'];
        $deja = (float) Facture::query()->where('type', 'FA')->where('origine_ref', $origine->reference)->sum('total_ttc');
        if ($deja + $nouveau > $origine->total_ttc + 0.01) {
            $this->erreur = sprintf(
                'Les avoirs sur %s dépasseraient la facture : %s FCFA déjà crédités, %s demandés, facture de %s FCFA.',
                $origine->reference,
                number_format($deja, 0, ',', ' '),
                number_format($nouveau, 0, ',', ' '),
                number_format($origine->total_ttc, 0, ',', ' '),
            );

            return;
        }

        $resultat = $this->emettreLigne('FA', CarbonImmutable::now('UTC'), [
            'vente_ref' => null,
            'origine_ref' => $origine->reference,
            'motif' => $motif,
            'client' => $origine->client,
            'client_ifu' => $origine->client_ifu,
            'client_adresse' => $origine->client_adresse,
        ], $lignes);
        if (is_string($resultat)) {
            $this->erreur = $resultat;

            return;
        }

        $this->message = "Avoir {$resultat->reference} émis sur {$origine->reference}.";
        $this->avoirSur = null;
        $this->erreur = null;
        $this->factureId = $resultat->id;
    }

    /** Export XLSX de la liste telle qu'elle est affichee (filtres compris). */
    public function exporter(): StreamedResponse
    {
        abort_unless(Auth::user()?->can('view-facturation'), 403);

        $fuseau = config('logialvia.fuseau');
        $lignes = [['Référence', 'Date', 'Client', 'Facture corrigée', 'Total TTC (FCFA)', 'Statut']];
        foreach ($this->facturesFiltrees() as $f) {
            $lignes[] = [
                $f->reference,
                $f->date_facture->timezone($fuseau)->format('d/m/Y'),
                $f->client,
                $f->origine_ref,
                (int) round(($f->type === 'FA' ? -1 : 1) * $f->total_ttc),
                self::LIBELLES_STATUT[$f->statut],
            ];
        }

        return ExportXlsx::telecharger($lignes, 'factures-mecef.xlsx', 'Factures');
    }

    // ------------------------------------------------------------------ Interne

    private const LIBELLES_STATUT = ['a_transmettre' => 'À transmettre', 'normalisee' => 'Normalisée', 'rejetee' => 'Rejetée'];

    /** Factures de vente rattachees a une vente (pour « une seule facture par vente »). */
    private function facturesDeVentes(): Collection
    {
        return Facture::query()->where('type', 'FV')->whereNotNull('vente_ref')->get(['id', 'reference', 'vente_ref', 'device_id']);
    }

    /**
     * La facture de vente de cette vente, s'il y en a une. Une reference de vente a code (`V-P2-…`) est globale ;
     * sans code, elle est propre a son poste : seule compte la facture de CE poste ou celle emise au web.
     */
    private function factureDeLaVente(Vente $vente, Collection $factures): ?Facture
    {
        $globale = preg_match('/^V-(P\d+|WEB)-\d{4}-\d{3,}$/', $vente->reference) === 1;

        return $factures->first(fn (Facture $f) => $f->vente_ref === $vente->reference
            && ($globale || in_array($f->device_id, [$vente->device_id, Catalogue::POSTE_WEB], true)));
    }

    /** `FV-WEB-AAAA-NNN` / `FA-WEB-AAAA-NNN` : maximum NUMERIQUE de l'annee (un tri textuel mettrait 1000 avant 999). */
    private function prochaineReference(string $type, int $annee): string
    {
        $prefixe = "$type-WEB-$annee-";
        $maximum = 0;
        foreach (Facture::query()->where('reference', 'like', $prefixe.'%')->pluck('reference') as $reference) {
            $numero = substr($reference, strlen($prefixe));
            if (ctype_digit($numero) && (int) $numero > $maximum) {
                $maximum = (int) $numero;
            }
        }

        return $prefixe.str_pad((string) ($maximum + 1), 3, '0', STR_PAD_LEFT);
    }

    /**
     * Ecrit la facture par la table de synchronisation (memes validations qu'un poste).
     *
     * @param  array<string, mixed>  $entete
     * @param  list<array<string, mixed>>  $lignes
     * @return Facture|string La facture creee, ou le motif du refus.
     */
    private function emettreLigne(string $type, CarbonInterface $date, array $entete, array $lignes): Facture|string
    {
        $date = CarbonImmutable::instance($date)->utc();
        $annee = (int) $date->timezone(config('logialvia.fuseau'))->format('Y');
        $motif = null;
        // Deux ecrans qui emettent en meme temps : la contrainte d'unicite tranche, on reprend le numero.
        for ($essai = 0; $essai < 3; $essai++) {
            $id = (string) Str::uuid();
            $motif = (new FacturesTable)->absorber(Catalogue::POSTE_WEB, array_merge($entete, CalculFacture::totaux($lignes), [
                'id' => $id,
                'reference' => $this->prochaineReference($type, $annee),
                'type' => $type,
                'date_facture' => $date->format('Y-m-d\TH:i:s.u\Z'),
                'statut' => 'a_transmettre',
                'code_mecef' => null,
                'nim' => null,
                'compteur' => null,
                'lien_verification' => null,
                'date_normalisation' => null,
                'erreur_transmission' => null,
                'updated_at' => $this->maintenant(),
                'lignes' => $lignes,
            ]));
            if ($motif === null) {
                return Facture::query()->findOrFail($id);
            }
            if ($motif !== FacturesTable::MOTIF_REFERENCE) {
                break;
            }
        }

        return $motif ?? "La facture n'a pas pu être émise.";
    }

    /** Factures de l'ecran : filtre de statut et recherche (jokers `%` et `_` litteraux). */
    private function facturesFiltrees(): Collection
    {
        $terme = trim($this->recherche);

        return Facture::query()
            ->when(in_array($this->statut, FacturesTable::STATUTS, true), fn ($q) => $q->where('statut', $this->statut))
            ->tap(fn ($q) => \App\Support\RechercheLike::appliquer($q, ['reference', 'client'], $terme))
            ->orderByDesc('date_facture')->orderByDesc('reference')->get();
    }

    /** Ventes non annulees qui n'ont pas encore de facture de vente. */
    private function ventesAFacturer(): Collection
    {
        $factures = $this->facturesDeVentes();

        return Vente::query()->where('status', '!=', 'Annulée')->orderByDesc('date_vente')->limit(300)->get()
            ->filter(fn (Vente $v) => $this->factureDeLaVente($v, $factures) === null)->values();
    }

    /** Poste d'emission : son code (`P2`), ou repli sur l'identifiant tronque. */
    private function libellePoste(string $deviceId): string
    {
        if ($deviceId === Catalogue::POSTE_WEB) {
            return 'Web';
        }
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

        $factures = $this->facturesFiltrees();

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
            'libellesStatut' => self::LIBELLES_STATUT,
            'peutGerer' => Auth::user()?->can('manage-facturation') ?? false,
            'ventesAFacturer' => $this->emission ? $this->ventesAFacturer() : collect(),
            'origineAvoir' => $this->avoirSur ? Facture::query()->with(['lignes' => fn ($q) => $q->orderBy('id')])->find($this->avoirSur) : null,
            'dejaCredite' => $this->avoirSur ? (float) Facture::query()->where('type', 'FA')->where('origine_ref', Facture::query()->whereKey($this->avoirSur)->value('reference'))->sum('total_ttc') : 0.0,
        ])->title('Facturation MeCeF');
    }
}
