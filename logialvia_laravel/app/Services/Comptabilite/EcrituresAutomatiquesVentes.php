<?php

namespace App\Services\Comptabilite;

use App\Livewire\Catalogue;
use App\Models\PieceComptable;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use App\Models\GroupeTaxe;
use App\Support\PlanSyscohada;
use App\Sync\Tables\EcrituresTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Ecritures AUTOMATIQUES des ventes — PORT FIDELE de `generer_ecritures_automatiques.dart` (BR-CPT-003)
 * et de `_ventiler*` de `ventes_repository_drift.dart`. Le Dart est la source.
 *
 * ## Schemas (identiques au poste, jeu chiffre a la main : `47a_COMMERCE_PARITE.md` §3)
 *
 * Vente comptant de 12 000 F (goliaths) :
 * ```
 * 571 Caisse                 D 12 000
 * 702 Ventes produits finis          C 12 000   (centre Goliaths)
 * ```
 * Vente a credit (avance) de 15 500 F dont 4 000 F encaisses en Mobile Money :
 * ```
 * 552 Mobile Money           D  4 000
 * 411 Clients                D 11 500
 * 702 Ventes produits finis          C  6 000   (Goliaths)
 * 702 Ventes produits finis          C  6 500   (Pintades)
 * 701 Ventes marchandises            C  3 000   (Commerce Annexe)
 * ```
 * Produit taxable a 18 % de 11 800 F TTC (TVA arrondie au franc, comme le poste) :
 * ```
 * 571 Caisse                 D 11 800
 * 701 Ventes marchandises            C 10 000
 * 4431 TVA facturee sur ventes       C  1 800
 * ```
 * Recouvrement : `571/552 D` / `411 C`, piece `REG-<reference>`, journal `CA`.
 * Plan : `App\Support\PlanSyscohada` (`47p_`).
 *
 * ## Ou le web s'ecarte du poste (a valider : `47a_` §5)
 * - **Annulation** : le poste recalcule l'ecriture inverse depuis la vente (mode, `paye` courant, categorie
 *   COURANTE des produits) ; le web contrepasse **ce que le grand livre porte reellement** pour cette vente
 *   (somme nette par compte et centre de toutes ses pieces). Meme resultat dans le cas courant, mais jamais
 *   un compte different si un produit a change de categorie, ni une tresorerie fausse si le recouvrement a ete
 *   fait par un autre moyen que la vente. Et une vente deja contrepassee ne l'est pas deux fois.
 * - **Atomicite** : le poste avale l'echec d'une ecriture (mois cloture) et garde la vente SANS ecriture ;
 *   le web refuse l'operation entiere, avec le motif du serveur.
 * - **Frais de livraison facturee** : credites en 7071 (sans centre), TVA au 4432 si le panier est taxable.
 *
 * Les ecritures passent par `EcrituresTable::absorber` (equilibre, plan, verrous de periode, droits) : jamais
 * d'insertion directe. Le droit est `manage-ventes` (piece AUTOMATIQUE : `vente_ref`).
 */
final class EcrituresAutomatiquesVentes
{
    public const CENTRE_COMMERCE_ANNEXE = 'Commerce Annexe';

    /** Filiere (`produits_vendables.espece`) → centre analytique. */
    private const CENTRES = [
        'goliaths' => 'Goliaths',
        'pintades' => 'Pintades',
        'lapins' => 'Lapins',
        'escargots' => 'Escargots',
        'ovins' => 'Ovins',
        'poissons-chats' => 'Poissons-Chats',
        'poulets' => 'Poulets',
        'pondeuses' => 'Pondeuses',
    ];

    public function __construct(private readonly User $utilisateur) {}

    // ------------------------------------------------------- constructeurs de lignes (purs)

    /** Compte de tresorerie du mode de reglement : Mobile Money → 552, tout le reste → 571. */
    public static function tresoreriePour(string $mode): string
    {
        return PlanSyscohada::tresoreriePour($mode);
    }

    /** Taux de TVA (en %) par groupe de taxe : le prix d'une ligne de vente est TTC (A exonere : 0, B : 18). */
    private static function tauxParGroupe(): array
    {
        return GroupeTaxe::query()->pluck('taux', 'code')->map(fn ($t) => (float) $t)->all();
    }

    /**
     * Cle de ventilation d'un produit : « Commerce Annexe » → 701 ; sinon 702, centre = filiere du produit
     * (`null` : produit d'elevage sans filiere identifiee, jamais rattache arbitrairement), plus le taux de
     * TVA (en %) du groupe de taxe du produit.
     *
     * @param  array<string, float>|null  $taux  taux par groupe (charge si omis)
     * @return array{0: string, 1: ?string, 2: float} [compte, centre, taux]
     */
    public static function cleDeVentilation(?ProduitVendable $produit, ?array $taux = null): array
    {
        $taux ??= self::tauxParGroupe();
        $tauxProduit = (float) ($taux[$produit?->groupe_taxe ?? 'A'] ?? 0.0);
        if ($produit?->cat === 'Commerce Annexe') {
            return [PlanSyscohada::VENTES_MARCHANDISES, self::CENTRE_COMMERCE_ANNEXE, $tauxProduit];
        }

        return [PlanSyscohada::VENTES_PRODUITS_FINIS, self::CENTRES[$produit?->espece] ?? null, $tauxProduit];
    }

    /**
     * Taux des frais de livraison facturee : celui du panier s'il est unique, sinon 0 (exonere). Meme regle
     * que le poste (`_tauxLivraison`).
     *
     * @param  list<array{compte: string, axe: ?string, taux: float, montant: float}>  $ventilation
     */
    public static function tauxLivraison(array $ventilation): float
    {
        $taux = array_values(array_unique(array_map(fn (array $v) => (float) $v['taux'], $ventilation)));

        return count($taux) === 1 ? $taux[0] : 0.0;
    }

    /**
     * Ventile des lignes `[produit_id, montant]` (TTC) par (compte, centre, taux), dans l'ordre d'apparition.
     *
     * @param  iterable<array{produit_id: string, montant: float}>  $lignes
     * @return list<array{compte: string, axe: ?string, taux: float, montant: float}>
     */
    public static function ventiler(iterable $lignes): array
    {
        $ventilation = [];
        $taux = self::tauxParGroupe();
        foreach ($lignes as $ligne) {
            [$compte, $axe, $t] = self::cleDeVentilation(ProduitVendable::query()->find($ligne['produit_id']), $taux);
            $cle = $compte.'|'.($axe ?? '').'|'.$t;
            $ventilation[$cle] ??= ['compte' => $compte, 'axe' => $axe, 'taux' => $t, 'montant' => 0.0];
            $ventilation[$cle]['montant'] += (float) $ligne['montant'];
        }

        return array_values($ventilation);
    }

    /**
     * Lignes de l'ecriture d'une vente. `[]` si le total n'est pas positif (rien a ecrire).
     *
     * @param  list<array{compte: string, axe: ?string, taux: float, montant: float}>  $ventilation  montants TTC
     * @return list<array{compte: string, debit: float, credit: float, libelle: string, axe: ?string}>
     */
    public static function lignesVente(
        string $reference,
        string $mode,
        float $total,
        float $paye,
        array $ventilation,
        float $fraisLivraison = 0.0,
        float $tauxLivraison = 0.0,
    ): array {
        if ($total <= 0) {
            return [];
        }

        $lignes = [];
        $resteDu = min(max($total - $paye, 0.0), $total);

        if ($paye > 0) {
            $lignes[] = self::ligne(self::tresoreriePour($mode), $paye, 0, "Encaissement vente $reference");
        }
        if ($resteDu > 0) {
            $lignes[] = self::ligne(PlanSyscohada::CLIENTS, $resteDu, 0, "Créance client — vente $reference");
        }
        // Produits HT ; la TVA collectee est UNE ligne par nature (biens 4431, prestations 4432) : le resultat
        // ne contient plus de TVA.
        $tvaBiens = 0.0;
        foreach ($ventilation as $v) {
            if ($v['montant'] <= 0) {
                continue;
            }
            $tva = PlanSyscohada::tvaDuTtc($v['montant'], $v['taux']);
            $tvaBiens += $tva;
            $lignes[] = self::ligne(
                $v['compte'], 0, $v['montant'] - $tva,
                $v['axe'] === null ? "Vente $reference" : "Vente $reference — {$v['axe']}",
                $v['axe'],
            );
        }
        if ($tvaBiens > 0) {
            $lignes[] = self::ligne(PlanSyscohada::TVA_COLLECTEE, 0, $tvaBiens, "TVA collectée — vente $reference");
        }
        // Les frais d'une livraison facturee sont DANS le total : sans cette ligne, la piece serait
        // desequilibree de leur montant.
        if ($fraisLivraison > 0) {
            $tvaLivraison = PlanSyscohada::tvaDuTtc($fraisLivraison, $tauxLivraison);
            $lignes[] = self::ligne(PlanSyscohada::FRAIS_LIVRAISON, 0, $fraisLivraison - $tvaLivraison, "Frais de livraison facturés — vente $reference");
            if ($tvaLivraison > 0) {
                $lignes[] = self::ligne(PlanSyscohada::TVA_COLLECTEE_SERVICES, 0, $tvaLivraison, "TVA collectée sur livraison — vente $reference");
            }
        }

        return $lignes;
    }

    /** Lignes du recouvrement d'une creance : tresorerie au debit, clients au credit. */
    public static function lignesReglement(string $reference, string $mode, float $montant): array
    {
        if ($montant <= 0) {
            return [];
        }

        return [
            self::ligne(self::tresoreriePour($mode), $montant, 0, "Encaissement créance $reference"),
            self::ligne(PlanSyscohada::CLIENTS, 0, $montant, "Encaissement créance $reference"),
        ];
    }

    /**
     * Ecriture INVERSE de tout ce que le grand livre porte pour cette vente : somme nette (debit − credit) par
     * (compte, centre) des pieces de la vente, sens oppose. Vide si tout est deja soldé (déjà contrepassée).
     *
     * @param  iterable<array{compte: string, axe: ?string, net: float}>  $nets
     * @return list<array{compte: string, debit: float, credit: float, libelle: string, axe: ?string}>
     */
    public static function lignesAnnulation(string $reference, iterable $nets): array
    {
        $lignes = [];
        foreach ($nets as $n) {
            $net = round($n['net'], 2);
            if (abs($net) < Verrous::TOLERANCE) {
                continue;
            }
            // Un solde debiteur se solde au credit, et inversement.
            $lignes[] = self::ligne(
                $n['compte'], $net < 0 ? -$net : 0, $net > 0 ? $net : 0, "Annulation vente $reference", $n['axe'],
            );
        }

        // Debits d'abord, comme le poste (tresorerie / clients au credit, produits au debit).
        usort($lignes, fn (array $a, array $b) => $b['debit'] <=> $a['debit']);

        return $lignes;
    }

    private static function ligne(string $compte, float $debit, float $credit, string $libelle, ?string $axe = null): array
    {
        return ['compte' => $compte, 'debit' => $debit, 'credit' => $credit, 'libelle' => $libelle, 'axe' => $axe];
    }

    // ----------------------------------------------------------------- lecture du grand livre

    /**
     * Pieces du grand livre qui portent cette vente. Une reference a code de poste ou du web est globale ;
     * une ancienne reference sans code ne l'est pas : on ne prend alors que les pieces du poste de la vente
     * (et celles que le web a passees pour elle).
     *
     * @return Collection<int, PieceComptable>
     */
    public static function piecesDeLaVente(Vente $vente): Collection
    {
        return PieceComptable::query()->with('lignes')
            ->where('vente_ref', $vente->reference)
            ->when($vente->portee_reference !== '', fn ($q) => $q->whereIn('device_id', [$vente->device_id, Catalogue::POSTE_WEB]))
            ->orderBy('date_ecriture')->get();
    }

    /**
     * Soldes nets (debit − credit) par (compte, centre) de l'ensemble des pieces de la vente.
     *
     * @return list<array{compte: string, axe: ?string, net: float}>
     */
    public static function netsDeLaVente(Vente $vente): array
    {
        $nets = [];
        foreach (self::piecesDeLaVente($vente) as $piece) {
            foreach ($piece->lignes as $l) {
                $cle = $l->numero_compte.'|'.($l->axe_analytique ?? '');
                $nets[$cle] ??= ['compte' => $l->numero_compte, 'axe' => $l->axe_analytique, 'net' => 0.0];
                $nets[$cle]['net'] += $l->debit - $l->credit;
            }
        }

        return array_values($nets);
    }

    // ------------------------------------------------------------------------- enregistrement

    /**
     * Passe UNE piece automatique par `EcrituresTable::absorber`, comme un poste (device `WEB`).
     *
     * @param  list<array{compte: string, debit: float, credit: float, libelle: string, axe: ?string}>  $lignes
     * @return string|null Le motif du refus, ou `null` si la piece est acceptee.
     */
    public function enregistrer(
        CarbonImmutable $date,
        string $journal,
        string $numeroPiece,
        array $lignes,
        string $venteRef,
    ): ?string {
        if ($lignes === []) {
            return null;
        }
        [$annee] = Verrous::anneeMois($date);

        $piece = [
            'id' => (string) Str::uuid(),
            'numero_piece' => $numeroPiece,
            'date_ecriture' => $date->utc()->format('Y-m-d\TH:i:s.u\Z'),
            'exercice_annee' => $annee,
            'journal_code' => $journal,
            'vente_ref' => $venteRef,
            'achat_ref' => null,
            'contrepasse_de' => null,
            'plan_version' => PlanSyscohada::VERSION,
            'updated_at' => Saisie::instantMaintenant(),
            'lignes' => array_map(fn (array $l) => [
                'id' => (string) Str::uuid(),
                'numero_compte' => $l['compte'],
                'debit' => (float) $l['debit'],
                'credit' => (float) $l['credit'],
                'libelle' => $l['libelle'],
                'axe_analytique' => $l['axe'] ?? null,
            ], $lignes),
        ];

        return DB::transaction(
            fn () => (new EcrituresTable)->pourUtilisateur($this->utilisateur)->absorber(Catalogue::POSTE_WEB, $piece),
        );
    }
}
