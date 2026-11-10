<?php

namespace App\Sync\Tables;

use App\Models\Bande;
use App\Support\FilieresElevage;
use App\Sync\TableSync;
use Illuminate\Validation\Rule;

/**
 * Bande d'elevage : fait saisi au poste, dernier ecrivain gagne par UUID (`46a_`).
 *
 * Voyage : la DECLARATION (filiere, code, mise en place, effectif mis en place — indicatif —,
 * cloture, observations). Ne voyage JAMAIS : un effectif « reel », qui n'existe pas comme
 * donnee stockee (il se recalcule des fiches journalieres) ; cette table n'a aucune colonne
 * pour le porter.
 *
 * Le code est UNIQUE par filiere : deux postes qui declarent chacun « B2 » hors ligne
 * creent deux bandes de UUID differents ; la seconde recue est REFUSEE avec son motif
 * (jamais fusionnee ni ecrasee : deux dates de mise en place ne se moyennent pas).
 */
class BandesTable extends TableSync
{
    public function nom(): string
    {
        return 'bandes';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return Bande::class;
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
        return ['espece', 'code', 'date_mise_en_bande', 'effectif_initial', 'date_cloture', 'observations'];
    }

    public function regles(): array
    {
        return [
            'espece' => ['required', Rule::in(FilieresElevage::identifiants())],
            'code' => ['required', 'string', 'max:60'],
            'date_mise_en_bande' => ['required', 'date_format:Y-m-d'],
            'effectif_initial' => ['nullable', 'integer:strict', 'min:0'],
            'date_cloture' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:date_mise_en_bande'],
            'observations' => ['nullable', 'string', 'max:1000'],
        ];
    }

    public function messages(): array
    {
        return [
            'id.uuid' => "L'identifiant de la bande doit être un UUID.",
            'espece.required' => 'La filière de la bande est obligatoire.',
            'espece.in' => 'La filière « :input » est inconnue.',
            'code.required' => 'Le code de la bande est obligatoire.',
            'code.max' => 'Le code de la bande est trop long.',
            'date_mise_en_bande.required' => 'La date de mise en place de la bande est obligatoire.',
            'date_mise_en_bande.date_format' => 'La date de mise en place de la bande est invalide.',
            'effectif_initial.integer' => "L'effectif mis en place doit être un entier positif ou nul.",
            'effectif_initial.min' => "L'effectif mis en place ne peut pas être négatif.",
            'date_cloture.date_format' => 'La date de clôture de la bande est invalide.',
            'date_cloture.after_or_equal' => 'La clôture ne peut pas précéder la mise en place de la bande.',
            'observations.max' => 'Les observations de la bande sont trop longues.',
        ];
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        // LIGNE ENTIERE : une colonne facultative absente est ecrite a `null`.
        foreach (['effectif_initial', 'date_cloture', 'observations'] as $champ) {
            $ligne[$champ] = $ligne[$champ] ?? null;
        }
        if (is_string($ligne['code'] ?? null)) {
            $ligne['code'] = trim($ligne['code']);
        }

        // Le code est l'identite metier d'une bande dans une filiere : le meme code sous
        // un autre UUID est refuse. Controle apres la validation : il ne s'applique qu'a
        // une ligne par ailleurs valide.
        $motif = $this->validerSeule($ligne);
        if ($motif !== null) {
            return $motif;
        }
        $homonyme = Bande::query()
            ->where('espece', $ligne['espece'])
            ->where('code', $ligne['code'])
            ->where('id', '!=', $ligne['id'])
            ->exists();
        if ($homonyme) {
            return 'Ce code de bande est déjà utilisé pour cette filière.';
        }

        return parent::absorber($deviceId, $ligne);
    }

    /** Motif de la premiere regle violee, ou `null`. */
    private function validerSeule(array $ligne): ?string
    {
        $validateur = \Illuminate\Support\Facades\Validator::make($ligne, array_merge([
            'id' => ['required', 'uuid'],
            'updated_at' => ['required', 'date'],
        ], $this->regles()), array_merge([
            'id.required' => "L'identifiant de la ligne est obligatoire.",
            'updated_at.required' => 'La date de saisie de la ligne est obligatoire.',
            'updated_at.date' => 'La date de saisie de la ligne est invalide.',
        ], $this->messages()));

        return $validateur->fails() ? $validateur->errors()->first() : null;
    }
}
