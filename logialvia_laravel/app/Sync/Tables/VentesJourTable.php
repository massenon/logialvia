<?php

namespace App\Sync\Tables;

use App\Models\FicheVentesJour;
use App\Models\User;
use App\Support\FilieresElevage;
use App\Support\UuidDeterministe;
use App\Sync\TableSync;
use Illuminate\Validation\Rule;

/**
 * Compteur de ventes du jour (`fiche_ventes_jour`) : UNE LIGNE PAR POSTE (`46a_`).
 *
 * Le compteur est cumulatif (la caisse l'incremente, une annulation le decremente). A
 * plusieurs postes, une ligne unique par (filiere, jour) se serait ecrasee d'un poste a
 * l'autre ou comptee deux fois. Chaque poste tient donc SON compteur, identifie par
 * (poste, filiere, jour) ; la lecture SOMME les lignes du jour. Un poste ne reecrit
 * jamais le compteur d'un autre : l'UUID est recalcule avec le `device_id` du jeton.
 *
 * La vente d'un autre poste n'incremente aucun compteur ici : le serveur n'a aucun
 * effet de bord, le compteur de chaque poste arrive par sa propre ligne.
 */
class VentesJourTable extends TableSync
{
    /** Qui lit le compteur : l'elevage (fiches) ou la vente (caisse). */
    public const DROITS_LECTURE = ['view-elevage', 'view-ventes'];

    /** Qui l'ecrit : la caisse l'alimente (caissier), l'elevage aussi (animalier, admin). */
    public const DROITS_ECRITURE = ['manage-ventes', 'manage-elevage'];

    public function nom(): string
    {
        return 'fiche_ventes_jour';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return FicheVentesJour::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function peutLire(User $utilisateur): bool
    {
        return $this->aUnDesDroits($utilisateur, self::DROITS_LECTURE);
    }

    public function peutEcrire(User $utilisateur): bool
    {
        return $this->aUnDesDroits($utilisateur, self::DROITS_ECRITURE);
    }

    public function colonnesEcrites(): array
    {
        return ['espece', 'date', 'qte'];
    }

    public function regles(): array
    {
        return [
            'espece' => ['required', Rule::in(FilieresElevage::identifiants())],
            'date' => ['required', 'date_format:Y-m-d'],
            'qte' => ['required', 'integer:strict', 'min:0'],
        ];
    }

    public function messages(): array
    {
        return [
            'id.uuid' => "L'identifiant du compteur doit être un UUID.",
            'espece.required' => 'La filière du compteur est obligatoire.',
            'espece.in' => 'La filière « :input » est inconnue.',
            'date.required' => 'La date du compteur est obligatoire.',
            'date.date_format' => 'La date du compteur est invalide.',
            'qte.required' => 'La quantité vendue est obligatoire.',
            'qte.integer' => 'La quantité vendue doit être un entier positif ou nul.',
            'qte.min' => 'La quantité vendue doit être un entier positif ou nul.',
        ];
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        // Le compteur d'un poste ne peut porter que l'identifiant calcule de
        // (filiere, jour, POSTE QUI ENVOIE) : sinon un poste pourrait ecrire celui d'un
        // autre, ou deux lignes d'un meme poste se sommeraient.
        if (is_string($ligne['id'] ?? null) && \Illuminate\Support\Str::isUuid($ligne['id']) && FilieresElevage::existe($ligne['espece'] ?? null)
            && $this->jourValide($ligne['date'] ?? null)
            && $ligne['id'] !== UuidDeterministe::ventesJour($ligne['espece'], $ligne['date'], $deviceId)) {
            return "L'identifiant du compteur ne correspond pas à sa filière, à sa date et à son poste.";
        }

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
