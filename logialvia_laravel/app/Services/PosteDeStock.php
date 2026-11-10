<?php

namespace App\Services;

use App\Models\Poste;
use App\Models\User;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Le POSTE DE STOCK que désigne une opération web qui a un effet de stock (`47s_`).
 *
 * Décision du client (conservée) : le stock et le PMP sont PROPRES À CHAQUE POSTE. Le web n'en a
 * pas ; il désigne donc le poste dont le stock subira l'opération. Le fait porte `poste_cible` ;
 * seul ce poste, en l'absorbant, applique l'effet (une fois). Cette classe dit QUI peut être
 * désigné, pour quelle opération, et retient le défaut de chaque compte.
 *
 * Un poste est désignable si, et seulement si :
 *  - il est appairé et non révoqué (sinon l'effet ne s'appliquerait jamais) ;
 *  - il a déjà fini au moins un tirage (`curseur_tirage` : un poste jamais synchronisé n'a pas
 *    encore reçu les référentiels, ni de stock « à lui ») ;
 *  - son compte connu a le droit de LIRE les faits de l'opération (sinon le fait ne lui serait
 *    jamais servi : l'effet attendrait pour toujours).
 */
final class PosteDeStock
{
    public const RECEPTION = 'reception_achat';

    public const VENTE = 'vente_web';

    public const CORRECTION = 'correction_stock';

    /** @var array<string, string> opération => libellé */
    public const OPERATIONS = [
        self::RECEPTION => "Réception d'achat",
        self::VENTE => 'Vente / caisse web',
        self::CORRECTION => 'Correction de stock',
    ];

    /** Droits de lecture dont l'un suffit pour que le poste reçoive les faits de l'opération. */
    private const DROITS_LECTURE = [
        self::RECEPTION => ['view-achats'],
        self::VENTE => ['view-ventes'],
        self::CORRECTION => ['view-ventes', 'view-stocks'],
    ];

    public const MOTIF_INCONNU = 'Poste de stock inconnu ou révoqué : choisissez un poste appairé et actif.';

    public const MOTIF_JAMAIS_SYNCHRONISE = "Ce poste ne s'est encore jamais synchronisé : il ne pourrait pas recevoir l'opération. Synchronisez-le d'abord.";

    /**
     * Motif du refus si ce poste ne peut pas être désigné pour cette opération, `null` sinon.
     * Message clair, en français : il s'affiche tel quel à la saisie.
     */
    public static function verifier(?string $deviceId, string $operation): ?string
    {
        if ($deviceId === null || $deviceId === '') {
            return self::MOTIF_INCONNU;
        }
        $poste = Poste::query()->where('device_id', $deviceId)->first();
        if ($poste === null || $poste->revoque_le !== null || $poste->etat() !== 'appaire') {
            return self::MOTIF_INCONNU;
        }
        if ($poste->curseur_tirage === null) {
            return self::MOTIF_JAMAIS_SYNCHRONISE;
        }
        if (! self::compteALeDroit($poste, $operation)) {
            return "Le compte connecté au poste {$poste->code} n'a pas le droit de lire ces opérations : "
                .'elles ne lui parviendraient jamais.';
        }

        return null;
    }

    public const MOTIF_SEUL_LE_WEB = 'Seul le web peut désigner un poste de stock.';

    public const MOTIF_LIEN = 'Le poste de stock de ce fait ne peut plus être changé : le fait lui est lié.';

    /**
     * Contrôle de la désignation d'un poste dans un fait REÇU : seul le web désigne (un poste ne
     * délègue pas son stock à un autre), et le poste désigné doit l'être pour cette opération.
     * `null` : pas de désignation, ou désignation valide.
     */
    public static function controlerDesignation(string $deviceId, ?string $cible, string $operation): ?string
    {
        if ($cible === null || $cible === '') {
            return null;
        }
        if ($deviceId !== \App\Livewire\Catalogue::POSTE_WEB) {
            return self::MOTIF_SEUL_LE_WEB;
        }

        return self::verifier($cible, $operation);
    }

    /** @return Collection<int, Poste> Les postes désignables pour cette opération, par code. */
    public static function proposables(string $operation): Collection
    {
        return Poste::query()->whereNull('revoque_le')->orderBy('code')->get()
            ->filter(fn (Poste $p) => self::verifier($p->device_id, $operation) === null)
            ->values();
    }

    /** Code court (`P2`) d'un poste, `null` si inconnu. */
    public static function code(?string $deviceId): ?string
    {
        if ($deviceId === null) {
            return null;
        }

        return Poste::query()->where('device_id', $deviceId)->value('code');
    }

    /**
     * Défaut de ce compte pour cette opération : le poste mémorisé s'il est encore désignable ;
     * sinon, s'il n'y a qu'UN poste désignable, celui-là ; sinon `null` (le compte choisit).
     */
    public static function defaut(User $utilisateur, string $operation): ?string
    {
        $memorise = DB::table('postes_stock_defauts')
            ->where('user_id', $utilisateur->getKey())->where('operation', $operation)
            ->value('poste_device_id');
        if ($memorise !== null && self::verifier($memorise, $operation) === null) {
            return $memorise;
        }
        $proposables = self::proposables($operation);

        return $proposables->count() === 1 ? $proposables->first()->device_id : null;
    }

    /** Retient le choix du compte comme défaut (jamais un poste non désignable). */
    public static function memoriser(User $utilisateur, string $operation, ?string $deviceId): void
    {
        if ($deviceId === null || self::verifier($deviceId, $operation) !== null) {
            return;
        }
        DB::table('postes_stock_defauts')->updateOrInsert(
            ['user_id' => $utilisateur->getKey(), 'operation' => $operation],
            ['poste_device_id' => $deviceId, 'updated_at' => now(), 'created_at' => now()],
        );
    }

    /** Le client peut exiger un poste de stock pour toute opération qui en a un effet (`STOCK_CIBLE_OBLIGATOIRE`). */
    public static function obligatoire(): bool
    {
        return (bool) config('logialvia.stock_cible.obligatoire');
    }

    public const MOTIF_OBLIGATOIRE = 'Désignez le « poste de stock » qui applique cette opération à son stock.';

    /**
     * Où en est l'effet de stock de ces faits ? Une entrée par fait :
     * `poste` (code `P2`, ou `null`), `etat`, `libelle` (badge), `avertissement`.
     *
     * États : `aucun` (aucun poste désigné : journal seul) · `a_la_reception` (commande pas encore
     * livrée) · `attente` (le poste désigné n'a pas encore tout appliqué : hors ligne, ou pas encore
     * synchronisé) · `applique` · `avertissement` (appliqué, stock ramené à 0) · `ignore` (le poste
     * a refusé d'appliquer, et dit pourquoi) · `sans_effet` (annulé avant d'avoir touché un stock) ·
     * `revoque` (poste révoqué : l'effet n'aura jamais lieu).
     *
     * @param  Collection<int, \Illuminate\Database\Eloquent\Model>  $faits  portent `id` et `poste_cible`
     * @param  callable(\Illuminate\Database\Eloquent\Model, Collection): (array<int, string>|null)  $attendus
     *         natures d'effet que le fait doit avoir produites, d'après son statut et les effets déjà reçus ;
     *         `null` : rien n'est encore attendu (commande pas encore livrée)
     * @return array<string, array{poste: ?string, etat: string, libelle: string, avertissement: ?string}>
     */
    public static function suivi(Collection $faits, callable $attendus): array
    {
        $effets = \App\Models\EffetStock::query()->whereIn('fait_id', $faits->pluck('id')->all())->get()->groupBy('fait_id');
        $postes = Poste::query()->get()->keyBy('device_id');
        $suivi = [];

        foreach ($faits as $fait) {
            if ($fait->poste_cible === null) {
                $suivi[$fait->id] = ['poste' => null, 'etat' => 'aucun', 'libelle' => 'Aucun (journal seul)', 'avertissement' => null];

                continue;
            }
            $poste = $postes->get($fait->poste_cible);
            $code = $poste?->code ?? '?';
            $recus = $effets->get($fait->id, collect());
            $attendus_ = $attendus($fait, $recus); // null : rien n'est encore attendu (commande pas livrée)
            $manquants = array_diff($attendus_ ?? [], $recus->pluck('nature')->all());
            $probleme = $recus->first(fn ($e) => $e->etat !== 'applique');

            [$etat, $libelle, $avert] = match (true) {
                $manquants !== [] && ($poste === null || $poste->revoque_le !== null)
                    => ['revoque', "Poste $code révoqué : jamais appliqué", null],
                $manquants !== [] => ['attente', "En attente du poste $code", null],
                $probleme !== null && $probleme->etat === 'ignore' => ['ignore', "Non appliqué par le poste $code", $probleme->avertissement],
                $probleme !== null => ['avertissement', "Appliqué au poste $code avec avertissement", $probleme->avertissement],
                $attendus_ === null => ['a_la_reception', "Poste $code (appliqué à la réception)", null],
                $attendus_ === [] => ['sans_effet', "Poste $code : aucun effet", null],
                default => ['applique', "Appliqué au poste $code", null],
            };
            $suivi[$fait->id] = ['poste' => $code, 'etat' => $etat, 'libelle' => $libelle, 'avertissement' => $avert];
        }

        return $suivi;
    }

    /** @param Collection<int, \App\Models\Achat> $achats */
    public static function suiviAchats(Collection $achats): array
    {
        return self::suivi($achats, function ($achat, Collection $recus): ?array {
            return match ($achat->statut) {
                'Livré' => ['reception'],
                // Annulé : une sortie n'est attendue que si la réception avait touché le stock.
                'Annulé' => $recus->contains(fn ($e) => $e->nature === 'reception' && $e->etat !== 'ignore')
                    ? ['reception', 'annulation_reception'] : [],
                default => null,
            };
        });
    }

    /** @param Collection<int, \App\Models\MouvementProduit> $corrections */
    public static function suiviCorrections(Collection $corrections): array
    {
        return self::suivi($corrections, fn () => ['correction']);
    }

    /** @param Collection<int, \App\Models\Vente> $ventes */
    public static function suiviVentes(Collection $ventes): array
    {
        return self::suivi($ventes, function ($vente, Collection $recus): array {
            if ($vente->status !== 'Annulée') {
                return ['vente'];
            }

            return $recus->contains(fn ($e) => $e->nature === 'vente' && $e->etat !== 'ignore')
                ? ['vente', 'annulation_vente'] : [];
        });
    }

    private static function compteALeDroit(Poste $poste, string $operation): bool
    {
        $compte = $poste->dernierUtilisateur;
        if ($compte === null) {
            return false;
        }
        foreach (self::DROITS_LECTURE[$operation] ?? [] as $droit) {
            if ($compte->can($droit)) {
                return true;
            }
        }

        return false;
    }
}
