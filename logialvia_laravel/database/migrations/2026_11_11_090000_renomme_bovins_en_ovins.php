<?php

use App\Support\FilieresElevage;
use App\Support\UuidDeterministe;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * DV-22 : la filiere Bovins devient Ovins a la demande du client (miroir de la migration v51 du poste,
 * `MigrationBovinsVersOvins`). Toutes les lignes `bovins` passent a `ovins` :
 *
 *  - IDEMPOTENTE (rejouable) et SANS DOUBLON : si la ligne `ovins` existe deja (meme cle), elle l'emporte et la
 *    ligne `bovins` est retiree ; un referentiel retire est ARCHIVE (pierre tombale), jamais efface ;
 *  - identifiants DETERMINISTES recalcules (fiche journaliere, compteur de ventes, bareme, taux, echeance) : le
 *    serveur les verifie ; une ligne saisie (UUID aleatoire) garde le sien. Le lien soin -> echeance suit ;
 *  - curseurs de tirage avances (`serveur_modifie_le` des faits, `updated_at` des referentiels) : les postes recoivent
 *    les lignes renommees ; `updated_at` des faits (instant de SAISIE) n'est PAS touche ;
 *  - valeurs d'origine reecrites : un bareme, une classe de poids ou une echeance restes EXACTEMENT a leur valeur
 *    d'ouverture bovine prennent la valeur d'ouverture ovine ; une valeur modifiee est conservee.
 *
 * Un poste ancien peut encore envoyer `bovins` : voir `App\Sync\AliasHerites`.
 */
return new class extends Migration
{
    private const ANCIEN = 'bovins';

    private const NOUVEAU = 'ovins';

    /** Stade => ration d'ouverture bovine / ovine (g par tete et par jour). */
    private const BAREMES = [
        'Veau' => ['ancienne' => 1500, 'nouveau_stade' => 'Agneau', 'nouvelle' => 300],
        'Embouche' => ['ancienne' => 7000, 'nouveau_stade' => 'Embouche', 'nouvelle' => 600],
        'Reproducteur' => ['ancienne' => 9000, 'nouveau_stade' => 'Reproducteur', 'nouvelle' => 800],
    ];

    /** Classes d'ouverture bovines => ovines : [min, max, taux] => [min, max, taux]. */
    private const TAUX = [
        [[0, 150000, 3.5], [0, 15000, 4.0]],
        [[150000, 300000, 3.0], [15000, 30000, 3.5]],
        [[300000, null, 2.5], [30000, null, 3.0]],
    ];

    /** Echeances d'ouverture bovines : jour => [traitement, produit] ; les nouvelles : jour => [traitement, produit, dose, remanence]. */
    private const ECHEANCES_ANCIENNES = [
        1 => ['Déparasitage interne', 'Albendazole'],
        7 => ['Détiquage (lutte contre les tiques)', 'Deltaméthrine, bain ou pulvérisation'],
        15 => ['Vaccin péripneumonie contagieuse bovine (PPCB)', 'Vaccin T1/44'],
        30 => ['Vaccin charbon bactéridien et symptomatique', 'Vaccin charbon'],
        45 => ['Vaccin pasteurellose', 'Vaccin Pasteurella'],
        60 => ['Déparasitage interne et externe', 'Ivermectine 1 %'],
        90 => ['Détiquage (rappel)', 'Deltaméthrine, bain ou pulvérisation'],
        180 => ['Déparasitage interne (rappel semestriel)', 'Albendazole'],
        365 => ['Rappel annuel PPCB et charbon', 'Vaccin T1/44 et vaccin charbon'],
    ];

    private const ECHEANCES_NOUVELLES = [
        1 => ['Déparasitage interne (strongles)', 'Albendazole', '5 mg par kg de poids vif, voie orale', 14],
        7 => ['Traitement externe (gale, tiques)', 'Deltaméthrine, bain ou pulvérisation', 'Dilution selon la notice du fabricant', 7],
        15 => ['Vaccin peste des petits ruminants (PPR)', 'Vaccin PPR (souche Nigeria 75/1)', '1 dose selon la notice, voie sous-cutanée', 0],
        30 => ['Vaccin entérotoxémie', 'Vaccin clostridies (entérotoxémie)', '2 mL selon la notice, voie sous-cutanée', 0],
        45 => ['Vaccin pasteurellose', 'Vaccin Pasteurella', '2 mL selon la notice, voie sous-cutanée', 0],
        60 => ['Déparasitage interne et externe', 'Ivermectine 1 %', '1 mL pour 50 kg de poids vif (0,2 mg/kg), voie sous-cutanée', 35],
        90 => ['Vitamines et minéraux', 'Complexe vitamines A, D3, E et oligo-éléments', 'Selon la notice du produit, voie orale ou injectable', 0],
        180 => ['Déparasitage interne (rappel semestriel, strongles)', 'Albendazole', '5 mg par kg de poids vif, voie orale', 14],
        365 => ['Rappel annuel PPR et entérotoxémie', 'Vaccin PPR et vaccin entérotoxémie', '1 dose de chacun selon la notice', 0],
    ];

    public function up(): void
    {
        DB::transaction(function () {
            $maintenant = now('UTC')->format('Y-m-d H:i:s.u');

            $this->modules($maintenant);
            $this->fichesJournee($maintenant);
            $this->ventesJour($maintenant);
            $this->baremes($maintenant);
            $this->taux($maintenant);
            $this->echeances($maintenant);
            foreach (['bandes', 'soins_calendrier', 'infirmerie'] as $table) {
                $this->renommerSimplement($table, 'serveur_modifie_le', $maintenant);
            }
            $this->renommerSimplement('lignes_vente', null, $maintenant);
            $this->produits($maintenant);
        });
    }

    public function down(): void
    {
        // Un renommage voulu par le client ne se defait pas : les lignes `ovins` n'ont plus rien de bovin.
    }

    // ------------------------------------------------------------------ utilitaires

    private function utilisable(string $table): bool
    {
        return Schema::hasTable($table) && Schema::hasColumn($table, 'espece');
    }

    private function jour(mixed $date): string
    {
        return substr((string) $date, 0, 10);
    }

    // -------------------------------------------------------------------- modules

    private function modules(string $maintenant): void
    {
        if (! Schema::hasTable('modules_actifs')) {
            return;
        }
        $existe = DB::table('modules_actifs')->where('module_id', self::NOUVEAU)->exists();
        if ($existe) {
            DB::table('modules_actifs')->where('module_id', self::ANCIEN)->delete();

            return;
        }
        DB::table('modules_actifs')->where('module_id', self::ANCIEN)->update([
            'module_id' => self::NOUVEAU, 'espece' => self::NOUVEAU, 'updated_at' => $maintenant,
        ]);
    }

    // ---------------------------------------------------------------------- faits

    private function fichesJournee(string $maintenant): void
    {
        if (! $this->utilisable('fiche_journee')) {
            return;
        }
        foreach (DB::table('fiche_journee')->where('espece', self::ANCIEN)->get(['id', 'date']) as $l) {
            $nouvelId = UuidDeterministe::ficheJournee(self::NOUVEAU, $this->jour($l->date));
            if (DB::table('fiche_journee')->where('id', $nouvelId)->exists()) {
                DB::table('fiche_journee')->where('id', $l->id)->delete();
            } else {
                DB::table('fiche_journee')->where('id', $l->id)->update([
                    'id' => $nouvelId, 'espece' => self::NOUVEAU, 'serveur_modifie_le' => $maintenant,
                ]);
            }
        }
    }

    private function ventesJour(string $maintenant): void
    {
        if (! $this->utilisable('fiche_ventes_jour')) {
            return;
        }
        foreach (DB::table('fiche_ventes_jour')->where('espece', self::ANCIEN)->get(['id', 'date', 'device_id']) as $l) {
            $nouvelId = UuidDeterministe::ventesJour(self::NOUVEAU, $this->jour($l->date), (string) $l->device_id);
            if (DB::table('fiche_ventes_jour')->where('id', $nouvelId)->exists()) {
                DB::table('fiche_ventes_jour')->where('id', $l->id)->delete();
            } else {
                DB::table('fiche_ventes_jour')->where('id', $l->id)->update([
                    'id' => $nouvelId, 'espece' => self::NOUVEAU, 'serveur_modifie_le' => $maintenant,
                ]);
            }
        }
    }

    // ---------------------------------------------------------------- referentiels

    /** Retire une ligne `bovins` que la ligne `ovins` rend inutile : pierre tombale, jamais d'effacement. */
    private function archiver(string $table, string $id, string $maintenant): void
    {
        DB::table($table)->where('id', $id)->update(['archive_le' => $maintenant, 'updated_at' => $maintenant]);
    }

    private function baremes(string $maintenant): void
    {
        if (! $this->utilisable('baremes_ration')) {
            return;
        }
        foreach (DB::table('baremes_ration')->where('espece', self::ANCIEN)->get() as $l) {
            $regle = self::BAREMES[$l->stade] ?? null;
            $stade = $regle['nouveau_stade'] ?? $l->stade;
            $ration = (int) $l->ration_grammes_par_jour;
            if ($regle !== null && $regle['ancienne'] === $ration && ! $l->confirme) {
                $ration = $regle['nouvelle'];
            }
            $nouvelId = $l->id === FilieresElevage::idBareme(self::ANCIEN, $l->stade)
                ? FilieresElevage::idBareme(self::NOUVEAU, $stade)
                : $l->id;

            if (DB::table('baremes_ration')->where('espece', self::NOUVEAU)->where('stade', $stade)->exists()) {
                $this->archiver('baremes_ration', $l->id, $maintenant);

                continue;
            }
            DB::table('baremes_ration')->where('id', $l->id)->update([
                'id' => $nouvelId, 'espece' => self::NOUVEAU, 'stade' => $stade,
                'ration_grammes_par_jour' => $ration, 'updated_at' => $maintenant,
            ]);
        }
    }

    private function taux(string $maintenant): void
    {
        if (! $this->utilisable('taux_ration_poids')) {
            return;
        }
        $lignes = DB::table('taux_ration_poids')->where('espece', self::ANCIEN)->orderBy('poids_min_g')->get()->values();

        // Les 3 classes d'ouverture se reecrivent ensemble, ou pas du tout (les bornes ne doivent pas se recouvrir).
        $inchangees = $lignes->count() === count(self::TAUX);
        foreach ($lignes as $i => $l) {
            if (! $inchangees) {
                break;
            }
            [$min, $max, $taux] = self::TAUX[$i][0];
            $inchangees = (int) $l->poids_min_g === $min
                && ($l->poids_max_g === null ? null : (int) $l->poids_max_g) === $max
                && abs((float) $l->taux_pourcent - $taux) < 1e-9
                && ! $l->confirme;
        }

        foreach ($lignes as $i => $l) {
            $min = (int) $l->poids_min_g;
            $nouvMin = $min;
            $nouvMax = $l->poids_max_g === null ? null : (int) $l->poids_max_g;
            $nouvTaux = (float) $l->taux_pourcent;
            if ($inchangees) {
                [$nouvMin, $nouvMax, $nouvTaux] = self::TAUX[$i][1];
            }
            $nouvelId = $l->id === FilieresElevage::idTaux(self::ANCIEN, $min)
                ? FilieresElevage::idTaux(self::NOUVEAU, $nouvMin)
                : $l->id;

            if (DB::table('taux_ration_poids')->where('espece', self::NOUVEAU)->where('poids_min_g', $nouvMin)->exists()) {
                $this->archiver('taux_ration_poids', $l->id, $maintenant);

                continue;
            }
            DB::table('taux_ration_poids')->where('id', $l->id)->update([
                'id' => $nouvelId, 'espece' => self::NOUVEAU, 'poids_min_g' => $nouvMin,
                'poids_max_g' => $nouvMax, 'taux_pourcent' => $nouvTaux, 'updated_at' => $maintenant,
            ]);
        }
    }

    private function echeances(string $maintenant): void
    {
        if (! $this->utilisable('calendrier_prophylaxie')) {
            return;
        }
        $aSoins = Schema::hasTable('soins_calendrier') && Schema::hasColumn('soins_calendrier', 'echeance_prophylaxie_id');

        foreach (DB::table('calendrier_prophylaxie')->where('espece', self::ANCIEN)->get() as $l) {
            $jour = (int) $l->jour_cycle;
            $ouverture = self::ECHEANCES_ANCIENNES[$jour] ?? null;
            $cible = $ouverture !== null && $ouverture[0] === $l->traitement && $ouverture[1] === $l->produit
                ? self::ECHEANCES_NOUVELLES[$jour]
                : null;
            $traitement = $cible[0] ?? $l->traitement;
            $produit = $cible[1] ?? $l->produit;
            $nouvelId = $l->id === FilieresElevage::idEcheance(self::ANCIEN, $jour, $l->traitement, $l->produit)
                ? FilieresElevage::idEcheance(self::NOUVEAU, $jour, $traitement, $produit)
                : $l->id;

            if ($nouvelId !== $l->id && DB::table('calendrier_prophylaxie')->where('id', $nouvelId)->exists()) {
                $this->archiver('calendrier_prophylaxie', $l->id, $maintenant);
            } else {
                DB::table('calendrier_prophylaxie')->where('id', $l->id)->update([
                    'id' => $nouvelId, 'espece' => self::NOUVEAU, 'traitement' => $traitement, 'produit' => $produit,
                    'dose' => $cible[2] ?? $l->dose, 'remanence_jours' => $cible[3] ?? $l->remanence_jours,
                    'updated_at' => $maintenant,
                ]);
            }
            if ($aSoins && $nouvelId !== $l->id) {
                DB::table('soins_calendrier')->where('echeance_prophylaxie_id', $l->id)
                    ->update(['echeance_prophylaxie_id' => $nouvelId, 'serveur_modifie_le' => $maintenant]);
            }
        }
    }

    // --------------------------------------------------------------------- simples

    private function renommerSimplement(string $table, ?string $curseur, string $maintenant): void
    {
        if (! $this->utilisable($table)) {
            return;
        }
        $maj = ['espece' => self::NOUVEAU];
        if ($curseur !== null && Schema::hasColumn($table, $curseur)) {
            $maj[$curseur] = $maintenant;
        }
        // Une cle unique deja prise par la ligne `ovins` (ex. code de bande) : la ligne `bovins` est retiree.
        foreach (DB::table($table)->where('espece', self::ANCIEN)->pluck('id') as $id) {
            try {
                DB::transaction(fn () => DB::table($table)->where('id', $id)->update($maj));
            } catch (\Illuminate\Database\UniqueConstraintViolationException) {
                DB::table($table)->where('id', $id)->delete();
            }
        }
    }

    private function produits(string $maintenant): void
    {
        if (! Schema::hasTable('produits_vendables')) {
            return;
        }
        DB::table('produits_vendables')->where('espece', self::ANCIEN)->update(['espece' => self::NOUVEAU, 'updated_at' => $maintenant]);
        DB::table('produits_vendables')->where('cat', 'Élevage bovin')->update(['cat' => 'Élevage ovin', 'updated_at' => $maintenant]);
    }
};
