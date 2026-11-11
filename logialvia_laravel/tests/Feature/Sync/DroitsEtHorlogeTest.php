<?php

namespace Tests\Feature\Sync;

use App\Models\Client;
use App\Models\DemandeReferentiel;
use App\Models\ModuleActif;
use App\Sync\DemandesReferentiel;
use App\Sync\DroitsPoste;
use App\Sync\GardeHorloge;
use App\Sync\MoteurSynchronisation;
use App\Sync\TableSync;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * `47g_` : le poste connait les DROITS de son compte (reponse de connexion, `me`, tirage) et le
 * serveur refuse avec des CODES STABLES (`droit_insuffisant`, `horloge_en_avance`). Un refus pour
 * droit n'est jamais memorise ; un instant de saisie en avance sur l'horloge du serveur est refuse.
 */
class DroitsEtHorlogeTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        RateLimiter::clear('');
        $this->travel(5)->seconds();
    }

    private function instant(string $decalage = 'now'): string
    {
        return now()->modify($decalage)->format('Y-m-d\TH:i:s.u\Z');
    }

    private function pousser(array $poste, string $table, array $lignes)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => [$table => $lignes],
        ]);
    }

    private function demander(array $poste, array $demandes)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => $demandes,
        ]);
    }

    private function demandeModule(?string $saisi = null, ?string $id = null): array
    {
        return [
            'id' => $id ?? (string) Str::uuid(),
            'type' => 'module_actif',
            'saisi_le' => $saisi ?? $this->instant(),
            'donnees' => ['module_id' => 'ovins', 'is_actif' => true],
        ];
    }

    // ------------------------------------------------------------------ Droits

    public static function comptes(): array
    {
        return [
            'admin' => ['admin', ['module_actif', 'parametres_entreprise', 'produit_vendable', 'intrant', 'bareme_ration', 'taux_ration_poids', 'echeance_prophylaxie', 'compte_comptable']],
            'caissier' => ['caissier', ['produit_vendable']],
            'comptable' => ['comptable', ['compte_comptable']],
            'animalier' => ['animalier', ['bareme_ration', 'taux_ration_poids', 'echeance_prophylaxie']],
        ];
    }

    /** @dataProvider comptes */
    public function test_la_connexion_donne_les_droits_du_compte_sans_aucun_secret(string $role, array $demandes): void
    {
        $utilisateur = $this->compteAvecRole($role, 'compte-'.$role);
        $utilisateur->forceFill(['password' => 'motdepasse-solide-1'])->save();

        $reponse = $this->postJson('/api/auth/login', [
            'identifiant' => 'compte-'.$role,
            'password' => 'motdepasse-solide-1',
            'device_name' => (string) Str::uuid(),
        ])->assertOk();

        $droits = $reponse->json('droits');
        $this->assertSame('compte-'.$role, $droits['compte']);
        $this->assertSame([$role], $droits['roles']);
        $this->assertEqualsCanonicalizing($demandes, $droits['demandes']);
        $this->assertNotEmpty($reponse->json('server_now'));

        // Aucun secret dans la reponse « droits ».
        $json = json_encode($droits);
        $this->assertStringNotContainsString('password', $json);
        $this->assertStringNotContainsString('token', $json);
        $this->assertStringNotContainsString($reponse->json('token'), $json);
    }

    public function test_les_tables_ecrites_sont_celles_que_le_serveur_accepte_pour_chaque_compte(): void
    {
        // La liste annoncee au poste ET le refus du serveur viennent de la MEME source (`peutEcrire`) :
        // pour chaque compte et chaque table de fait, on pousse une ligne invalide ; une table non
        // annoncee est refusee `droit_insuffisant`, une table annoncee juge la ligne (refus ordinaire).
        foreach (['admin', 'caissier', 'comptable', 'animalier'] as $role) {
            $poste = $this->poste($role, 'matrice-'.$role);
            $droits = DroitsPoste::pour($poste['utilisateur']);

            foreach ((new MoteurSynchronisation)->tables() as $table) {
                if ($table->nature() !== TableSync::FAIT) {
                    continue;
                }
                $bilan = $this->pousser($poste, $table->nom(), [['id' => 'pas-un-uuid']])->assertOk()->json($table->nom());
                $refus = $bilan['rejected'][0] ?? null;
                $this->assertNotNull($refus, "$role / {$table->nom()} : une ligne invalide est refusee");

                if (in_array($table->nom(), $droits['tables_ecrites'], true)) {
                    $this->assertArrayNotHasKey('code', $refus, "$role peut ecrire {$table->nom()} : refus ordinaire");
                } else {
                    $this->assertSame('droit_insuffisant', $refus['code'] ?? null, "$role ne peut pas ecrire {$table->nom()}");
                }
            }
        }
    }

    public function test_les_droits_annonces_par_type_de_demande_sont_ceux_que_le_serveur_applique(): void
    {
        foreach (self::comptes() as [$role]) {
            $poste = $this->poste($role, 'types-'.$role);
            $permis = DemandesReferentiel::typesPermis($poste['utilisateur']);

            foreach (array_keys(DemandesReferentiel::DROITS_PAR_TYPE) as $type) {
                $d = ['id' => (string) Str::uuid(), 'type' => $type, 'saisi_le' => $this->instant(), 'donnees' => ['x' => 1]];
                $refus = $this->demander($poste, [$d])->assertOk()->json('rejected.0');
                if (in_array($type, $permis, true)) {
                    $this->assertNotSame('droit_insuffisant', $refus['code'] ?? null, "$role peut proposer $type");
                } else {
                    $this->assertSame('droit_insuffisant', $refus['code'] ?? null, "$role ne peut pas proposer $type");
                }
            }
        }
    }

    public function test_le_tirage_et_me_portent_les_droits_a_jour(): void
    {
        $poste = $this->poste('caissier', 'evolutif');

        $avant = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->assertOk();
        $this->assertSame(['produit_vendable'], $avant->json('droits.demandes'));
        $this->assertNotNull($avant->json('server_now'));

        // Le serveur accorde un droit : le tirage SUIVANT le dit, sans reconnexion.
        $poste['utilisateur']->assignRole('animalier');
        $apres = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->assertOk();
        $this->assertContains('bareme_ration', $apres->json('droits.demandes'));
        $this->assertContains('fiche_journee', $apres->json('droits.tables_ecrites'));

        $me = $this->avecJeton($poste['jeton'])->getJson('/api/auth/me')->assertOk();
        $this->assertContains('fiche_journee', $me->json('droits.tables_ecrites'));
        $this->assertSame('evolutif', $me->json('droits.compte'));
    }

    public function test_une_demande_sans_droit_est_refusee_avec_son_code_et_nest_jamais_memorisee(): void
    {
        $caissier = $this->poste('caissier', 'caisse');
        $admin = $this->poste('admin', 'gerante');
        $d = $this->demandeModule();

        $this->demander($caissier, [$d])->assertOk()
            ->assertJsonPath('rejected.0.code', 'droit_insuffisant')
            ->assertJsonPath('rejected.0.id', $d['id']);
        $this->assertDatabaseCount('demandes_referentiel', 0);
        $this->assertFalse((bool) ModuleActif::query()->where('module_id', 'ovins')->value('is_actif'));

        // La MEME demande (meme UUID), renvoyee par une session qui a le droit : jugee de nouveau, acceptee.
        $this->demander($admin, [$d])->assertOk()->assertJson(['accepted' => [$d['id']], 'rejected' => []]);
        $this->assertTrue((bool) ModuleActif::query()->where('module_id', 'ovins')->value('is_actif'));
        $this->assertSame('acceptee', DemandeReferentiel::query()->find($d['id'])->statut);
    }

    public function test_une_ligne_sans_droit_nest_pas_ecrite_et_le_refus_porte_le_code(): void
    {
        $caissier = $this->poste('caissier', 'caisse');
        $ligne = ['id' => (string) Str::uuid(), 'nom' => 'Exploitant', 'updated_at' => $this->instant()];

        // Le caissier peut ecrire les clients (manage-ventes) ; il ne peut pas ecrire les fiches du jour.
        $this->pousser($caissier, 'clients', [$ligne])->assertOk()->assertJsonPath('clients.accepted.0', $ligne['id']);

        $fiche = ['id' => (string) Str::uuid(), 'updated_at' => $this->instant()];
        $this->pousser($caissier, 'fiche_journee', [$fiche])->assertOk()
            ->assertJsonPath('fiche_journee.rejected.0.code', 'droit_insuffisant')
            ->assertJsonPath('fiche_journee.rejected.0.motif', 'Droit insuffisant pour écrire dans « fiche_journee ».');
    }

    // ----------------------------------------------------------------- Horloge

    public static function decalagesRefuses(): array
    {
        return [
            '+1 h' => ['+1 hour', '1 h'],
            '+2 jours' => ['+2 days', '2 jours'],
            '+2 ans' => ['+2 years', '2 ans'],
            '+6 min' => ['+6 minutes', '6 min'],
        ];
    }

    /** @dataProvider decalagesRefuses */
    public function test_un_instant_de_saisie_en_avance_est_refuse_avec_son_code_et_un_motif_explicite(string $decalage, string $duree): void
    {
        $poste = $this->poste('caissier', 'avance');
        $ligne = ['id' => (string) Str::uuid(), 'nom' => 'Gelé', 'updated_at' => $this->instant($decalage)];

        $refus = $this->pousser($poste, 'clients', [$ligne])->assertOk()->json('clients.rejected.0');

        $this->assertSame('horloge_en_avance', $refus['code']);
        $this->assertStringContainsString("L'horloge de ce poste avance de $duree", $refus['motif']);
        $this->assertStringContainsString("corrigez la date et l'heure du poste", $refus['motif']);
        $this->assertNull(Client::query()->find($ligne['id']), 'rien n\'est ecrit');
    }

    public function test_un_retard_ou_la_tolerance_exacte_sont_acceptes_et_une_seconde_de_plus_est_refusee(): void
    {
        $poste = $this->poste('caissier', 'tolerance');
        $this->freezeTime();

        foreach (['-1 hour', '-2 days', 'now', '+300 seconds'] as $decalage) {
            $ligne = ['id' => (string) Str::uuid(), 'nom' => "T $decalage", 'updated_at' => $this->instant($decalage)];
            $this->pousser($poste, 'clients', [$ligne])->assertOk()->assertJsonPath('clients.accepted.0', $ligne['id']);
        }

        $trop = ['id' => (string) Str::uuid(), 'nom' => 'Trop', 'updated_at' => $this->instant('+301 seconds')];
        $this->pousser($poste, 'clients', [$trop])->assertOk()->assertJsonPath('clients.rejected.0.code', 'horloge_en_avance');
        $this->assertSame(300, GardeHorloge::TOLERANCE_SECONDES);
    }

    public function test_aucune_ligne_nest_gelee_un_poste_en_avance_ne_gagne_rien_et_l_autre_poste_ecrit(): void
    {
        $avance = $this->poste('caissier', 'avance');
        $normal = $this->poste('caissier', 'normal');
        $id = (string) Str::uuid();

        $this->pousser($normal, 'clients', [['id' => $id, 'nom' => 'Version A', 'updated_at' => $this->instant('-1 minute')]])->assertOk();
        $this->pousser($avance, 'clients', [['id' => $id, 'nom' => 'Version gelee', 'updated_at' => $this->instant('+2 years')]])
            ->assertOk()->assertJsonPath('clients.rejected.0.code', 'horloge_en_avance');

        // L'autre poste corrige ensuite : sa saisie, plus recente que la precedente, passe.
        $this->pousser($normal, 'clients', [['id' => $id, 'nom' => 'Version B', 'updated_at' => $this->instant()]])->assertOk();
        $this->assertSame('Version B', Client::query()->find($id)->nom);

        // Apres correction de l'horloge, le poste en avance re-envoie sa saisie (datee de l'heure juste) : acceptee.
        $this->pousser($avance, 'clients', [['id' => $id, 'nom' => 'Version C', 'updated_at' => $this->instant('+1 second')]])
            ->assertOk()->assertJsonPath('clients.accepted.0', $id);
        $this->assertSame('Version C', Client::query()->find($id)->nom);
    }

    public function test_la_garde_couvre_toute_table_pas_seulement_les_lignes_plates(): void
    {
        $admin = $this->poste('admin', 'gerante');

        // Un instant de saisie `horodatage` (journal) et `updated_at` d'une table a absorbeur propre.
        $mouvement = ['id' => (string) Str::uuid(), 'horodatage' => $this->instant('+3 days')];
        $this->pousser($admin, 'mouvements_intrant', [$mouvement])->assertOk()
            ->assertJsonPath('mouvements_intrant.rejected.0.code', 'horloge_en_avance');

        $vente = ['id' => (string) Str::uuid(), 'updated_at' => $this->instant('+3 days')];
        $this->pousser($admin, 'ventes', [$vente])->assertOk()
            ->assertJsonPath('ventes.rejected.0.code', 'horloge_en_avance');

        $facture = ['id' => (string) Str::uuid(), 'updated_at' => $this->instant('+3 days')];
        $this->pousser($admin, 'factures', [$facture])->assertOk()
            ->assertJsonPath('factures.rejected.0.code', 'horloge_en_avance');

        $fiche = ['id' => (string) Str::uuid(), 'updated_at' => $this->instant('+3 days')];
        $this->pousser($admin, 'fiche_journee', [$fiche])->assertOk()
            ->assertJsonPath('fiche_journee.rejected.0.code', 'horloge_en_avance');

        $ecriture = ['id' => (string) Str::uuid(), 'updated_at' => $this->instant('+3 days')];
        $this->pousser($admin, 'ecriture_comptable', [$ecriture])->assertOk()
            ->assertJsonPath('ecriture_comptable.rejected.0.code', 'horloge_en_avance');

        $devis = ['id' => (string) Str::uuid(), 'updated_at' => $this->instant('+3 days')];
        $this->pousser($admin, 'devis', [$devis])->assertOk()
            ->assertJsonPath('devis.rejected.0.code', 'horloge_en_avance');
    }

    public function test_une_demande_datee_dans_le_futur_est_refusee_et_nest_pas_memorisee(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $d = $this->demandeModule($this->instant('+2 days'));

        $refus = $this->demander($admin, [$d])->assertOk()->json('rejected.0');

        $this->assertSame('horloge_en_avance', $refus['code']);
        $this->assertStringContainsString('avance de 2 jours', $refus['motif']);
        $this->assertDatabaseCount('demandes_referentiel', 0);

        // La meme demande, re-datee apres correction de l'horloge, est acceptee (meme UUID).
        $juste = $d;
        $juste['saisi_le'] = $this->instant();
        $this->demander($admin, [$juste])->assertOk()->assertJson(['accepted' => [$d['id']]]);
    }

    public function test_la_duree_est_dite_en_clair(): void
    {
        $this->assertSame('2 ans', GardeHorloge::duree(2 * 365 * 86400 + 5));
        $this->assertSame('1 an', GardeHorloge::duree(365 * 86400));
        $this->assertSame('2 jours', GardeHorloge::duree(2 * 86400));
        $this->assertSame('1 h', GardeHorloge::duree(3600));
        $this->assertSame('1 h 05', GardeHorloge::duree(3900));
        $this->assertSame('6 min', GardeHorloge::duree(360));
        $this->assertSame('42 s', GardeHorloge::duree(42));
    }

    public function test_un_ecran_du_web_ecrit_meme_apres_une_ligne_deja_gelee(): void
    {
        // Une ligne d'avant la garde peut etre datee loin dans le futur : le web (poste nul) la remplace
        // par une saisie datee APRES elle (il n'est pas soumis a la garde, qui vise l'horloge des postes).
        $table = new \App\Sync\Tables\ClientsTable;
        $id = (string) Str::uuid();
        $gele = now()->addYear();
        $this->assertNull($table->absorber('00000000-0000-0000-0000-000000000000', ['id' => $id, 'nom' => 'Gelé', 'updated_at' => $gele->format('Y-m-d\TH:i:s.u\Z')]));
        $this->assertNull($table->absorber('00000000-0000-0000-0000-000000000000', ['id' => $id, 'nom' => 'Web', 'updated_at' => $gele->addSecond()->format('Y-m-d\TH:i:s.u\Z')]));
        $this->assertSame('Web', Client::query()->find($id)->nom);

        // Un poste, lui, est jugé : le meme appel direct avec un autre identifiant est refuse.
        $autre = new \App\Sync\Tables\ClientsTable;
        $motif = $autre->absorber((string) Str::uuid(), ['id' => (string) Str::uuid(), 'nom' => 'X', 'updated_at' => $gele->format('Y-m-d\TH:i:s.u\Z')]);
        $this->assertStringContainsString("L'horloge de ce poste avance de 1 an", (string) $motif);
        $this->assertSame('horloge_en_avance', $autre->codeRefus());
    }
}
