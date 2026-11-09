<?php

namespace App\Sync;

use App\Models\DemandeReferentiel;
use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\User;
use App\Support\Audit;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * `POST /api/sync/demandes` : le poste PROPOSE une modification de referentiel, le
 * serveur DECIDE (`46_` §2.2 et §4.3).
 *
 *  - droit verifie par type (`manage-modules`, `manage-parametres`) ;
 *  - idempotent par l'UUID de la demande : rejouee, elle rend la meme issue ;
 *  - une demande plus ANCIENNE que la derniere decision du serveur est refusee
 *    (« une modification plus recente existe ») : le poste la recevra au tirage ;
 *  - une demande acceptee DECIDE la ligne (`updated_at` avance) : elle redescend
 *    vers tous les postes, et la ligne n'est plus une valeur de semis ;
 *  - champs propres a une machine ou verrous de securite : jamais acceptes.
 */
class DemandesReferentiel
{
    public const TYPE_MODULE = 'module_actif';

    public const TYPE_PARAMETRES = 'parametres_entreprise';

    /** Champs de `parametres_entreprise` qu'un poste peut proposer. */
    public const CHAMPS_PARAMETRES = [
        'raison_sociale', 'nom_promoteur', 'adresse_siege', 'telephone', 'email', 'ifu', 'rccm',
        'mecef_actif', 'mecef_url', 'mecef_nim', 'smtp_serveur', 'smtp_port', 'smtp_securite',
        'delai_paiement_jours', 'prefixe_enclos', 'prefixe_cage', 'prefixe_bande', 'prefixe_bassin',
        'prefixe_bac', 'prefixe_parc',
    ];

    /** @return array{accepted: list<string>, rejected: list<array{id: string, motif: string}>} */
    public function traiter(User $utilisateur, string $deviceId, array $demandes): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($demandes as $demande) {
            $demande = (array) $demande;
            $id = is_string($demande['id'] ?? null) ? $demande['id'] : '';

            $issue = DB::transaction(fn () => $this->une($utilisateur, $deviceId, $demande), 3);

            if ($issue === null) {
                $accepted[] = $id;
            } else {
                $rejected[] = ['id' => $id, 'motif' => $issue];
            }
        }

        if ($demandes !== []) {
            Audit::enregistrer('sync.demandes', $utilisateur, [
                'poste' => $deviceId,
                'acceptees' => count($accepted),
                'refusees' => count($rejected),
            ]);
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    /** @return string|null Le motif du refus, ou `null` si la demande est acceptee. */
    private function une(User $utilisateur, string $deviceId, array $demande): ?string
    {
        $v = Validator::make($demande, [
            'id' => ['required', 'uuid'],
            'type' => ['required', 'string'],
            'saisi_le' => ['required', 'date'],
            'donnees' => ['required', 'array'],
        ], [
            'id.required' => "L'identifiant de la demande est obligatoire.",
            'id.uuid' => "L'identifiant de la demande doit être un UUID.",
            'type.required' => 'Le type de la demande est obligatoire.',
            'saisi_le.required' => 'La date de saisie de la demande est obligatoire.',
            'saisi_le.date' => 'La date de saisie de la demande est invalide.',
            'donnees.required' => 'Les données de la demande sont obligatoires.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }

        // Idempotence : une demande deja traitee rend la meme issue.
        $connue = DemandeReferentiel::query()->find($demande['id']);
        if ($connue !== null) {
            return $connue->statut === 'acceptee' ? null : $connue->motif;
        }

        $saisie = CarbonImmutable::parse($demande['saisi_le'])->utc();

        $motif = match ($demande['type']) {
            self::TYPE_MODULE => $this->module($utilisateur, $demande['donnees'], $saisie, $cle),
            self::TYPE_PARAMETRES => $this->parametres($utilisateur, $demande['donnees'], $saisie, $cle),
            default => "Type de demande inconnu du serveur : « {$demande['type']} ».",
        };

        DemandeReferentiel::query()->create([
            'id' => $demande['id'],
            'device_id' => $deviceId,
            'type' => $demande['type'],
            'cle' => $cle ?? '',
            'donnees' => $demande['donnees'],
            'saisi_le' => $saisie,
            'statut' => $motif === null ? 'acceptee' : 'refusee',
            'motif' => $motif,
        ]);

        return $motif;
    }

    private function module(User $utilisateur, array $donnees, CarbonImmutable $saisie, ?string &$cle): ?string
    {
        $v = Validator::make($donnees, [
            'module_id' => ['required', 'string'],
            'is_actif' => ['required', 'boolean'],
        ], [
            'module_id.required' => "L'identifiant du module est obligatoire.",
            'is_actif.required' => "L'état du module est obligatoire.",
            'is_actif.boolean' => "L'état du module doit être actif ou inactif.",
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }

        $cle = (string) $donnees['module_id'];
        if (! array_key_exists($cle, config('logialvia.modules'))) {
            return "Module inconnu du serveur : « $cle ».";
        }
        if (! $utilisateur->can('manage-modules')) {
            return 'Droit insuffisant pour modifier les modules actifs.';
        }

        $module = ModuleActif::query()->where('module_id', $cle)->first();
        if ($module !== null && $this->plusRecente($module->updated_at, $module->created_at, $saisie)) {
            return 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';
        }

        if ($module === null) {
            ModuleActif::query()->create([
                'module_id' => $cle,
                'is_actif' => (bool) $donnees['is_actif'],
                'espece' => config('logialvia.modules')[$cle],
            ]);
        } else {
            $module->forceFill(['is_actif' => (bool) $donnees['is_actif']])->save();
            $module->touch(); // DECIDE la ligne : updated_at avance meme si la valeur est identique
        }

        return null;
    }

    private function parametres(User $utilisateur, array $donnees, CarbonImmutable $saisie, ?string &$cle): ?string
    {
        $cle = 'parametres';

        $inconnus = array_diff(array_keys($donnees), self::CHAMPS_PARAMETRES);
        if ($inconnus !== []) {
            return 'Champ(s) non modifiable(s) depuis un poste : '.implode(', ', $inconnus).'.';
        }

        $v = Validator::make($donnees, [
            'raison_sociale' => ['nullable', 'string', 'max:255'],
            'nom_promoteur' => ['nullable', 'string', 'max:255'],
            'adresse_siege' => ['nullable', 'string', 'max:255'],
            'telephone' => ['nullable', 'string', 'max:255'],
            'email' => ['nullable', 'string', 'max:255'],
            'ifu' => ['nullable', 'string', 'max:255'],
            'rccm' => ['nullable', 'string', 'max:255'],
            'mecef_actif' => ['nullable', 'boolean'],
            'mecef_url' => ['nullable', 'string', 'max:255'],
            'mecef_nim' => ['nullable', 'string', 'max:255'],
            'smtp_serveur' => ['nullable', 'string', 'max:255'],
            'smtp_port' => ['nullable', 'integer', 'min:1', 'max:65535'],
            'smtp_securite' => ['nullable', 'string', 'max:20'],
            'delai_paiement_jours' => ['nullable', 'integer', 'min:0', 'max:3650'],
            'prefixe_enclos' => ['nullable', 'string', 'min:1', 'max:4'],
            'prefixe_cage' => ['nullable', 'string', 'min:1', 'max:4'],
            'prefixe_bande' => ['nullable', 'string', 'min:1', 'max:4'],
            'prefixe_bassin' => ['nullable', 'string', 'min:1', 'max:4'],
            'prefixe_bac' => ['nullable', 'string', 'min:1', 'max:4'],
            'prefixe_parc' => ['nullable', 'string', 'min:1', 'max:4'],
        ], [
            'raison_sociale.max' => 'La raison sociale est trop longue.',
            'smtp_port.integer' => 'Le port SMTP doit être un nombre entier.',
            'smtp_port.max' => 'Le port SMTP est invalide.',
            'prefixe_enclos.max' => 'Un préfixe compte 4 caractères au plus.',
            'prefixe_cage.max' => 'Un préfixe compte 4 caractères au plus.',
            'prefixe_bande.max' => 'Un préfixe compte 4 caractères au plus.',
            'prefixe_bassin.max' => 'Un préfixe compte 4 caractères au plus.',
            'prefixe_bac.max' => 'Un préfixe compte 4 caractères au plus.',
            'prefixe_parc.max' => 'Un préfixe compte 4 caractères au plus.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if (! $utilisateur->can('manage-parametres')) {
            return 'Droit insuffisant pour modifier les paramètres de l\'entreprise.';
        }

        $parametres = ParametresEntreprise::courant();
        if ($this->plusRecente($parametres->updated_at, $parametres->created_at, $saisie)) {
            return 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';
        }

        // Une valeur vide ne compte pas : elle n'efface jamais une valeur du serveur
        // (meme regle que le poste a la reception).
        $valeurs = array_filter(
            $donnees,
            fn ($valeur) => $valeur !== null && $valeur !== '',
        );
        // Les colonnes NOT NULL n'acceptent de toute facon pas de null.
        $parametres->forceFill($valeurs)->save();
        $parametres->touch();

        return null;
    }

    /**
     * La demande est-elle plus ANCIENNE que la derniere decision du serveur ? Une ligne
     * de semis (`updated_at == created_at`) n'a jamais ete decidee : toute saisie du
     * poste la depasse.
     */
    private function plusRecente(mixed $miseAJour, mixed $creation, CarbonImmutable $saisie): bool
    {
        if ($miseAJour === null || $creation === null) {
            return false;
        }
        $decide = CarbonImmutable::parse($miseAJour)->utc()->greaterThan(CarbonImmutable::parse($creation)->utc());

        return $decide && CarbonImmutable::parse($miseAJour)->utc()->greaterThan($saisie);
    }
}
