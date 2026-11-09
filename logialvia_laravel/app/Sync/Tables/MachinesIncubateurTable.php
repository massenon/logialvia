<?php

namespace App\Sync\Tables;

use App\Models\MachineIncubateur;
use App\Sync\TableSync;
use Closure;
use Illuminate\Support\Facades\Validator;

/**
 * Incubateurs du couvoir : FAIT saisi au poste, dernier ecrivain gagne par UUID (`46b_`).
 *
 * Le contrat (`46_` §2.2) les rangeait parmi les referentiels « le serveur gagne » ; on les
 * traite en faits (decision a valider) : seul le poste sait en declarer, et le serveur n'a
 * aucune regle propre a leur appliquer. Le CODE est l'identite metier : le poste derive l'UUID
 * du code (deux postes qui declarent « INC-01 » designent le meme incubateur), et le serveur
 * refuse, sans jamais fusionner, un AUTRE UUID qui porterait le meme code.
 *
 * Aucun effet de bord : ni lot, ni stock, ni ecriture.
 */
class MachinesIncubateurTable extends TableSync
{
    public const MOTIF_CODE = 'Un incubateur porte déjà le code %s.';

    public function nom(): string
    {
        return 'machines_incubateur';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return MachineIncubateur::class;
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

    public function colonnesEcrites(): array
    {
        return ['code', 'libelle', 'capacite_oeufs', 'active'];
    }

    /** Entier strict (un texte « 500 » ou un decimal est refuse, comme au poste). */
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
        return [
            'code' => ['required', 'string', 'max:40'],
            'libelle' => ['required', 'string', 'max:255'],
            'capacite_oeufs' => ['nullable', self::entier(1, 'La capacité doit être supérieure à 0.')],
            'active' => ['required', function (string $attribut, mixed $valeur, Closure $echec) {
                if (! is_bool($valeur)) {
                    $echec("L'état de l'incubateur est invalide.");
                }
            }],
        ];
    }

    public function messages(): array
    {
        return [
            'code.required' => "Le code de l'incubateur est obligatoire.",
            'code.max' => "Le code de l'incubateur est trop long.",
            'libelle.required' => "Le libellé de l'incubateur est obligatoire.",
            'libelle.max' => "Le libellé de l'incubateur est trop long.",
            'active.required' => "L'état de l'incubateur est invalide.",
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

        // Un AUTRE incubateur porte deja ce code : jamais fusionne en silence (casse ignoree).
        $code = trim($ligne['code']);
        $homonyme = MachineIncubateur::query()
            ->where('id', '!=', $ligne['id'])
            ->whereRaw('lower(code) = ?', [mb_strtolower($code)])
            ->exists();

        if ($homonyme) {
            return sprintf(self::MOTIF_CODE, $code);
        }

        $ligne['code'] = $code;
        $ligne['libelle'] = trim($ligne['libelle']);

        return parent::absorber($deviceId, $ligne);
    }
}
