<?php

namespace App\Sync;

use App\Models\DemandeReferentiel;
use App\Models\Intrant;
use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\ProduitVendable;
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

    public const TYPE_PRODUIT = 'produit_vendable';

    public const TYPE_INTRANT = 'intrant';

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
            self::TYPE_PRODUIT => $this->produit($utilisateur, $demande['donnees'], $saisie, $cle),
            self::TYPE_INTRANT => $this->intrant($utilisateur, $demande['donnees'], $saisie, $cle),
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
     * Cree ou modifie un produit du catalogue. Le STOCK n'est jamais accepte : donnee
     * derivee (ventes, achats), propre a chaque poste. Une demande plus ancienne que la
     * derniere acceptee est refusee ; une demande identique a l'etat actuel est
     * acceptee sans rien changer (deux postes semes du meme catalogue proposent les memes
     * produits : ce n'est pas un conflit).
     */
    private function produit(User $utilisateur, array $donnees, CarbonImmutable $saisie, ?string &$cle): ?string
    {
        $cle = is_string($donnees['id'] ?? null) ? $donnees['id'] : null;

        if (array_key_exists('stock', $donnees)) {
            return 'Le stock n\'est pas synchronisé : il reste propre à chaque poste.';
        }
        $v = Validator::make($donnees, [
            'id' => ['required', 'uuid'],
            'sku' => ['nullable', 'string', 'max:40'],
            'name' => ['required', 'string', 'max:255'],
            'cat' => ['required', 'string', 'max:80'],
            'price' => ['required', 'numeric', 'gt:0'],
            'price_max' => ['nullable', 'numeric', 'gte:price'],
            'unit' => ['required', 'string', 'max:40'],
            'icon' => ['required', 'string', 'max:80'],
            'cout_revient' => ['nullable', 'numeric', 'min:0'],
            'groupe_taxe' => ['nullable', 'string', 'max:5'],
            'threshold' => ['nullable', 'integer', 'min:0'],
            'espece' => ['nullable', 'string', 'max:40'],
            'archive' => ['nullable', 'boolean'],
        ], [
            'id.required' => "L'identifiant du produit est obligatoire.",
            'id.uuid' => "L'identifiant du produit doit être un UUID.",
            'name.required' => 'La désignation du produit est obligatoire.',
            'cat.required' => 'La catégorie du produit est obligatoire.',
            'price.required' => 'Le tarif du produit est obligatoire.',
            'price.gt' => 'Le tarif indicatif doit être supérieur à 0.',
            'price_max.gte' => 'Le prix haut de fourchette ne peut être inférieur au prix bas.',
            'unit.required' => "L'unité du produit est obligatoire.",
            'icon.required' => "L'icône du produit est obligatoire.",
            'cout_revient.min' => 'Le coût de revient ne peut être négatif.',
            'threshold.min' => 'Le seuil d\'alerte ne peut être négatif.',
            'archive.boolean' => 'Le drapeau d\'archivage du produit est invalide.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if (isset($donnees['cout_revient']) && $donnees['cout_revient'] > $donnees['price']) {
            return 'Le coût de revient dépasse le tarif indicatif : chaque vente serait à perte.';
        }
        if (! $utilisateur->can('manage-ventes')) {
            return 'Droit insuffisant pour modifier le catalogue.';
        }

        $champs = [
            'sku' => $donnees['sku'] ?? null,
            'name' => $donnees['name'],
            'cat' => $donnees['cat'],
            'price' => (float) $donnees['price'],
            'price_max' => isset($donnees['price_max']) ? (float) $donnees['price_max'] : null,
            'unit' => $donnees['unit'],
            'icon' => $donnees['icon'],
            'cout_revient' => isset($donnees['cout_revient']) ? (float) $donnees['cout_revient'] : null,
            'groupe_taxe' => $donnees['groupe_taxe'] ?? 'A',
            'threshold' => (int) ($donnees['threshold'] ?? 0),
            'espece' => $donnees['espece'] ?? null,
        ];

        // Suppression au poste : pierre tombale (`archive`), jamais d'effacement.
        $archive = (bool) ($donnees['archive'] ?? false);
        $champs['archive_le'] = $archive ? $saisie : null;

        $produit = ProduitVendable::query()->find($donnees['id']);
        if ($produit === null) {
            (new ProduitVendable)->forceFill($champs + ['id' => $donnees['id'], 'saisi_le' => $saisie])->save();

            return null;
        }

        $identique = collect($champs)->except('archive_le')->every(fn ($valeur, $colonne) => $produit->{$colonne} == $valeur)
            && ($produit->archive_le !== null) === $archive;
        if ($identique) {
            return null;
        }
        if ($produit->saisi_le !== null && $produit->saisi_le->greaterThanOrEqualTo($saisie)) {
            return 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';
        }

        $produit->forceFill($champs + ['saisi_le' => $saisie])->save();

        return null;
    }

    /**
     * Cree ou modifie un intrant. Ni STOCK ni PMP : propres a chaque poste (decision du
     * client). Meme regles que le catalogue : identique accepte sans conflit, plus
     * ancien refuse. La cle est le CODE, partage par tous les postes.
     */
    private function intrant(User $utilisateur, array $donnees, CarbonImmutable $saisie, ?string &$cle): ?string
    {
        $cle = is_string($donnees['code'] ?? null) ? $donnees['code'] : null;

        foreach (['stock', 'pmp'] as $interdit) {
            if (array_key_exists($interdit, $donnees)) {
                return "Le $interdit n'est pas synchronisé : il reste propre à chaque poste.";
            }
        }
        $v = Validator::make($donnees, [
            'code' => ['required', 'string', 'max:40'],
            'name' => ['required', 'string', 'max:255'],
            'cat' => ['required', 'string', 'max:80'],
            'unit' => ['required', 'string', 'max:40'],
            'threshold' => ['nullable', 'integer', 'min:0'],
        ], [
            'code.required' => "Le code de l'intrant est obligatoire.",
            'name.required' => "La désignation de l'intrant est obligatoire.",
            'cat.required' => "La catégorie de l'intrant est obligatoire.",
            'unit.required' => "L'unité de l'intrant est obligatoire.",
            'threshold.min' => 'Le seuil d\'alerte ne peut être négatif.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if (! $utilisateur->can('manage-stocks') && ! $utilisateur->can('manage-achats')) {
            return 'Droit insuffisant pour modifier les intrants.';
        }

        $champs = [
            'name' => $donnees['name'],
            'cat' => $donnees['cat'],
            'unit' => $donnees['unit'],
            'threshold' => (int) ($donnees['threshold'] ?? 0),
        ];
        $intrant = Intrant::query()->find($donnees['code']);
        if ($intrant === null) {
            (new Intrant)->forceFill($champs + ['code' => $donnees['code'], 'saisi_le' => $saisie])->save();

            return null;
        }
        if (collect($champs)->every(fn ($valeur, $colonne) => $intrant->{$colonne} == $valeur)) {
            return null;
        }
        if ($intrant->saisi_le !== null && $intrant->saisi_le->greaterThanOrEqualTo($saisie)) {
            return 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';
        }
        $intrant->forceFill($champs + ['saisi_le' => $saisie])->save();

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
