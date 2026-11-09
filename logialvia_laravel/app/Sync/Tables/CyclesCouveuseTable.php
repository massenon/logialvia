<?php

namespace App\Sync\Tables;

use App\Models\CycleCouveuse;
use App\Models\MachineIncubateur;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Closure;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;

/**
 * Lots d'incubation et leurs mirages : FAIT saisi au poste, dernier ecrivain gagne par UUID
 * (`46_` §2.3, `46b_`).
 *
 * Les mirages ne sont pas une table : deux colonnes du lot (`oeufs_blancs_j7`,
 * `oeufs_gates_j14`), saisies dans le temps ; `null` = « pas encore mire » (jamais confondu
 * avec zero œuf clair). Une saisie de mirage est une MODIFICATION du lot.
 *
 *  - Valeurs permises (espece, statut) et compteurs coherents : un mirage ne retire pas plus
 *    d'œufs qu'il n'y en a ; eclos + perdus ne depassent pas les œufs retenus (memes regles
 *    que l'ecran du poste).
 *  - Incubateur connu du serveur, sinon refus (le lot arrive APRES son incubateur).
 *  - `lot_parent_id` n'est PAS verifie : le lot d'origine peut arriver apres son remplacant
 *    (ordre libre des lignes d'une page).
 *  - Code du lot (`code_incubation`) : numero officiel, jamais modifie ; unique pour tous
 *    avec un code de poste (`C-P2-2026-001`), unique PAR POSTE sans code (`C-2026-001`) ;
 *    les lots supprimes ne retiennent pas leur code.
 *  - Suppression : pierre tombale `supprime_le` (le serveur n'efface jamais), redistribuee ;
 *    une saisie plus recente (lot restaure) la leve.
 *  - Aucun effet de bord : ni naissances dans les fiches d'elevage, ni stock, ni ecriture.
 */
class CyclesCouveuseTable extends TableSync
{
    public const ESPECES = ['goliath', 'pintade'];

    public const STATUTS = ['En Incubation', 'Éclosion Effectuée', 'Remplacé'];

    public const MOTIF_CODE = 'Ce code est déjà utilisé par un autre lot.';

    public const MOTIF_MACHINE = 'Incubateur inconnu du serveur.';

    public function nom(): string
    {
        return 'cycle_couveuse';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return CycleCouveuse::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-elevage';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-elevage';
    }

    /** Un code a poste (`C-P2-2026-001`) est unique pour tous ; sans poste, par poste. */
    public static function porteeCode(string $code, string $deviceId): string
    {
        return preg_match('/^C-P\d+-\d{4}-\d{3,}$/', $code) === 1 ? '' : $deviceId;
    }

    public function exporter(Model $ligne): array
    {
        $donnees = parent::exporter($ligne);
        unset($donnees['portee_code']);

        return $donnees;
    }

    public function colonnesEcrites(): array
    {
        return [
            'espece', 'date_incubation', 'oeufs_couves', 'poussins_nes', 'oeufs_perdus', 'statut',
            'machine_id', 'oeufs_blancs_j7', 'oeufs_gates_j14', 'lot_parent_id', 'supprime_le',
        ];
    }

    /** Entier strict, `null` toléré si [$nullable]. */
    private static function entier(int $minimum, string $motif): Closure
    {
        return function (string $attribut, mixed $valeur, Closure $echec) use ($minimum, $motif) {
            if (! is_int($valeur) || $valeur < $minimum) {
                $echec($motif);
            }
        };
    }

    public function regles(): array
    {
        $negatif = 'Les quantités ne peuvent être négatives.';

        return [
            'code_incubation' => ['required', 'string', 'max:40'],
            'espece' => ['required', 'in:'.implode(',', self::ESPECES)],
            'date_incubation' => ['required', 'date_format:Y-m-d'],
            'oeufs_couves' => ['required', self::entier(1, "Le nombre d'œufs chargés est obligatoire.")],
            'poussins_nes' => ['nullable', self::entier(0, $negatif)],
            'oeufs_perdus' => ['nullable', self::entier(0, $negatif)],
            'statut' => ['required', 'in:'.implode(',', self::STATUTS)],
            'machine_id' => ['nullable', 'uuid'],
            'oeufs_blancs_j7' => ['nullable', self::entier(0, $negatif)],
            'oeufs_gates_j14' => ['nullable', self::entier(0, $negatif)],
            'lot_parent_id' => ['nullable', 'uuid'],
            'supprime_le' => ['nullable', 'date'],
        ];
    }

    public function messages(): array
    {
        return [
            'code_incubation.required' => 'Le code du lot est obligatoire.',
            'code_incubation.max' => 'Le code du lot est trop long.',
            'espece.required' => "L'espèce du lot est obligatoire.",
            'espece.in' => "L'espèce du lot est inconnue.",
            'date_incubation.required' => 'La date de chargement est obligatoire.',
            'date_incubation.date_format' => 'La date de chargement est invalide.',
            'oeufs_couves.required' => "Le nombre d'œufs chargés est obligatoire.",
            'statut.required' => 'Le statut du lot est obligatoire.',
            'statut.in' => 'Le statut du lot est inconnu.',
            'machine_id.uuid' => "L'identifiant de l'incubateur est invalide.",
            'lot_parent_id.uuid' => "L'identifiant du lot d'origine est invalide.",
            'supprime_le.date' => 'La date de suppression est invalide.',
        ];
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $validateur = Validator::make($ligne, array_merge([
            'id' => ['required', 'uuid'],
            'updated_at' => ['required', 'date'],
        ], $this->regles()), array_merge([
            'id.required' => "L'identifiant de la ligne est obligatoire.",
            'id.uuid' => "L'identifiant de la ligne doit être un UUID.",
            'updated_at.required' => 'La date de saisie de la ligne est obligatoire.',
            'updated_at.date' => 'La date de saisie de la ligne est invalide.',
        ], $this->messages()));

        if ($validateur->fails()) {
            return $validateur->errors()->first();
        }

        $motif = $this->controleCroise($deviceId, $ligne);
        if ($motif !== null) {
            return $motif;
        }

        $saisie = CarbonImmutable::parse($ligne['updated_at'])->utc();
        $donnees = array_intersect_key($ligne, array_flip($this->colonnesEcrites()));
        $code = trim($ligne['code_incubation']);
        $existant = CycleCouveuse::query()->find($ligne['id']);

        if ($existant === null) {
            (new CycleCouveuse)->forceFill($donnees + [
                'id' => $ligne['id'],
                'device_id' => $deviceId,
                'code_incubation' => $code,
                'portee_code' => self::porteeCode($code, $deviceId),
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ])->save();

            return null;
        }

        // Dernier ecrivain gagne, strictement ; un rejeu est accepte sans rien changer.
        if ($saisie->greaterThan($existant->updated_at)) {
            $existant->forceFill($donnees + [
                'device_id' => $deviceId,
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ])->save();
        }

        return null;
    }

    /** Regles qui croisent plusieurs colonnes ou plusieurs lignes. */
    private function controleCroise(string $deviceId, array $ligne): ?string
    {
        $charges = $ligne['oeufs_couves'];
        $blancs = $ligne['oeufs_blancs_j7'] ?? null;
        $gates = $ligne['oeufs_gates_j14'] ?? null;
        $eclos = $ligne['poussins_nes'] ?? null;
        $perdus = $ligne['oeufs_perdus'] ?? null;
        $retenus = $charges - ($blancs ?? 0) - ($gates ?? 0);

        if ($retenus < 0) {
            return "Les mirages retirent plus d'œufs que le lot n'en contient.";
        }
        if ($eclos !== null && $eclos + ($perdus ?? 0) > $retenus) {
            return "Poussins éclos + œufs perdus dépasse les œufs encore en incubation après les mirages.";
        }
        if (($ligne['lot_parent_id'] ?? null) === $ligne['id']) {
            return 'Un lot ne peut pas se remplacer lui-même.';
        }

        $code = trim($ligne['code_incubation']);
        $existant = CycleCouveuse::query()->find($ligne['id']);

        // Le code est le numero officiel du lot : il ne change jamais.
        if ($existant !== null && $existant->code_incubation !== $code) {
            return 'Le code d\'un lot ne change jamais.';
        }

        // Une pierre tombale ne demande ni incubateur connu ni code libre : le lot n'existe plus.
        if (($ligne['supprime_le'] ?? null) !== null) {
            return null;
        }

        if (($ligne['machine_id'] ?? null) !== null
            && ! MachineIncubateur::query()->whereKey($ligne['machine_id'])->exists()) {
            return self::MOTIF_MACHINE;
        }

        $portee = $existant?->portee_code ?? self::porteeCode($code, $deviceId);
        $doublon = CycleCouveuse::query()
            ->where('id', '!=', $ligne['id'])
            ->where('code_incubation', $code)
            ->where('portee_code', $portee)
            ->whereNull('supprime_le')
            ->exists();

        return $doublon ? self::MOTIF_CODE : null;
    }
}
