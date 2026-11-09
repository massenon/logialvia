<?php

namespace App\Sync\Tables;

use App\Models\FicheJournee;
use App\Support\FilieresElevage;
use App\Support\UuidDeterministe;
use App\Sync\TableSync;
use Illuminate\Validation\Rule;

/**
 * Fiche journaliere d'elevage : fait saisi au poste, DERNIER ECRIVAIN GAGNE, LIGNE ENTIERE
 * (`46a_`).
 *
 * Identite : (filiere, jour). L'UUID est DETERMINISTE de cette cle et le serveur le
 * recalcule : deux postes qui saisissent le meme jour ecrivent la meme ligne ; la plus
 * recente (instant de SAISIE, strictement) l'emporte en bloc. Jamais de melange champ par
 * champ : les effectifs sont calcules a partir de la veille, melanger deux saisies
 * produirait un effectif qu'aucun poste n'a calcule.
 *
 * Le serveur n'applique aucune cascade : la ligne arrive avec ses valeurs calculees par le
 * poste qui l'a saisie, les jours suivants arrivent par leurs propres lignes.
 */
class FichesJourneeTable extends TableSync
{
    /** Entiers obligatoires (>= 0). */
    public const ENTIERS = [
        'achat', 'ne', 'vente',
        'mort_cat1', 'mort_cat2', 'mort_cat3',
        'don_cat1', 'don_cat2', 'don_cat3',
        'effectif', 'eff_cat1_day', 'eff_cat2_day', 'eff_cat3_day',
    ];

    /** Entiers facultatifs (`null` ou >= 0). */
    public const ENTIERS_FACULTATIFS = [
        'mort_cat4', 'don_cat4', 'eff_cat4_day',
        'srh', 'ts', 'stock_final_oeufs',
        'oeufs_pondus', 'oeufs_casses', 'sorties_plateaux',
        'poids_general_g',
    ];

    public function nom(): string
    {
        return 'fiche_journee';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return FicheJournee::class;
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
        return [
            'espece', 'date', ...self::ENTIERS, ...self::ENTIERS_FACULTATIFS,
            'traitement_obs', 'traitement_valide', 'is_recorded',
        ];
    }

    public function regles(): array
    {
        $regles = [
            'espece' => ['required', Rule::in(FilieresElevage::identifiants())],
            'date' => ['required', 'date_format:Y-m-d'],
        ];
        foreach (self::ENTIERS as $champ) {
            $regles[$champ] = ['required', 'integer:strict', 'min:0'];
        }
        foreach (self::ENTIERS_FACULTATIFS as $champ) {
            $regles[$champ] = ['nullable', 'integer:strict', 'min:0'];
        }
        $regles['traitement_obs'] = ['nullable', 'string', 'max:2000'];
        $regles['traitement_valide'] = ['required', 'boolean:strict'];
        $regles['is_recorded'] = ['required', 'boolean:strict'];

        return $regles;
    }

    public function messages(): array
    {
        $messages = [
            'id.uuid' => "L'identifiant de la fiche doit être un UUID.",
            'espece.required' => 'La filière de la fiche est obligatoire.',
            'espece.in' => 'La filière « :input » est inconnue.',
            'date.required' => 'La date de la fiche est obligatoire.',
            'date.date_format' => 'La date de la fiche est invalide.',
            'traitement_obs.max' => "L'observation de traitement est trop longue.",
            'traitement_valide.required' => "L'indicateur « traitement_valide » est obligatoire.",
            'traitement_valide.boolean' => "L'indicateur « traitement_valide » doit être vrai ou faux.",
            'is_recorded.required' => "L'indicateur « is_recorded » est obligatoire.",
            'is_recorded.boolean' => "L'indicateur « is_recorded » doit être vrai ou faux.",
        ];
        foreach ([...self::ENTIERS, ...self::ENTIERS_FACULTATIFS] as $champ) {
            $messages["$champ.required"] = "La valeur de « $champ » est obligatoire.";
            $messages["$champ.integer"] = "La valeur de « $champ » doit être un entier positif ou nul.";
            $messages["$champ.min"] = "La valeur de « $champ » doit être un entier positif ou nul.";
        }

        return $messages;
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        // L'identite d'une fiche est sa cle (filiere, jour) : un UUID qui n'en est pas le
        // calcul romprait la convergence entre postes. Controle fait seulement quand la
        // cle est lisible ; sinon la validation de la classe mere dit le vrai motif.
        if (is_string($ligne['id'] ?? null) && \Illuminate\Support\Str::isUuid($ligne['id']) && FilieresElevage::existe($ligne['espece'] ?? null)
            && $this->jourValide($ligne['date'] ?? null)
            && $ligne['id'] !== UuidDeterministe::ficheJournee($ligne['espece'], $ligne['date'])) {
            return "L'identifiant de la fiche ne correspond pas à sa filière et à sa date.";
        }

        // LIGNE ENTIERE : une colonne facultative absente est ecrite a `null`, jamais
        // laissee a sa valeur precedente (sinon deux saisies se melangeraient).
        foreach (self::ENTIERS_FACULTATIFS as $champ) {
            $ligne[$champ] = $ligne[$champ] ?? null;
        }
        $ligne['traitement_obs'] = $ligne['traitement_obs'] ?? null;

        return parent::absorber($deviceId, $ligne);
    }

    private function jourValide(mixed $jour): bool
    {
        if (! is_string($jour)) {
            return false;
        }
        $analyse = \DateTime::createFromFormat('!Y-m-d', $jour);

        return $analyse !== false && $analyse->format('Y-m-d') === $jour;
    }
}
