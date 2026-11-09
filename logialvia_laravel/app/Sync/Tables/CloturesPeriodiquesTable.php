<?php

namespace App\Sync\Tables;

use App\Models\CloturePeriodique;
use App\Models\ExerciceComptable;
use App\Models\User;
use App\Services\Comptabilite\Verrous;
use App\Support\UuidDeterministe;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Validator;

/**
 * Cloture (et decloture) d'un MOIS (BR-CPT-006).
 *
 * Cle naturelle (annee, mois), identifiant derive : « dernier ecrivain gagne », strictement,
 * a l'instant de saisie. Clore un mois ne supprime rien : il refuse les NOUVELLES ecritures
 * datees de ce mois, pour tous les postes.
 *
 * ## Qui peut
 *  - CLORE : `manage-comptabilite`, sur une balance equilibree (BR-CPT-004) ;
 *  - DECLORE (reouvrir pour correction) : `close-fiscal-year`, l'administratrice seule,
 *    comme au poste (BR-CPT-006) ;
 *  - jamais sur un exercice deja cloture (BR-CPT-001).
 */
class CloturesPeriodiquesTable extends TableSync
{
    private ?User $utilisateur = null;

    public function nom(): string
    {
        return 'clotures_periodiques';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return CloturePeriodique::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-comptabilite';
    }

    public function peutEcrire(User $utilisateur): bool
    {
        $this->pourUtilisateur($utilisateur);

        return $this->aUnDesDroits($utilisateur, ['manage-comptabilite', 'close-fiscal-year']);
    }

    public function pourUtilisateur(User $utilisateur): static
    {
        $this->utilisateur = $utilisateur;

        return $this;
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $v = Validator::make($ligne, [
            'id' => ['required', 'uuid'],
            'annee' => ['required', 'integer'],
            'mois' => ['required', 'integer', 'between:1,12'],
            'is_cloture' => ['required', 'boolean'],
            'date_cloture' => ['nullable', 'date'],
            'decloture_par' => ['nullable', 'string', 'max:255'],
            'updated_at' => ['required', 'date'],
        ], [
            'id.required' => "L'identifiant de la clôture est obligatoire.",
            'id.uuid' => "L'identifiant de la clôture doit être un UUID.",
            'annee.required' => "L'exercice est obligatoire.",
            'mois.between' => 'Le mois va de 1 à 12.',
            'is_cloture.required' => "L'état du mois (clos ou ouvert) est obligatoire.",
            'is_cloture.boolean' => "L'état du mois doit être clos ou ouvert.",
            'date_cloture.date' => 'La date de clôture est invalide.',
            'updated_at.required' => 'La date de saisie de la clôture est obligatoire.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if ($this->utilisateur === null) {
            return 'Utilisateur inconnu : la clôture ne peut pas être rattachée à un droit.';
        }

        $annee = (int) $ligne['annee'];
        $mois = (int) $ligne['mois'];
        $cloture = filter_var($ligne['is_cloture'], FILTER_VALIDATE_BOOLEAN);

        if ($ligne['id'] !== UuidDeterministe::cloturePeriodique($annee, $mois)) {
            return "L'identifiant de la clôture ne désigne pas le mois $mois/$annee.";
        }
        if ($cloture && empty($ligne['date_cloture'])) {
            return 'La date de clôture est obligatoire.';
        }

        // Le droit dépend du geste : clore ou rouvrir.
        $droit = $cloture ? 'manage-comptabilite' : 'close-fiscal-year';
        if (! $this->utilisateur->can($droit)) {
            return $cloture
                ? 'Droit insuffisant pour clôturer un mois.'
                : 'Seule une administratrice peut déclôturer un mois (BR-CPT-006).';
        }

        $saisie = CarbonImmutable::parse($ligne['updated_at'])->utc();
        $existante = CloturePeriodique::query()->find($ligne['id']);

        // Un rejeu ou une saisie plus ancienne est acceptee sans rien changer.
        if ($existante !== null && ! $saisie->greaterThan($existante->updated_at)) {
            return null;
        }

        if (Verrous::exercice($annee) === null) {
            return "Exercice $annee hors des bornes acceptées.";
        }
        if (ExerciceComptable::query()->find($annee)?->is_cloture) {
            return "L'exercice $annee est clôturé : ses mois ne bougent plus (BR-CPT-001).";
        }
        if ($cloture && ! Verrous::exerciceEquilibre($annee)) {
            return 'Balance déséquilibrée : une clôture ne peut pas s\'exécuter sur une comptabilité déséquilibrée (BR-CPT-004).';
        }

        $champs = [
            'is_cloture' => $cloture,
            'date_cloture' => $cloture ? CarbonImmutable::parse($ligne['date_cloture'])->utc() : null,
            'decloture_par' => $cloture ? null : ($ligne['decloture_par'] ?? null),
            'device_id' => $deviceId,
            'updated_at' => $saisie,
            'serveur_modifie_le' => CarbonImmutable::now('UTC'),
        ];

        if ($existante === null) {
            (new CloturePeriodique)->forceFill($champs + [
                'id' => $ligne['id'],
                'annee' => $annee,
                'mois' => $mois,
            ])->save();
        } else {
            $existante->forceFill($champs)->save();
        }

        return null;
    }
}
