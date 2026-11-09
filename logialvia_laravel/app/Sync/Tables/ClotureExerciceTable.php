<?php

namespace App\Sync\Tables;

use App\Models\ClotureExercice;
use App\Models\ExerciceComptable;
use App\Models\User;
use App\Services\Comptabilite\Verrous;
use App\Support\Audit;
use App\Support\UuidDeterministe;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Validator;

/**
 * Cloture ANNUELLE d'un exercice : un fait LOURD (`46d_` §4).
 *
 * Le serveur ne la sert jamais (l'exercice cloture redescend par `exercice_comptable`) ;
 * il la REJOUE et decide :
 *  - **qui** : `close-fiscal-year` (l'administratrice seule, DV-15) ;
 *  - **quand** : sur une balance equilibree, toutes les pieces de l'exercice etant deja
 *    recues (le poste envoie ses pieces AVANT : ordre du moteur) ;
 *  - **effet** : l'exercice est clos (definitif : aucune declôture, BR-CPT-001), l'exercice
 *    suivant est ouvert, les ecritures sont verrouillees (derive de l'exercice) ;
 *  - **trace** : le fait est garde (qui, d'ou, quand) et un audit est ecrit.
 *
 * Une ecriture saisie hors ligne pour cet exercice et arrivant APRES la cloture est
 * refusee avec son motif (`EcrituresTable`) : le poste la garde, marquee, dans ses livres.
 * Rejoue, ou deja clos : accepte sans rien changer.
 */
class ClotureExerciceTable extends TableSync
{
    private ?User $utilisateur = null;

    public function nom(): string
    {
        return 'clotures_exercice';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return ClotureExercice::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    /** Jamais servie : l'exercice cloture redescend par `exercice_comptable`. */
    public function peutLire(User $utilisateur): bool
    {
        return false;
    }

    public function droitEcriture(): ?string
    {
        return 'close-fiscal-year';
    }

    public function peutEcrire(User $utilisateur): bool
    {
        $this->pourUtilisateur($utilisateur);

        return $utilisateur->can('close-fiscal-year');
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
            'date_cloture' => ['required', 'date'],
            'updated_at' => ['required', 'date'],
        ], [
            'id.required' => "L'identifiant de la clôture est obligatoire.",
            'id.uuid' => "L'identifiant de la clôture doit être un UUID.",
            'annee.required' => "L'exercice à clôturer est obligatoire.",
            'date_cloture.required' => 'La date de clôture est obligatoire.',
            'updated_at.required' => 'La date de saisie de la clôture est obligatoire.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if ($this->utilisateur === null || ! $this->utilisateur->can('close-fiscal-year')) {
            return 'Droit insuffisant pour clôturer un exercice (close-fiscal-year).';
        }

        $annee = (int) $ligne['annee'];
        if ($ligne['id'] !== UuidDeterministe::clotureExercice($annee)) {
            return "L'identifiant de la clôture ne désigne pas l'exercice $annee.";
        }

        $exercice = Verrous::exercice($annee);
        if ($exercice === null) {
            return "Exercice $annee hors des bornes acceptées.";
        }
        // Deja clos (rejeu, ou autre poste) : accepte sans rien changer.
        if ($exercice->is_cloture) {
            return null;
        }
        if (! Verrous::exerciceEquilibre($annee)) {
            $t = Verrous::totaux($annee);

            return sprintf(
                'Balance déséquilibrée de %s FCFA : une clôture annuelle est définitive, elle ne peut pas s\'exécuter sur une comptabilité déséquilibrée (BR-CPT-004).',
                number_format(abs($t['debit'] - $t['credit']), 0, ',', ' '),
            );
        }

        $date = CarbonImmutable::parse($ligne['date_cloture'])->utc();
        $exercice->forceFill([
            'is_cloture' => true,
            'date_cloture' => $date,
            'cloture_par' => $this->utilisateur->getKey(),
        ])->save();
        $exercice->touch();

        // L'exercice suivant est ouvert automatiquement (comme au poste).
        ExerciceComptable::query()->firstOrCreate(['annee' => $annee + 1], ['is_cloture' => false]);

        (new ClotureExercice)->forceFill([
            'id' => $ligne['id'],
            'annee' => $annee,
            'device_id' => $deviceId,
            'utilisateur_id' => $this->utilisateur->getKey(),
            'date_cloture' => $date,
            'updated_at' => CarbonImmutable::parse($ligne['updated_at'])->utc(),
            'serveur_modifie_le' => CarbonImmutable::now('UTC'),
        ])->save();

        Audit::enregistrer('comptabilite.cloture_exercice', $this->utilisateur, ['annee' => $annee, 'poste' => $deviceId]);

        return null;
    }
}
