<?php

namespace App\Sync\Tables;

use App\Models\Devis;
use App\Sync\TableSync;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;

/**
 * Devis de prestations : FAITS saisis au poste ou au web, dernier ecrivain gagne par UUID (`47a2_`).
 *
 *  - `reference` est le numero OFFICIEL : jamais renumerote ni modifie. Unique pour tous quand elle porte un
 *    code (`DV-P2-…`, `DV-WEB-…`), unique PAR POSTE sinon (`DV-2026-001`, poste jamais appaire) ;
 *  - un devis ACCEPTE est fige : son contenu ne change plus et il ne se supprime pas (seul son statut peut
 *    encore etre corrige) ;
 *  - supprimer = pierre tombale `supprime_le` (la ligne reste : le numero n'est jamais reutilise) ;
 *  - aucun effet de bord : ni vente, ni stock, ni ecriture comptable.
 */
class DevisTable extends TableSync
{
    public const STATUTS = ['emis', 'accepte', 'refuse'];

    public const MOTIF_REFERENCE = 'Cette référence est déjà utilisée par un autre devis.';

    public const MOTIF_FIGE = 'Un devis accepté ne se modifie plus et ne se supprime pas.';

    public function nom(): string
    {
        return 'devis';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return Devis::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-ventes';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-ventes';
    }

    /** Une reference a code (poste ou WEB) est globale ; sans code, elle est propre au poste. */
    public static function porteeReference(string $reference, string $deviceId): string
    {
        return preg_match('/^DV-(P\d+|WEB)-\d{4}-\d{3,}$/', $reference) === 1 ? '' : $deviceId;
    }

    public function colonnesEcrites(): array
    {
        return ['reference', 'portee_reference', 'client', 'objet', 'montant_estime', 'validite_jours', 'date_emission', 'statut', 'supprime_le'];
    }

    public function regles(): array
    {
        return [
            'reference' => ['required', 'string', 'regex:/^DV-((P\d+|WEB)-)?\d{4}-\d{3,}$/'],
            'client' => ['required', 'string', 'max:255'],
            'objet' => ['required', 'string', 'max:500'],
            'montant_estime' => ['required', 'numeric', 'gt:0'],
            'validite_jours' => ['required', 'integer', 'min:1', 'max:3650'],
            'date_emission' => ['required', 'date'],
            'statut' => ['required', 'string', 'in:'.implode(',', self::STATUTS)],
            'supprime_le' => ['nullable', 'date'],
        ];
    }

    public function messages(): array
    {
        return [
            'reference.required' => 'La référence du devis est obligatoire.',
            'reference.regex' => 'La référence du devis est invalide (attendu : DV-P2-2026-001).',
            'client.required' => 'Le client du devis est obligatoire.',
            'objet.required' => "L'objet du devis est obligatoire.",
            'montant_estime.required' => 'Le montant du devis est obligatoire.',
            'montant_estime.numeric' => 'Le montant du devis est invalide.',
            'montant_estime.gt' => 'Le montant du devis doit être supérieur à 0.',
            'validite_jours.required' => 'La validité du devis est obligatoire.',
            'validite_jours.integer' => 'La validité du devis est un nombre entier de jours.',
            'validite_jours.min' => 'La validité doit être d\'au moins 1 jour.',
            'validite_jours.max' => 'La validité d\'un devis ne dépasse pas 3650 jours.',
            'date_emission.required' => "La date d'émission du devis est obligatoire.",
            'date_emission.date' => "La date d'émission du devis est invalide.",
            'statut.in' => 'Le statut du devis est inconnu (emis, accepte ou refuse).',
        ];
    }

    public function exporter(Model $ligne): array
    {
        $donnees = parent::exporter($ligne);
        unset($donnees['portee_reference']); // detail d'implementation du serveur

        return $donnees;
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $validateur = Validator::make($ligne, array_merge([
            'id' => ['required', 'uuid'],
            'updated_at' => ['required', 'date'],
        ], $this->regles()), $this->messages());
        if ($validateur->fails()) {
            return $validateur->errors()->first();
        }

        $ligne['client'] = trim($ligne['client']);
        $ligne['objet'] = trim($ligne['objet']);
        $existant = Devis::query()->find($ligne['id']);

        if ($existant === null) {
            $portee = self::porteeReference($ligne['reference'], $deviceId);
            $doublon = Devis::query()
                ->where('portee_reference', $portee)
                ->where('reference', $ligne['reference'])
                ->exists();
            if ($doublon) {
                return self::MOTIF_REFERENCE;
            }
            $ligne['portee_reference'] = $portee;
        } else {
            if ($existant->reference !== $ligne['reference']) {
                return 'La référence d\'un devis ne change jamais.';
            }
            if ($existant->statut === 'accepte' && $this->touche($existant, $ligne)) {
                return self::MOTIF_FIGE;
            }
            $ligne['portee_reference'] = $existant->portee_reference;
        }

        return parent::absorber($deviceId, $ligne);
    }

    /** Le contenu change-t-il, ou le devis est-il supprime ? */
    private function touche(Devis $existant, array $ligne): bool
    {
        return $existant->client !== trim($ligne['client'])
            || $existant->objet !== trim($ligne['objet'])
            || abs($existant->montant_estime - (float) $ligne['montant_estime']) > 0.0001
            || $existant->validite_jours !== (int) $ligne['validite_jours']
            || ! empty($ligne['supprime_le']);
    }
}
