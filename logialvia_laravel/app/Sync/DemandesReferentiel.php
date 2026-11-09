<?php

namespace App\Sync;

use App\Models\BaremeRation;
use App\Models\DemandeReferentiel;
use App\Models\EcheanceProphylaxie;
use App\Models\Intrant;
use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\PlanComptable;
use App\Models\ProduitVendable;
use App\Models\TauxRationPoids;
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

    public const TYPE_BAREME = 'bareme_ration';

    public const TYPE_TAUX_POIDS = 'taux_ration_poids';

    public const TYPE_ECHEANCE = 'echeance_prophylaxie';
    public const TYPE_COMPTE = 'compte_comptable';

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

            $issue = \App\Support\TransactionRejouee::executer(fn () => $this->une($utilisateur, $deviceId, $demande));

            if ($issue === null) {
                $accepted[] = $id;
            } else {
                $rejected[] = ['id' => $id, 'motif' => $issue] + ($this->codeRefus !== null ? ['code' => $this->codeRefus] : []);
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

    /** Code stable du refus de la demande en cours (`null` : refus ordinaire). */
    private ?string $codeRefus = null;

    /** Refus pour droit insuffisant : code stable `droit_insuffisant` (`47g_`). */
    private function refusDroit(string $motif): string
    {
        $this->codeRefus = DroitsPoste::CODE_REFUS;

        return $motif;
    }

    /**
     * Droits qui ouvrent chaque type de demande (un SEUL suffit). Source unique : le poste
     * l'apprend (`DroitsPoste`, liste `demandes`) et ne propose que ces types.
     */
    public const DROITS_PAR_TYPE = [
        self::TYPE_MODULE => ['manage-modules'],
        self::TYPE_PARAMETRES => ['manage-parametres'],
        self::TYPE_PRODUIT => ['manage-ventes'],
        self::TYPE_INTRANT => ['manage-stocks', 'manage-achats'],
        self::TYPE_BAREME => ['manage-elevage'],
        self::TYPE_TAUX_POIDS => ['manage-elevage'],
        self::TYPE_ECHEANCE => ['manage-elevage'],
        self::TYPE_COMPTE => ['manage-comptabilite'],
    ];

    /** Ce compte peut-il PROPOSER ce type de demande ? (un type inconnu : non) */
    public static function peutProposer(User $utilisateur, string $type): bool
    {
        foreach (self::DROITS_PAR_TYPE[$type] ?? [] as $droit) {
            if ($utilisateur->can($droit)) {
                return true;
            }
        }

        return false;
    }

    /** @return list<string> Les types de demande que ce compte peut proposer. */
    public static function typesPermis(User $utilisateur): array
    {
        return array_values(array_filter(
            array_keys(self::DROITS_PAR_TYPE),
            fn (string $type) => self::peutProposer($utilisateur, $type),
        ));
    }

    /** Un refus lie a l'etat du MOMENT (droits, horloge) n'est jamais definitif : on ne le memorise pas. */
    private const REFUS_PROVISOIRES = [DroitsPoste::CODE_REFUS, GardeHorloge::CODE];

    private function motifDroit(string $type): string
    {
        return match ($type) {
            self::TYPE_MODULE => 'Droit insuffisant pour modifier les modules actifs.',
            self::TYPE_PARAMETRES => 'Droit insuffisant pour modifier les paramètres de l\'entreprise.',
            self::TYPE_PRODUIT => 'Droit insuffisant pour modifier le catalogue.',
            self::TYPE_INTRANT => 'Droit insuffisant pour modifier les intrants.',
            self::TYPE_COMPTE => 'Droit insuffisant pour modifier le plan comptable.',
            default => 'Droit insuffisant pour modifier les paramètres d\'élevage.',
        };
    }

    /** @return string|null Le motif du refus, ou `null` si la demande est acceptee. */
    private function une(User $utilisateur, string $deviceId, array $demande): ?string
    {
        $this->codeRefus = null;

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

        // `47g_` : un instant de saisie dans le futur gagnerait toutes les comparaisons.
        if (($motif = GardeHorloge::controler(['saisi_le' => $demande['saisi_le']])) !== null) {
            $this->codeRefus = GardeHorloge::CODE;

            return $motif;
        }

        // `47g_` : le droit se verifie AVANT tout (le poste ne propose que ce qu'il peut ecrire).
        if (isset(self::DROITS_PAR_TYPE[$demande['type']]) && ! self::peutProposer($utilisateur, $demande['type'])) {
            return $this->refusDroit($this->motifDroit($demande['type']));
        }

        $motif = match ($demande['type']) {
            self::TYPE_MODULE => $this->module($utilisateur, $demande['donnees'], $saisie, $cle),
            self::TYPE_PARAMETRES => $this->parametres($utilisateur, $demande['donnees'], $saisie, $cle),
            self::TYPE_PRODUIT => $this->produit($utilisateur, $demande['donnees'], $saisie, $cle),
            self::TYPE_INTRANT => $this->intrant($utilisateur, $demande['donnees'], $saisie, $cle),
            self::TYPE_BAREME, self::TYPE_TAUX_POIDS, self::TYPE_ECHEANCE => $this->parametreElevage($utilisateur, $demande['type'], $demande['donnees'], $saisie, $cle),
            self::TYPE_COMPTE => $this->compte($utilisateur, $demande['donnees'], $saisie, $cle),
            default => "Type de demande inconnu du serveur : « {$demande['type']} ».",
        };

        // Droits et horloge : refus provisoire, rien n'est memorise (la meme demande,
        // renvoyee quand le droit est accorde, sera jugee de nouveau).
        if ($this->codeRefus !== null && in_array($this->codeRefus, self::REFUS_PROVISOIRES, true)) {
            return $motif;
        }

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
            return $this->refusDroit('Droit insuffisant pour modifier les modules actifs.');
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
            return $this->refusDroit('Droit insuffisant pour modifier les paramètres de l\'entreprise.');
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
            return $this->refusDroit('Droit insuffisant pour modifier le catalogue.');
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
            'archive' => ['nullable', 'boolean'],
        ], [
            'code.required' => "Le code de l'intrant est obligatoire.",
            'name.required' => "La désignation de l'intrant est obligatoire.",
            'cat.required' => "La catégorie de l'intrant est obligatoire.",
            'unit.required' => "L'unité de l'intrant est obligatoire.",
            'threshold.min' => 'Le seuil d\'alerte ne peut être négatif.',
            'archive.boolean' => 'Le drapeau d\'archivage de l\'intrant est invalide.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if (! $utilisateur->can('manage-stocks') && ! $utilisateur->can('manage-achats')) {
            return $this->refusDroit('Droit insuffisant pour modifier les intrants.');
        }

        $champs = [
            'name' => $donnees['name'],
            'cat' => $donnees['cat'],
            'unit' => $donnees['unit'],
            'threshold' => (int) ($donnees['threshold'] ?? 0),
        ];
        // Suppression au poste : pierre tombale (`archive`), jamais d'effacement (47h D4).
        $archive = (bool) ($donnees['archive'] ?? false);
        $intrant = Intrant::withoutGlobalScopes()->find($donnees['code']);
        if ($intrant === null) {
            (new Intrant)->forceFill($champs + [
                'code' => $donnees['code'], 'saisi_le' => $saisie, 'archive_le' => $archive ? $saisie : null,
            ])->save();

            return null;
        }
        if (collect($champs)->every(fn ($valeur, $colonne) => $intrant->{$colonne} == $valeur)
            && ($intrant->archive_le !== null) === $archive) {
            return null;
        }
        if ($intrant->saisi_le !== null && $intrant->saisi_le->greaterThanOrEqualTo($saisie)) {
            return 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';
        }
        $intrant->forceFill($champs + ['saisi_le' => $saisie, 'archive_le' => $archive ? $saisie : null])->save();

        return null;
    }

    // ------------------------------------------------- Parametres d'elevage (P7c)

    /**
     * Cree ou modifie un bareme, un taux par classe de poids ou une echeance de
     * prophylaxie (`46c_`). Memes regles que le catalogue :
     *
     *  - droit `manage-elevage` ; une SUPPRESSION (pierre tombale, `archive`) exige
     *    `archive-elevage` ;
     *  - une demande identique a l'etat actuel est acceptee sans rien changer (deux
     *    postes semes du meme programme proposent les memes lignes : pas un conflit) ;
     *  - une demande plus ANCIENNE (ou egale) que la derniere acceptee est refusee ;
     *  - la cle naturelle (espece + stade, espece + poids minimal) ne peut etre portee
     *    que par UN identifiant : un autre UUID est refuse, avec son motif.
     */
    private function parametreElevage(User $utilisateur, string $type, array $donnees, CarbonImmutable $saisie, ?string &$cle): ?string
    {
        $cle = is_string($donnees['id'] ?? null) ? $donnees['id'] : null;

        [$modele, $champs, $regles, $messages] = match ($type) {
            self::TYPE_BAREME => [BaremeRation::class, ['espece', 'stade', 'ration_grammes_par_jour', 'confirme'], [
                'espece' => ['required', 'string', 'max:40'],
                'stade' => ['required', 'string', 'max:255'],
                'ration_grammes_par_jour' => ['required', 'integer', 'min:1', 'max:20000'],
                'confirme' => ['required', 'boolean'],
            ], [
                'espece.required' => "L'espèce est obligatoire.",
                'stade.required' => 'Le stade du barème est obligatoire.',
                'ration_grammes_par_jour.required' => 'La ration doit être comprise entre 1 et 20 000 g par jour.',
                'ration_grammes_par_jour.integer' => 'La ration doit être comprise entre 1 et 20 000 g par jour.',
                'ration_grammes_par_jour.min' => 'La ration doit être comprise entre 1 et 20 000 g par jour.',
                'ration_grammes_par_jour.max' => 'La ration doit être comprise entre 1 et 20 000 g par jour.',
                'confirme.required' => 'Le statut du barème est invalide.',
                'confirme.boolean' => 'Le statut du barème est invalide.',
            ]],
            self::TYPE_TAUX_POIDS => [TauxRationPoids::class, ['espece', 'poids_min_g', 'poids_max_g', 'taux_pourcent', 'confirme'], [
                'espece' => ['required', 'string', 'max:40'],
                'poids_min_g' => ['required', 'integer', 'min:0'],
                'poids_max_g' => ['nullable', 'integer', 'gt:poids_min_g'],
                'taux_pourcent' => ['required', 'numeric', 'gt:0', 'max:25'],
                'confirme' => ['required', 'boolean'],
            ], [
                'espece.required' => "L'espèce est obligatoire.",
                'poids_min_g.required' => 'Le poids minimal est invalide.',
                'poids_min_g.integer' => 'Le poids minimal est invalide.',
                'poids_min_g.min' => 'Le poids minimal est invalide.',
                'poids_max_g.integer' => 'Le poids maximal doit dépasser le poids minimal.',
                'poids_max_g.gt' => 'Le poids maximal doit dépasser le poids minimal.',
                'taux_pourcent.required' => 'Le taux doit être compris entre 0 et 25 % du poids vif par jour.',
                'taux_pourcent.numeric' => 'Le taux doit être compris entre 0 et 25 % du poids vif par jour.',
                'taux_pourcent.gt' => 'Le taux doit être compris entre 0 et 25 % du poids vif par jour.',
                'taux_pourcent.max' => 'Le taux doit être compris entre 0 et 25 % du poids vif par jour.',
                'confirme.required' => 'Le statut du taux est invalide.',
                'confirme.boolean' => 'Le statut du taux est invalide.',
            ]],
            default => [EcheanceProphylaxie::class, ['espece', 'jour_cycle', 'traitement', 'produit', 'remanence_jours', 'dose'], [
                'espece' => ['required', 'string', 'max:40'],
                'jour_cycle' => ['required', 'integer', 'min:1', 'max:365'],
                'traitement' => ['required', 'string', 'max:255'],
                'produit' => ['required', 'string', 'max:255'],
                'remanence_jours' => ['required', 'integer', 'min:0', 'max:3650'],
                'dose' => ['nullable', 'string', 'max:255'],
            ], [
                'espece.required' => "L'espèce est obligatoire.",
                'jour_cycle.required' => 'Le jour du cycle doit être compris entre 1 et 365.',
                'jour_cycle.integer' => 'Le jour du cycle doit être compris entre 1 et 365.',
                'jour_cycle.min' => 'Le jour du cycle doit être compris entre 1 et 365.',
                'jour_cycle.max' => 'Le jour du cycle doit être compris entre 1 et 365.',
                'traitement.required' => 'Le traitement et le produit sont obligatoires.',
                'produit.required' => 'Le traitement et le produit sont obligatoires.',
                'remanence_jours.required' => 'La rémanence ne peut pas être négative.',
                'remanence_jours.integer' => 'La rémanence ne peut pas être négative.',
                'remanence_jours.min' => 'La rémanence ne peut pas être négative.',
                'remanence_jours.max' => 'La rémanence est invraisemblable.',
            ]],
        };

        $v = Validator::make($donnees, array_merge([
            'id' => ['required', 'uuid'],
            'archive' => ['nullable', 'boolean'],
        ], $regles), array_merge([
            'id.required' => "L'identifiant de la ligne est obligatoire.",
            'id.uuid' => "L'identifiant de la ligne doit être un UUID.",
            'archive.boolean' => "Le drapeau d'archivage est invalide.",
        ], $messages));
        if ($v->fails()) {
            return $v->errors()->first();
        }

        $archive = (bool) ($donnees['archive'] ?? false);
        if (! $utilisateur->can($archive ? 'archive-elevage' : 'manage-elevage')) {
            return $this->refusDroit($archive
                ? 'Droit insuffisant pour supprimer un paramètre d\'élevage.'
                : 'Droit insuffisant pour modifier les paramètres d\'élevage.');
        }

        $valeurs = [];
        foreach ($champs as $champ) {
            $valeur = $donnees[$champ] ?? null;
            $valeurs[$champ] = $champ === 'dose' && $valeur === '' ? null : $valeur;
        }

        // Cle naturelle : une AUTRE ligne ne peut pas la porter.
        $conflit = match ($type) {
            self::TYPE_BAREME => BaremeRation::query()->where('espece', $valeurs['espece'])
                ->where('stade', $valeurs['stade'])->where('id', '!=', $donnees['id'])->exists()
                ? 'Un barème existe déjà pour ce stade.' : null,
            self::TYPE_TAUX_POIDS => TauxRationPoids::query()->where('espece', $valeurs['espece'])
                ->where('poids_min_g', $valeurs['poids_min_g'])->where('id', '!=', $donnees['id'])->exists()
                ? 'Une classe de poids existe déjà avec ce poids minimal.' : null,
            default => null,
        };
        if ($conflit !== null) {
            return $conflit;
        }

        $ligne = $modele::query()->find($donnees['id']);
        if ($ligne === null) {
            (new $modele)->forceFill($valeurs + [
                'id' => $donnees['id'],
                'saisi_le' => $saisie,
                'archive_le' => $archive ? $saisie : null,
            ])->save();

            return null;
        }

        $identique = collect($valeurs)->every(
            fn ($valeur, $colonne) => $colonne === 'taux_pourcent'
                ? abs((float) $ligne->{$colonne} - (float) $valeur) < 1e-9
                : $ligne->{$colonne} == $valeur,
        ) && ($ligne->archive_le !== null) === $archive;
        if ($identique) {
            return null;
        }
        if ($ligne->saisi_le !== null && $ligne->saisi_le->greaterThanOrEqualTo($saisie)) {
            return 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';
        }

        $ligne->forceFill($valeurs + ['saisi_le' => $saisie, 'archive_le' => $archive ? $saisie : null])->save();

        return null;
    }

    /**
     * Cree ou modifie un compte du plan comptable (P8). Cle : le NUMERO de compte, le meme
     * sur tous les postes. Droit `manage-comptabilite`. Memes regles que le catalogue :
     * identique accepte sans conflit, plus ancien refuse. Son numero, cle des ecritures,
     * ne change jamais, et la classe est le premier chiffre du numero.
     */
    private function compte(User $utilisateur, array $donnees, CarbonImmutable $saisie, ?string &$cle): ?string
    {
        $cle = is_string($donnees['numero_compte'] ?? null) ? $donnees['numero_compte'] : null;

        $v = Validator::make($donnees, [
            'numero_compte' => ['required', 'string', 'regex:/^[1-7]\d{0,19}$/'],
            'libelle' => ['required', 'string', 'max:255'],
            'classe' => ['required', 'string', 'size:1', 'in:1,2,3,4,5,6,7'],
            'archive' => ['required', 'boolean'],
        ], [
            'numero_compte.required' => 'Le numéro de compte est obligatoire.',
            'numero_compte.regex' => 'Un numéro de compte SYSCOHADA commence par un chiffre de 1 à 7.',
            'libelle.required' => 'Le libellé est obligatoire.',
            'classe.required' => 'La classe est obligatoire.',
            'classe.in' => 'La classe d\'un compte va de 1 à 7.',
            'archive.required' => "L'état d'archivage du compte est obligatoire.",
            'archive.boolean' => "L'état d'archivage du compte est invalide.",
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if (! str_starts_with($donnees['numero_compte'], $donnees['classe'])) {
            return "Le numéro {$donnees['numero_compte']} ne peut pas appartenir à la classe {$donnees['classe']}.";
        }
        if (! $utilisateur->can('manage-comptabilite')) {
            return $this->refusDroit('Droit insuffisant pour modifier le plan comptable.');
        }

        $champs = [
            'libelle' => $donnees['libelle'],
            'classe' => $donnees['classe'],
            'archive' => filter_var($donnees['archive'], FILTER_VALIDATE_BOOLEAN),
        ];

        $compte = PlanComptable::query()->find($donnees['numero_compte']);
        if ($compte === null) {
            $nouveau = (new PlanComptable)->forceFill($champs + ['numero_compte' => $donnees['numero_compte'], 'saisi_le' => $saisie]);
            $nouveau->save();
            // Un compte cree par une demande est DECIDE : `updated_at` doit depasser `created_at`.
            $nouveau->touch();

            return null;
        }

        if (collect($champs)->every(fn ($valeur, $colonne) => $compte->{$colonne} == $valeur)) {
            return null;
        }
        if ($compte->saisi_le !== null && $compte->saisi_le->greaterThanOrEqualTo($saisie)) {
            return 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';
        }
        // Le numero est la cle des ecritures et ne change jamais ; la classe EST son premier
        // chiffre (verifie plus haut) : un compte mouvemente ne peut donc pas changer de
        // classe, ni deplacer retroactivement ses ecritures d'un poste du bilan a un autre.

        // La valeur differe (le cas identique est sorti plus haut) : `updated_at` avance, le
        // compte est desormais DECIDE.
        $compte->forceFill($champs + ['saisi_le' => $saisie])->save();

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
