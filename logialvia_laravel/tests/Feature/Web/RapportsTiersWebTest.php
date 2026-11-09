<?php

namespace Tests\Feature\Web;

use App\Livewire\Rapports;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\Concerns\JeuRapports;
use Tests\TestCase;

/**
 * Rapports & Etats, onglets « Créances Clients » et « Dettes Fournisseurs » (Dart : `_creances`, `_dettes`,
 * `CreanceClient`, `DetteFournisseur`). « Maintenant » = 18/11/2026 10:00 (Porto-Novo) : le retard se compte en JOURS
 * CIVILS locaux entre l'echeance et aujourd'hui, jamais en heures, jamais negatif.
 */
class RapportsTiersWebTest extends TestCase
{
    use JeuRapports, RefreshDatabase;

    private const AMINA = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

    private const KOFFI = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerRapports();
    }

    private function rapport(string $onglet): \Livewire\Features\SupportTesting\Testable
    {
        $this->actingAs($this->utilisateurRapports('comptable', 'paul'));

        return Livewire::test(Rapports::class)->set('onglet', $onglet);
    }

    private function poserCreances(): void
    {
        $this->client('Amina Bako', self::AMINA);
        $this->client('Koffi Dossou', self::KOFFI);

        // En retard de 8 jours (echeance 10/11), reste 30 000.
        $this->vente(['reference' => 'V-C1', 'client' => 'Amina Bako', 'client_id' => self::AMINA, 'status' => 'Avance',
            'date_vente' => $this->loc('2026-11-02 09:00:00'), 'total' => 50000, 'paye' => 20000, 'echeance' => $this->loc('2026-11-10 12:00:00')]);
        // Echeance AUJOURD'HUI a 00:30 : zero jour de retard -> « À Échoir ».
        $this->vente(['reference' => 'V-C2', 'client' => 'Amina Bako', 'client_id' => self::AMINA, 'status' => 'Avance',
            'date_vente' => $this->loc('2026-11-03 09:00:00'), 'total' => 40000, 'paye' => 0, 'echeance' => $this->loc('2026-11-18 00:30:00')]);
        // Echeance HIER a 23:59 : un jour de retard ; client retrouve par son NOM (pas de client_id).
        $this->vente(['reference' => 'V-C3', 'client' => 'Koffi Dossou', 'status' => 'Avance',
            'date_vente' => $this->loc('2026-11-04 09:00:00'), 'total' => 100000, 'paye' => 60000, 'echeance' => $this->loc('2026-11-17 23:59:00')]);
        // Soldee : exclue.
        $this->vente(['reference' => 'V-C4', 'client' => 'Koffi Dossou', 'status' => 'Payée', 'total' => 25000, 'paye' => 25000]);
        // Client de passage (absent des clients), sans echeance : « Sans échéance », code « — ».
        $this->vente(['reference' => 'V-C5', 'client' => 'Passage', 'status' => 'Avance',
            'date_vente' => $this->loc('2026-11-05 09:00:00'), 'total' => 10000, 'paye' => 0]);
        // Annulee : n'est plus une creance (son encours est contrepasse).
        $this->vente(['reference' => 'V-C6', 'client' => 'Amina Bako', 'client_id' => self::AMINA, 'status' => 'Annulée',
            'date_vente' => $this->loc('2026-11-06 09:00:00'), 'total' => 70000, 'paye' => 0, 'echeance' => $this->loc('2026-10-01 12:00:00')]);
    }

    public function test_creances_chiffres_exacts_du_dart(): void
    {
        $this->poserCreances();
        $c = $this->rapport('creances');

        $this->assertSame('120 000 FCFA', $this->nombre($c, 'creances-en-cours'));       // 30 000 + 40 000 + 40 000 + 10 000
        $this->assertSame('70 000 FCFA', $this->nombre($c, 'creances-en-retard'));       // V-C1 (8 j) + V-C3 (1 j)
        $this->assertSame('3', $this->nombre($c, 'clients-debiteurs'));                  // Amina (2 factures), Koffi, Passage
        $this->assertSame('40,0 %', $this->nombre($c, 'taux-recouvrement'));             // 80 000 / 200 000

        // Triees par date de vente ; colonnes du Dart.
        $this->assertSame([
            ['CLI-AAAAAAAA', 'Amina Bako', 'V-C1', '02/11/2026', '10/11/2026', '50 000', '20 000', '30 000', '8j', 'En Retard', "Saisir l'encaissement"],
            ['CLI-AAAAAAAA', 'Amina Bako', 'V-C2', '03/11/2026', '18/11/2026', '40 000', '—', '40 000', '—', 'À Échoir', "Saisir l'encaissement"],
            ['CLI-BBBBBBBB', 'Koffi Dossou', 'V-C3', '04/11/2026', '17/11/2026', '100 000', '60 000', '40 000', '1j', 'En Retard', "Saisir l'encaissement"],
            ['—', 'Passage', 'V-C5', '05/11/2026', '—', '10 000', '—', '10 000', '—', 'Sans échéance', "Saisir l'encaissement"],
        ], $this->lignes($c, "//table[@data-table='creances']/tbody/tr"));
    }

    public function test_a_date_egale_les_creances_sont_triees_par_reference_et_le_code_suit_l_identifiant_du_client(): void
    {
        $this->client('Amina Bako', self::AMINA);
        // Le client a ete renomme : la vente garde l'ancien nom, le code vient de l'IDENTIFIANT.
        $this->vente(['reference' => 'B-2', 'client' => 'Ancien Nom', 'client_id' => self::AMINA, 'status' => 'Avance', 'date_vente' => $this->loc('2026-11-02 09:00:00'), 'total' => 10, 'paye' => 0]);
        $this->vente(['reference' => 'A-1', 'client' => 'Ancien Nom', 'client_id' => self::AMINA, 'status' => 'Avance', 'date_vente' => $this->loc('2026-11-02 09:00:00'), 'total' => 10, 'paye' => 0]);
        $this->vente(['reference' => 'A-0', 'client' => 'Ancien Nom', 'client_id' => self::AMINA, 'status' => 'Avance', 'date_vente' => $this->loc('2026-11-03 09:00:00'), 'total' => 10, 'paye' => 0]);
        $c = $this->rapport('creances');

        $this->assertSame(['A-1', 'B-2', 'A-0'], $this->textes($c, "//table[@data-table='creances']/tbody/tr/td[3]"));
        $this->assertSame(['CLI-AAAAAAAA', 'CLI-AAAAAAAA', 'CLI-AAAAAAAA'], $this->textes($c, "//table[@data-table='creances']/tbody/tr/td[@data-code]"));
    }

    public function test_le_filtre_de_statut_des_creances_ne_propose_que_en_retard_et_a_echoir(): void
    {
        $this->poserCreances();
        $c = $this->rapport('creances')->set('filtreStatutCreance', 'En Retard');

        $this->assertSame(['V-C1', 'V-C3'], $this->textes($c, "//table[@data-table='creances']/tbody/tr/td[3]"));
        // Les KPI decrivent TOUTES les creances, pas le filtre.
        $this->assertSame('120 000 FCFA', $this->nombre($c, 'creances-en-cours'));

        // « À Échoir » ne reprend PAS « Sans échéance » : aucune date fixee n'est pas une date a venir.
        $c->set('filtreStatutCreance', 'À Échoir');
        $this->assertSame(['V-C2'], $this->textes($c, "//table[@data-table='creances']/tbody/tr/td[3]"));

        $c->set('filtreStatutCreance', 'Sans échéance');   // pas une option du poste : « tous »
        $this->assertCount(4, $this->lignes($c, "//table[@data-table='creances']/tbody/tr"));
    }

    public function test_creances_vide_et_filtre_sans_resultat_ont_chacun_leur_message(): void
    {
        $c = $this->rapport('creances');
        $c->assertSeeHtml('data-vide="creances"')->assertSee('Aucune créance en cours : toutes les ventes sont intégralement réglées.');
        $this->assertSame('—', $this->nombre($c, 'taux-recouvrement'));   // aucun montant initial : pas de division
        $this->assertSame('0', $this->nombre($c, 'clients-debiteurs'));

        $this->vente(['reference' => 'V-X', 'status' => 'Avance', 'total' => 100, 'paye' => 0, 'echeance' => $this->loc('2026-11-30 12:00:00')]);
        $c = $this->rapport('creances')->set('filtreStatutCreance', 'En Retard');
        $c->assertSee('Aucune créance ne correspond à ce statut.')->assertDontSee('toutes les ventes sont intégralement réglées');
    }

    public function test_une_creance_sans_echeance_n_est_jamais_en_retard_meme_tres_ancienne(): void
    {
        $this->vente(['reference' => 'V-VIEILLE', 'status' => 'Avance', 'date_vente' => $this->loc('2026-01-02 09:00:00'), 'total' => 500, 'paye' => 0]);
        $c = $this->rapport('creances');

        $this->assertSame('0 FCFA', $this->nombre($c, 'creances-en-retard'));
        $this->assertSame(['—'], $this->textes($c, "//tr[@data-facture='V-VIEILLE']/td[@data-retard]"));
    }

    public function test_le_lien_encaissement_exige_de_voir_les_ventes(): void
    {
        $this->poserCreances();
        $c = $this->rapport('creances');
        $c->assertSeeHtml('data-action="encaissement"')->assertSeeHtml('href="/clients"');

        // Un compte qui ne voit que les rapports ne recoit pas un lien vers un ecran qui lui est ferme.
        $lecteur = \App\Models\User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-rapports');
        $this->actingAs($lecteur);
        Livewire::test(Rapports::class)->set('onglet', 'creances')->assertDontSeeHtml('data-action="encaissement"')->assertSee('V-C1');
    }

    public function test_creances_les_deux_vues_et_la_note_d_echeance(): void
    {
        $this->poserCreances();
        $c = $this->rapport('creances');

        $c->assertSeeHtml('hidden overflow-x-auto sm:block')->assertSeeHtml('data-vue="cartes"')->assertSeeHtml('data-note="echeance"');
        $this->assertCount(4, $this->textes($c, "//*[@data-vue='cartes']/article"));
    }

    // ==================================================================== Dettes

    private function poserDettes(): void
    {
        $f1 = $this->fournisseur('Provenderie du Nord', 'f1f1f1f1-1111-4111-8111-f1f1f1f1f1f1');
        $f2 = $this->fournisseur('Ferme Sud', 'f2f2f2f2-2222-4222-8222-f2f2f2f2f2f2');

        // Urgente : 6 jours de retard (echeance 12/11).
        $this->achat($f1, ['reference' => 'A1', 'date_achat' => $this->loc('2026-11-02 09:00:00'), 'total' => 80000, 'paye' => 30000, 'echeance' => $this->loc('2026-11-12 12:00:00')]);
        // Normale : echeance a venir.
        $this->achat($f1, ['reference' => 'A2', 'date_achat' => $this->loc('2026-11-03 09:00:00'), 'total' => 20000, 'paye' => 0, 'echeance' => $this->loc('2026-11-30 12:00:00')]);
        // Sans echeance.
        $this->achat($f2, ['reference' => 'A3', 'date_achat' => $this->loc('2026-11-04 09:00:00'), 'total' => 60000, 'paye' => 10000]);
        // Soldee : exclue.
        $this->achat($f2, ['reference' => 'A4', 'total' => 15000, 'paye' => 15000]);
        // Annulee (statut reel « Annulé ») : n'est plus une dette.
        $this->achat($f2, ['reference' => 'A5', 'statut' => 'Annulé', 'total' => 90000, 'paye' => 0, 'echeance' => $this->loc('2026-10-01 12:00:00')]);
    }

    public function test_dettes_chiffres_exacts_du_dart(): void
    {
        $this->poserDettes();
        $c = $this->rapport('dettes');

        $this->assertSame('120 000 FCFA', $this->nombre($c, 'total-dettes'));            // 50 000 + 20 000 + 50 000
        $this->assertSame('50 000 FCFA', $this->nombre($c, 'dettes-urgentes'));          // A1 seule
        $this->assertSame('2', $this->nombre($c, 'fournisseurs-crediteurs'));

        $this->assertSame([
            ['FRN-F1F1F1F1', 'Provenderie du Nord', 'A1', '02/11/2026', '12/11/2026', '80 000', '30 000', '50 000', 'Urgent'],
            ['FRN-F1F1F1F1', 'Provenderie du Nord', 'A2', '03/11/2026', '30/11/2026', '20 000', '—', '20 000', 'Normal'],
            ['FRN-F2F2F2F2', 'Ferme Sud', 'A3', '04/11/2026', '—', '60 000', '10 000', '50 000', 'Sans échéance'],
        ], $this->lignes($c, "//table[@data-table='dettes']/tbody/tr"));
    }

    public function test_les_achats_annules_sont_exclus_des_dettes(): void
    {
        $this->poserDettes();
        $c = $this->rapport('dettes');

        $this->assertNotContains('A5', $this->textes($c, "//table[@data-table='dettes']/tbody/tr/td[3]"));
        $this->assertSame('120 000 FCFA', $this->nombre($c, 'total-dettes'));   // 90 000 de A5 ne s'y ajoutent pas
    }

    public function test_filtre_de_statut_des_dettes(): void
    {
        $this->poserDettes();
        $c = $this->rapport('dettes')->set('filtreStatutDette', 'Urgent');
        $this->assertSame(['A1'], $this->textes($c, "//table[@data-table='dettes']/tbody/tr/td[3]"));
        $this->assertSame('120 000 FCFA', $this->nombre($c, 'total-dettes'));

        $c->set('filtreStatutDette', 'Normal');
        $this->assertSame(['A2'], $this->textes($c, "//table[@data-table='dettes']/tbody/tr/td[3]"));   // pas « Sans échéance »

        $c->call('reinitialiserFiltres');
        $this->assertCount(3, $this->lignes($c, "//table[@data-table='dettes']/tbody/tr"));
    }

    public function test_dettes_vides_et_filtre_sans_resultat(): void
    {
        $c = $this->rapport('dettes');
        $c->assertSeeHtml('data-vide="dettes"')->assertSee('Aucune dette fournisseur : tous les achats sont intégralement réglés.');

        $f = $this->fournisseur('F');
        $this->achat($f, ['reference' => 'A9', 'total' => 100, 'paye' => 0, 'echeance' => $this->loc('2026-11-30 12:00:00')]);
        $c = $this->rapport('dettes')->set('filtreStatutDette', 'Urgent');
        $c->assertSee('Aucune dette ne correspond à ce statut.');
    }

    public function test_une_dette_dont_le_fournisseur_est_supprime_garde_son_nom(): void
    {
        // Suppression douce : la dette existe toujours, le fournisseur ne disparait pas du rapport.
        $f = $this->fournisseur('Ancien Fournisseur');
        $f->forceFill(['supprime_le' => now()])->save();
        $this->achat($f, ['reference' => 'A-OLD', 'total' => 1000, 'paye' => 0]);

        $this->assertSame(['Ancien Fournisseur'], $this->textes($this->rapport('dettes'), "//table[@data-table='dettes']/tbody/tr/td[2]"));
    }

    public function test_dettes_les_deux_vues(): void
    {
        $this->poserDettes();
        $c = $this->rapport('dettes');
        $c->assertSeeHtml('hidden overflow-x-auto sm:block')->assertSeeHtml('data-vue="cartes"');
        $this->assertCount(3, $this->textes($c, "//*[@data-vue='cartes']/article"));
    }
}
