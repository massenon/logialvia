<?php

namespace App\Sync\Tables;

use App\Models\EcheanceProphylaxie;
use App\Models\SoinCalendrier;
use App\Sync\TableSync;
use Illuminate\Validation\Rule;

/**
 * Soins du calendrier : FAIT saisi au poste, dernier ecrivain gagne, par UUID
 * (`46_` §2.3, `46c_`).
 *
 * Aucune bande : les bandes ne sont pas encore synchronisees, un entier de bande n'aurait
 * aucun sens ici. L'echeance de prophylaxie qui a engendre un soin doit etre CONNUE du
 * serveur (les demandes partent avant les faits). Absorber un soin n'a aucun effet de
 * bord : le serveur l'enregistre et le redistribue.
 */
class SoinsCalendrierTable extends TableSync
{
    /**
     * Types d'action proposes par la modale « Nouveau Soin ». Le champ `type_soin` reste
     * un texte LIBRE : « Planifier une Intervention » le saisit tel quel (« Vaccin
     * Newcastle (Rappel) »), hors de ces 4 valeurs.
     */
    public const TYPES = ['Vaccination', 'Traitement curatif', 'Vermifuge', 'Vitamines'];

    public const STATUTS = ['Planifié', 'Effectué', 'En retard', 'Traitement en cours'];

    public function nom(): string
    {
        return 'soins_calendrier';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return SoinCalendrier::class;
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
            'espece', 'date_prevue', 'type_soin', 'statut', 'observations', 'produit', 'dose',
            'remanence_jours', 'veterinaire', 'symptomes', 'cout_fcfa', 'echeance_prophylaxie_id',
        ];
    }

    public function regles(): array
    {
        return [
            'espece' => ['required', 'string', 'max:40'],
            'date_prevue' => ['required', 'date_format:Y-m-d'],
            'type_soin' => ['required', 'string', 'max:255'],
            'statut' => ['required', Rule::in(self::STATUTS)],
            'observations' => ['nullable', 'string', 'max:2000'],
            'produit' => ['nullable', 'string', 'max:255'],
            'dose' => ['nullable', 'string', 'max:255'],
            'remanence_jours' => ['required', 'integer', 'min:0', 'max:3650'],
            'veterinaire' => ['nullable', 'string', 'max:255'],
            'symptomes' => ['nullable', 'string', 'max:2000'],
            'cout_fcfa' => ['required', 'integer', 'min:0'],
            'echeance_prophylaxie_id' => ['nullable', 'uuid'],
        ];
    }

    public function messages(): array
    {
        return [
            'espece.required' => "L'espèce du soin est obligatoire.",
            'espece.max' => "L'espèce du soin est trop longue.",
            'date_prevue.required' => 'La date prévue du soin est invalide.',
            'date_prevue.date_format' => 'La date prévue du soin est invalide.',
            'type_soin.required' => "Le type d'action est obligatoire.",
            'type_soin.max' => "Le type d'action est trop long.",
            'statut.required' => 'Le statut du soin est invalide.',
            'statut.in' => 'Le statut du soin est invalide.',
            'remanence_jours.required' => 'La rémanence ne peut pas être négative.',
            'remanence_jours.integer' => 'La rémanence ne peut pas être négative.',
            'remanence_jours.min' => 'La rémanence ne peut pas être négative.',
            'remanence_jours.max' => 'La rémanence est invraisemblable.',
            'cout_fcfa.required' => 'Le coût ne peut pas être négatif.',
            'cout_fcfa.integer' => 'Le coût ne peut pas être négatif.',
            'cout_fcfa.min' => 'Le coût ne peut pas être négatif.',
            'echeance_prophylaxie_id.uuid' => "L'identifiant de l'échéance doit être un UUID.",
        ];
    }

    protected function controler(array $ligne): ?string
    {
        $echeance = $ligne['echeance_prophylaxie_id'] ?? null;
        if ($echeance !== null && ! EcheanceProphylaxie::query()->whereKey($echeance)->exists()) {
            return 'Échéance de prophylaxie inconnue du serveur.';
        }

        return null;
    }
}
