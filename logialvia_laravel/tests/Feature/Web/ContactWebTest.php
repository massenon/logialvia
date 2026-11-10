<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\Contact;
use App\Livewire\CorbeilleWeb;
use App\Models\AuditLog;
use App\Models\DemandeReferentiel;
use App\Models\MessageEditeur;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Contactez l'Éditeur » : coordonnees, formulaire, messages synchronises ; aucun e-mail (declare). */
class ContactWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
    }

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private function composant(?User $u = null)
    {
        return Livewire::actingAs($u ?? $this->utilisateur('caissier', 'amina'))->test(Contact::class);
    }

    private function message(array $s = []): MessageEditeur
    {
        $m = (new MessageEditeur)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'horodatage' => '2026-11-01 09:00:00', 'type' => 'question',
            'sujet' => 'Une question', 'message' => 'Comment faire ?', 'etapes' => null, 'auteur' => 'Awa (awa) — Comptable', 'statut' => 'En attente',
            'updated_at' => '2026-11-01 09:00:00', 'serveur_modifie_le' => '2026-11-01 09:00:00', 'supprime_le' => null,
        ], $s));
        $m->save();

        return $m;
    }

    // ------------------------------------------------------------------- Acces

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/contact')->assertRedirect(route('login'));
    }

    public function test_tout_compte_connecte_ouvre_la_page(): void
    {
        foreach (['admin', 'comptable', 'caissier', 'animalier'] as $i => $role) {
            $this->actingAs($this->utilisateur($role, "u$i"))->get('/contact')
                ->assertOk()->assertSee('Contactez l\'Éditeur', false)->assertDontSee('arrive bientôt');
        }
    }

    public function test_les_coordonnees_de_l_editeur_sont_la(): void
    {
        $this->composant()
            ->assertSee('rarhodes06@gmail.com')->assertSeeHtml('href="mailto:rarhodes06@gmail.com"')
            ->assertSee('FAGUEZ SARL')->assertSee('Dr MASSENON Rhodes')
            ->assertSee('+229 01 51 33 50 40')->assertSee('+229 01 97 31 24 37')
            ->assertSee('contact@massenonrhodes.com');
    }

    public function test_le_formulaire_a_deux_onglets_et_l_ecart_aucun_email_est_declare(): void
    {
        $page = $this->composant()
            ->assertSee('Poser une question générale')->assertSee('Objet *')->assertDontSee('Module concerné *')
            ->assertSeeHtml('data-ecart="aucun-envoi"')->assertSee('n\'envoie aucun e-mail', false)->assertDontSee('Message envoyé')
            ->call('choisirType', 'bug')->assertSee('Signaler un problème technique')->assertSee('Module concerné *')
            ->assertSee('Étapes pour reproduire')->assertDontSee('Objet *')
            ->call('choisirType', 'nimporte')->assertSet('type', 'question');
        $this->assertStringContainsString('v1.0.0', $page->html());
    }

    // ------------------------------------------------------------------ Envoi

    public function test_enregistrer_une_question_ecrit_un_fait_du_poste_web_et_ne_promet_aucun_envoi(): void
    {
        $u = $this->utilisateur('comptable', 'awa');

        $this->composant($u)->set('objet', ' Question compta ')->set('message', ' Comment clôturer ? ')->call('enregistrer')
            ->assertSet('erreur', null)->assertSet('objet', '')->assertSet('message', '')
            ->assertSee('Aucun e-mail n\'est envoyé')->assertSeeHtml('data-texte-a-copier')
            ->assertSee('De : Awa (awa) — Comptable')->assertSee('Objet : Question compta');

        $m = MessageEditeur::query()->firstOrFail();
        $this->assertSame('question', $m->type);
        $this->assertSame('Question compta', $m->sujet);
        $this->assertSame('Comment clôturer ?', $m->message);
        $this->assertSame('En attente', $m->statut);
        $this->assertSame('Awa (awa) — Comptable', $m->auteur);
        $this->assertSame(Catalogue::POSTE_WEB, $m->device_id);
        $this->assertNull($m->supprime_le);
        $this->assertNull($m->etapes);
        $this->assertSame(0, DemandeReferentiel::query()->count());
        $audit = AuditLog::query()->where('action', 'message_editeur.cree')->firstOrFail();
        $this->assertSame(['id' => $m->id, 'type' => 'question'], $audit->detail);
    }

    public function test_enregistrer_un_probleme_garde_le_module_et_les_etapes(): void
    {
        $this->composant()->call('choisirType', 'bug')->set('module', 'Comptabilité')->set('message', 'Le bilan plante')
            ->set('etapes', "1. Ouvrir\n2. Cliquer")->call('enregistrer')->assertSet('erreur', null)
            ->assertSee('Rapport enregistré')->assertSee('Signalement de problème')->assertSee('Module concerné : Comptabilité')
            ->assertSee('Étapes pour reproduire');

        $m = MessageEditeur::query()->firstOrFail();
        $this->assertSame('bug', $m->type);
        $this->assertSame('Comptabilité', $m->sujet);
        $this->assertSame("1. Ouvrir\n2. Cliquer", $m->etapes);
    }

    public function test_les_etapes_d_une_question_ne_sont_jamais_gardees(): void
    {
        $this->composant()->set('etapes', 'cache')->set('objet', 'Obj')->set('message', 'Msg')->call('enregistrer');
        $this->assertNull(MessageEditeur::query()->firstOrFail()->etapes);
    }

    /** @dataProvider messagesRefuses */
    public function test_chaque_regle_de_validation_a_son_message(string $type, array $champs, string $erreur): void
    {
        $c = $this->composant()->call('choisirType', $type);
        foreach ($champs as $k => $v) {
            $c->set($k, $v);
        }
        $c->call('enregistrer')->assertSet('erreur', $erreur);
        $this->assertSame(0, MessageEditeur::query()->count());
        $this->assertSame(0, AuditLog::query()->where('action', 'message_editeur.cree')->count());
    }

    public static function messagesRefuses(): array
    {
        return [
            'objet vide' => ['question', ['objet' => '  ', 'message' => 'x'], 'L\'objet est obligatoire.'],
            'message vide' => ['question', ['objet' => 'Obj', 'message' => '   '], 'Le message est obligatoire.'],
            'module absent' => ['bug', ['module' => '', 'message' => 'x'], 'Le module concerné est obligatoire.'],
            'module inconnu' => ['bug', ['module' => 'Secret', 'message' => 'x'], 'Le module concerné est inconnu.'],
            'description vide' => ['bug', ['module' => 'Autre', 'message' => ''], 'Le message est obligatoire.'],
        ];
    }

    // --------------------------------------------------------------- Registre

    public function test_le_registre_montre_les_messages_du_poste_et_du_web_sans_les_supprimes(): void
    {
        $this->message(['sujet' => 'Du poste', 'horodatage' => '2026-11-01 09:00:00']);
        $this->message(['sujet' => 'Plus recent', 'horodatage' => '2026-11-02 09:00:00', 'statut' => 'Transmis']);
        $this->message(['sujet' => 'Efface', 'supprime_le' => '2026-11-03 09:00:00']);

        $this->composant()->assertSee('Messages enregistrés (2)')->assertSeeInOrder(['Plus recent', 'Du poste'])
            ->assertDontSee('Efface')->assertSee('Transmis')->assertSee('01/11/2026 10:00');
    }

    public function test_voir_le_texte_a_copier(): void
    {
        $m = $this->message(['type' => 'bug', 'sujet' => 'Santé Animale', 'etapes' => 'Aller dans soins']);

        $this->composant()->call('montrerTexte', $m->id)->assertSeeHtml('data-texte-a-copier')
            ->assertSee('LogiALVIA v1.0.0 — Signalement de problème')->assertSee('De : Awa (awa) — Comptable')
            ->assertSee('Module concerné : Santé Animale')->assertSee('Étapes pour reproduire :')
            ->call('montrerTexte', (string) Str::uuid())->assertDontSeeHtml('data-texte-a-copier');
    }

    public function test_marquer_transmis_modifie_le_message_et_fait_avancer_le_curseur(): void
    {
        $m = $this->message();

        $this->composant()->call('marquerTransmis', $m->id)->assertSet('erreur', null)->assertSee('Message marqué comme transmis.')
            ->assertDontSee('Marquer comme transmis');

        $m->refresh();
        $this->assertSame('Transmis', $m->statut);
        $this->assertSame('Une question', $m->sujet);
        $this->assertSame(Catalogue::POSTE_WEB, $m->device_id);
        $this->assertTrue($m->serveur_modifie_le->greaterThan(\Carbon\Carbon::parse('2026-11-01 09:00:00')), 'redescend vers les postes');
        $this->assertNotNull(AuditLog::query()->where('action', 'message_editeur.transmis')->first());
    }

    public function test_marquer_transmis_un_message_inconnu_est_refuse(): void
    {
        $c = $this->composant();
        $c->call('marquerTransmis', (string) Str::uuid())->assertSet('erreur', 'Ce message n\'a pas pu être marqué comme transmis.');
        $supprime = $this->message(['supprime_le' => '2026-11-03 09:00:00']);
        $c->call('marquerTransmis', $supprime->id)->assertSet('erreur', 'Ce message n\'a pas pu être marqué comme transmis.');
        $this->assertSame('En attente', $supprime->fresh()->statut);
    }

    public function test_supprimer_se_confirme_pose_une_pierre_tombale_et_reste_restaurable(): void
    {
        $m = $this->message(['sujet' => 'A effacer']);
        $c = $this->composant()->call('demanderSuppression', $m->id)->assertSee('Supprimer ce message ?')->assertSee('« A effacer »');
        $this->assertNull($m->fresh()->supprime_le, 'rien n\'est supprime avant la confirmation');
        $c->call('annuler')->assertSet('messageAConfirmer', null)->assertDontSee('Supprimer ce message ?');
        $c->call('demanderSuppression', $m->id)->call('confirmerSuppression')->assertSet('erreur', null)->assertSee('Message supprimé')
            ->assertSee('Messages enregistrés (0)');

        $this->assertNotNull($m->fresh()->supprime_le, 'pierre tombale, jamais d\'effacement');
        $this->assertNotNull(AuditLog::query()->where('action', 'message_editeur.supprime')->first());

        // Restauration depuis la Corbeille par l'administrateur.
        Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(CorbeilleWeb::class)->assertSee('A effacer')->assertSee('Message à l\'éditeur')
            ->call('restaurer', 'messages', $m->id)->assertSet('erreur', null);
        $this->assertNull($m->fresh()->supprime_le);
    }

    public function test_confirmer_sans_demande_ou_sur_un_message_deja_supprime_ne_fait_rien(): void
    {
        $m = $this->message(['supprime_le' => '2026-11-03 09:00:00']);
        $this->composant()->call('confirmerSuppression')->assertSet('erreur', 'Ce message n\'a pas pu être supprimé.')
            ->call('demanderSuppression', $m->id)->assertSet('messageAConfirmer', null);
    }

    // ------------------------------------------------------------------ Droits

    public function test_toutes_les_methodes_exigent_un_compte_connecte(): void
    {
        $m = $this->message();
        $u = $this->utilisateur('caissier', 'amina');
        $appels = [['choisirType', ['bug']], ['enregistrer', []], ['montrerTexte', [$m->id]], ['marquerTransmis', [$m->id]],
            ['demanderSuppression', [$m->id]], ['annuler', []], ['confirmerSuppression', []]];

        foreach ($appels as [$methode, $args]) {
            $c = Livewire::actingAs($u)->test(Contact::class);
            \Illuminate\Support\Facades\Auth::logout(); // session perdue en cours de page
            $c->call($methode, ...$args)->assertForbidden();
        }
        $this->assertSame('En attente', $m->fresh()->statut);
        $this->assertNull($m->fresh()->supprime_le);
        $this->assertSame(1, MessageEditeur::query()->count());
    }

    public function test_aucun_message_n_est_attribue_a_un_autre_compte(): void
    {
        $this->composant($this->utilisateur('animalier', 'ali'))->set('objet', 'X')->set('message', 'Y')->call('enregistrer');
        $this->assertSame('Ali (ali) — Agent d\'Élevage', MessageEditeur::query()->firstOrFail()->auteur);
    }
}
