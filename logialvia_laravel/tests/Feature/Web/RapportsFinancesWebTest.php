<?php

namespace Tests\Feature\Web;

use App\Livewire\Rapports;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\Concerns\JeuRapports;
use Tests\TestCase;

/**
 * Rapports & Etats, onglets « Recettes et Dépenses » et « État de Trésorerie » : chiffres calcules comme le Dart
 * (`rapports_repository_drift.dart`, `rapports_view_model.dart`) sur un JEU CONSTRUIT A LA MAIN, valeurs exactes
 * ecrites a l'avance (jamais relues depuis le code teste).
 *
 * Jeu (heure locale, « maintenant » = 18/11/2026 10:00, periode par defaut du 01/11 au 18/11) :
 *   avant la periode : 531 D 20 000 (2025), 512 D 50 000 (sept.), 531 D 100 000 + 531 D 30 000 / 701 C 30 000 (31/10 23:59:59)
 *   dans la periode  : voir `poserLeJeu()`.
 *   apres            : 19/11 00:00:00, 531 D 99 999 / 701 C 99 999.
 */
class RapportsFinancesWebTest extends TestCase
{
    use JeuRapports, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerRapports();
        $this->compte('6011', 'Charge test', '6');
        $this->compte('7011', 'Produit test', '7');
    }

    private function poserLeJeu(): void
    {
        // Avant la periode.
        $this->piece('2025-12-20 10:00:00', [['531', 20000, 0], ['101', 0, 20000]], 'OD-2025');
        $this->piece('2026-09-15 10:00:00', [['512', 50000, 0], ['101', 0, 50000]], 'OD-0915');
        $this->piece('2026-10-31 23:59:59', [['531', 100000, 0], ['101', 0, 100000]], 'OD-1031');
        $this->piece('2026-10-31 23:59:59', [['531', 30000, 0], ['701', 0, 30000]], 'V-1031');

        // Dans la periode.
        $this->piece('2026-11-01 00:00:00', [['531', 120000, 0], ['701', 0, 120000]], 'V-P1-2026-001', ['vente_ref' => 'V-P1-2026-001', 'journal_code' => 'VT']);
        $this->piece('2026-11-05 09:00:00', [['531', 30000, 0], ['411', 50000, 0], ['707', 0, 80000]], 'V-P1-2026-002', ['vente_ref' => 'V-P1-2026-002', 'journal_code' => 'VT']);
        $this->piece('2026-11-05 14:00:00', [['601', 40000, 0], ['531', 0, 10000], ['401', 0, 30000]], 'ACH-P1-2026-001', ['achat_ref' => 'ACH-P1-2026-001', 'journal_code' => 'AC']);
        $this->piece('2026-11-06 11:00:00', [['701', 20000, 0], ['531', 0, 20000]], 'ANN-V-001', ['vente_ref' => 'V-P1-2026-001']);
        $this->piece('2026-11-07 10:00:00', [['531', 1000, 0], ['401', 0, 1000]], 'REM-1', ['achat_ref' => 'ACH-P1-2026-001']);

        // Deux pieces du MEME instant : identifiants adverses (la ligne creditee et la piece saisie la premiere ont les plus petits UUID).
        $this->piece('2026-11-08 10:00:00', [
            ['531', 0, 7000, '00000000-0000-4000-8000-000000000001'],
            ['512', 7000, 0, 'ffffffff-ffff-4fff-8fff-ffffffffffff'],
        ], 'OD-T9', ['id' => 'ffffffff-ffff-4fff-8fff-fffffffffff0'], '2026-11-08 10:00:00.100');
        $this->piece('2026-11-08 10:00:00', [
            ['531', 500, 0, '00000000-0000-4000-8000-000000000000'],
            ['101', 0, 500],
        ], 'OD-T2', ['id' => '00000000-0000-4000-8000-0000000000f0'], '2026-11-08 10:00:00.200');

        $this->piece('2026-11-10 10:00:00', [['624', 15000, 0], ['512', 0, 15000]], 'DEP-P1-2026-0001');
        // Saisie ANTERIEURE a toutes les autres pieces : seule la DATE (12/11) la place apres celle du 10/11.
        $this->piece('2026-11-12 10:00:00', [['6011', 5000, 0], ['531', 0, 5000]], 'DEP-P1-2026-0002', [], '2026-10-01 10:00:00');
        $this->piece('2026-11-18 23:59:59', [['531', 2000, 0], ['7011', 0, 2000]], null);

        // Apres la periode.
        $this->piece('2026-11-19 00:00:00', [['531', 99999, 0], ['701', 0, 99999]], 'V-1119');
    }

    private function rapport(string $onglet = 'recettes'): \Livewire\Features\SupportTesting\Testable
    {
        $this->actingAs($this->utilisateurRapports('comptable', 'paul'));

        return Livewire::test(Rapports::class)->set('onglet', $onglet);
    }

    // ============================================================ Recettes et Dépenses

    public function test_recettes_et_depenses_donnent_les_chiffres_du_dart(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport();

        $this->assertSame('182 000 FCFA', $this->nombre($c, 'total-recettes'));
        $this->assertSame('60 000 FCFA', $this->nombre($c, 'total-depenses'));
        $this->assertSame('122 000 FCFA', $this->nombre($c, 'resultat-net'));
        $this->assertSame('67,0 %', $this->nombre($c, 'taux-marge'));   // 122 000 / 182 000 = 67,03 %

        // Une ligne PAR compte de gestion, triees comme du TEXTE (601 < 6011 < 624 < 701 < 7011 < 707), classes 6 et 7 seules.
        $this->assertSame([
            ['Novembre 2026', 'ACH-P1-2026-001', '601 - Achats de Matières (Intrants Provende)', 'Aviculture', '—', '40 000', '-40 000'],
            ['Novembre 2026', 'DEP-P1-2026-0002', '6011 - Charge test', 'Aviculture', '—', '5 000', '-45 000'],
            ['Novembre 2026', 'DEP-P1-2026-0001', '624 - Transports', 'Charge Générale', '—', '15 000', '-60 000'],
            ['Novembre 2026', 'V-P1-2026-001', '701 - Ventes de Produits Avicoles', 'Aviculture', '100 000', '—', '40 000'],
            ['Novembre 2026', '—', '7011 - Produit test', 'Aviculture', '2 000', '—', '42 000'],
            ['Novembre 2026', 'V-P1-2026-002', '707 - Ventes de Marchandises (Commerce Annexe)', 'Commerce Annexe', '80 000', '—', '122 000'],
        ], $this->lignes($c, "//table[@data-table='recettes']/tbody/tr"));
    }

    public function test_le_resultat_net_est_celui_de_la_comptabilite_du_serveur(): void
    {
        // BR-CPT-005 : meme source (LivreComptable) donc meme Resultat Net que le Compte de Resultat sur la meme periode.
        $this->poserLeJeu();
        $c = $this->rapport()->set('debut', '2026-01-01')->set('fin', '2026-12-31');

        // Exercice 2026 entier : produits 701 (30 000 + 120 000 - 20 000 + 99 999) + 707 80 000 + 7011 2 000 = 311 999 ; charges 60 000.
        $this->assertSame('311 999 FCFA', $this->nombre($c, 'total-recettes'));
        $this->assertSame('251 999 FCFA', $this->nombre($c, 'resultat-net'));
        $this->assertSame('Janvier 2026 — Décembre 2026', $this->texte($c, "//table[@data-table='recettes']/tbody/tr[1]/td[1]"));
    }

    public function test_bornes_de_periode_incluses_premier_et_dernier_instant(): void
    {
        $this->poserLeJeu();
        // 18/11 23:59:59 (7011, 2 000) et 01/11 00:00:00 (701) sont DANS la periode ; 31/10 23:59:59 et 19/11 00:00:00 non.
        $c = $this->rapport();
        $this->assertSame(['100 000'], $this->textes($c, "//tr[@data-compte='701']/td[@data-encaissement]"));
        $this->assertSame(['2 000'], $this->textes($c, "//tr[@data-compte='7011']/td[@data-encaissement]"));

        // Periode d'un seul jour : on ne voit que ce jour (05/11 : V2 707 80 000 et ACH 601 40 000).
        $c->set('debut', '2026-11-05')->set('fin', '2026-11-05');
        $this->assertSame('80 000 FCFA', $this->nombre($c, 'total-recettes'));
        $this->assertSame('40 000 FCFA', $this->nombre($c, 'total-depenses'));
        $this->assertSame('Novembre 2026', $this->texte($c, "//tr[@data-compte='707']/td[1]"));
        $c->assertSee('du 05/11/2026 au 05/11/2026');
    }

    public function test_le_dernier_microsecond_du_dernier_jour_est_inclus(): void
    {
        $this->piece('2026-11-18 23:59:59.999999', [['707', 0, 300], ['531', 300, 0]], 'V-FIN');
        $this->piece('2026-11-19 00:00:00', [['707', 0, 900], ['531', 900, 0]], 'V-APRES');
        $this->assertSame('300 FCFA', $this->nombre($this->rapport(), 'total-recettes'));
    }

    public function test_un_remboursement_vient_en_deduction_de_la_charge_et_les_centres_622_et_602_existent(): void
    {
        $this->piece('2026-11-05 10:00:00', [['624', 1000, 0], ['531', 0, 1000]], 'D-1');
        $this->piece('2026-11-06 10:00:00', [['531', 400, 0], ['624', 0, 400]], 'D-2');   // avoir : charge nette 600
        $this->piece('2026-11-07 10:00:00', [['622', 700, 0], ['531', 0, 700]], 'D-3');
        $this->piece('2026-11-08 10:00:00', [['602', 800, 0], ['531', 0, 800]], 'D-4');
        $c = $this->rapport();

        $this->assertSame(['602 - Achats de Marchandises (Commerce Annexe)|Commerce Annexe|800', '622 - Frais Vétérinaires|Aviculture|700', '624 - Transports|Charge Générale|600'],
            array_map(fn ($l) => $l[2].'|'.$l[3].'|'.$l[5], $this->lignes($c, "//table[@data-table='recettes']/tbody/tr")));
        $this->assertSame('2 100 FCFA', $this->nombre($c, 'total-depenses'));
    }

    public function test_les_montants_sont_arrondis_comme_le_poste_pas_a_la_hausse_en_export(): void
    {
        $this->piece('2026-11-05 10:00:00', [['531', 1000.4, 0], ['701', 0, 1000.4]], 'V-1');
        $c = $this->rapport()->call('exporter');
        $csv = explode("\n", base64_decode($c->effects['download']['content']));
        $this->assertStringContainsString(';1000;0;1000', implode("\n", $csv));
    }

    public function test_la_periode_inversee_est_remise_d_aplomb_comme_au_poste(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport()->set('debut', '2026-11-18')->set('fin', '2026-11-01');

        $c->assertSet('debut', '2026-11-01')->assertSet('fin', '2026-11-18');
        $this->assertSame('182 000 FCFA', $this->nombre($c, 'total-recettes'));
        $c->assertDontSeeHtml('data-alerte="periode"');
    }

    public function test_une_date_invalide_retombe_sur_le_mois_en_cours_et_le_dit(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport()->set('debut', 'pas-une-date');

        $c->assertSeeHtml('data-alerte="periode"')->assertSee('du 01/11/2026 au 18/11/2026');
        $this->assertSame('182 000 FCFA', $this->nombre($c, 'total-recettes'));
    }

    public function test_les_totaux_portent_sur_tout_le_cumul_sur_les_lignes_filtrees(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport()->set('filtreCentre', 'Aviculture');

        // Les KPI decrivent la periode entiere ; le cumul est celui du centre affiche.
        $this->assertSame('182 000 FCFA', $this->nombre($c, 'total-recettes'));
        $this->assertSame('122 000 FCFA', $this->nombre($c, 'resultat-net'));
        $this->assertSame(['-40 000', '-45 000', '55 000', '57 000'], $this->textes($c, "//table[@data-table='recettes']/tbody/tr/td[@data-cumul]"));

        $c->set('filtreCentre', 'Commerce Annexe');
        $this->assertSame(['80 000'], $this->textes($c, "//table[@data-table='recettes']/tbody/tr/td[@data-cumul]"));
        $c->set('filtreCentre', 'Charge Générale');
        $this->assertSame(['-15 000'], $this->textes($c, "//table[@data-table='recettes']/tbody/tr/td[@data-cumul]"));

        $c->call('reinitialiserFiltres')->assertSet('filtreCentre', null);
        $this->assertCount(6, $this->lignes($c, "//table[@data-table='recettes']/tbody/tr"));
    }

    public function test_un_filtre_trafique_vaut_tous_les_centres(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport()->set('filtreCentre', 'Pirate');

        $this->assertCount(6, $this->lignes($c, "//table[@data-table='recettes']/tbody/tr"));
    }

    public function test_sans_ecriture_les_etats_vides_et_les_taux_indefinis_sont_dits_en_clair(): void
    {
        $c = $this->rapport();

        $c->assertSeeHtml('data-vide="recettes"')->assertSee('Aucune écriture de gestion sur la période.');
        $c->assertSeeHtml('data-vide="comparatif"')->assertSee('Aucun produit ni charge sur la période sélectionnée.');
        $this->assertSame('0 FCFA', $this->nombre($c, 'total-recettes'));
        $this->assertSame('—', $this->nombre($c, 'taux-marge'));   // recettes nulles : pas de division
    }

    public function test_un_filtre_sans_resultat_ne_dit_pas_qu_il_n_y_a_aucune_ecriture(): void
    {
        $this->piece('2026-11-05 09:00:00', [['531', 1000, 0], ['707', 0, 1000]], 'V-1');
        $c = $this->rapport()->set('filtreCentre', 'Aviculture');

        $c->assertSee('Aucune ligne ne correspond à ce centre de profit.')->assertDontSee('Aucune écriture de gestion');
    }

    public function test_le_comparatif_recettes_depenses_a_des_barres_proportionnelles(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport();

        $c->assertSeeHtml('data-barre="Recettes"')->assertSeeHtml('style="width: 100%"')->assertSeeHtml('style="width: 33%"');
    }

    // ============================================================ État de Trésorerie

    public function test_tresorerie_soldes_ouverture_cloture_et_mouvements_exacts(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport('tresorerie');

        // Soldes de cloture = ouverture (avant le 01/11) + mouvements de la periode, par compte de classe 5.
        $this->assertSame('261 500 FCFA', $this->nombre($c, 'compte-caisse'));
        $this->assertSame('42 000 FCFA', $this->nombre($c, 'compte-mobile-money'));
        $this->assertSame('303 500 FCFA', $this->nombre($c, 'tresorerie-nette'));
        $c->assertSee('Caisse Espèces')->assertSee('Solde au 18/11/2026');

        // Ouvertures, dans l'ordre du plan (512 avant 531) : Mobile Money 50 000 ; Caisse 20 000 + 100 000 + 30 000 (exercices anterieurs compris).
        $this->assertSame([['01/11/2026', 'Mobile Money', 'Solde d\'Ouverture', '50 000'], ['01/11/2026', 'Caisse', 'Solde d\'Ouverture', '150 000']],
            $this->lignes($c, "//table[@data-table='tresorerie']/tbody/tr[@data-ouverture]"));

        // Solde progressif PAR COMPTE (jamais Caisse et Mobile Money melanges), type deduit de l'origine de l'ecriture.
        $this->assertSame([
            ['01/11/2026', 'Caisse', 'Vente POS', 'Libelle V-P1-2026-001', '120 000', '—', '270 000'],
            ['05/11/2026', 'Caisse', 'Vente POS', 'Libelle V-P1-2026-002', '30 000', '—', '300 000'],
            ['05/11/2026', 'Caisse', 'Décaissement Achat', 'Libelle ACH-P1-2026-001', '—', '10 000', '290 000'],
            ['06/11/2026', 'Caisse', 'Annulation Vente', 'Libelle ANN-V-001', '—', '20 000', '270 000'],
            ['07/11/2026', 'Caisse', 'Remboursement Achat', 'Libelle REM-1', '1 000', '—', '271 000'],
            ['08/11/2026', 'Mobile Money', 'Encaissement Divers', 'Libelle OD-T9', '7 000', '—', '57 000'],
            ['08/11/2026', 'Caisse', 'Décaissement Divers', 'Libelle OD-T9', '—', '7 000', '264 000'],
            ['08/11/2026', 'Caisse', 'Encaissement Divers', 'Libelle OD-T2', '500', '—', '264 500'],
            ['10/11/2026', 'Mobile Money', 'Décaissement Divers', 'Libelle DEP-P1-2026-0001', '—', '15 000', '42 000'],
            ['12/11/2026', 'Caisse', 'Décaissement Divers', 'Libelle DEP-P1-2026-0002', '—', '5 000', '259 500'],
            ['18/11/2026', 'Caisse', 'Encaissement Divers', 'Libelle sans numero', '2 000', '—', '261 500'],
        ], $this->lignes($c, "//table[@data-table='tresorerie']/tbody/tr[@data-mouvement]"));
    }

    public function test_l_ordre_des_mouvements_du_meme_instant_est_deterministe_quels_que_soient_les_uuid(): void
    {
        // Decision 46f_ : meme date -> instant de saisie de la piece, puis entree avant sortie ; jamais l'ordre des UUID.
        // Ici les UUID sont adverses : la ligne creditee de T1 et la piece T2 ont les plus PETITS identifiants.
        $this->poserLeJeu();
        $c = $this->rapport('tresorerie');

        $this->assertSame(
            ['Libelle OD-T9|Mobile Money|7 000', 'Libelle OD-T9|Caisse|—', 'Libelle OD-T2|Caisse|500'],
            array_map(fn (array $l) => $l[3].'|'.$l[1].'|'.($l[4] === '—' ? '—' : $l[4]), $this->lignes($c, "//table[@data-table='tresorerie']/tbody/tr[@data-mouvement][td[1][text()='08/11/2026']]")),
        );
    }

    public function test_le_filtre_de_compte_garde_le_solde_progressif_du_compte_et_ses_ouvertures(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport('tresorerie')->set('filtreCompte', 'Mobile Money');

        $this->assertSame([['01/11/2026', 'Mobile Money', 'Solde d\'Ouverture', '50 000']], $this->lignes($c, "//table[@data-table='tresorerie']/tbody/tr[@data-ouverture]"));
        $this->assertSame(['57 000', '42 000'], $this->textes($c, "//tr[@data-mouvement]/td[@data-solde]"));
        // Les KPI ne suivent pas le filtre.
        $this->assertSame('303 500 FCFA', $this->nombre($c, 'tresorerie-nette'));
        $this->assertSame('261 500 FCFA', $this->nombre($c, 'compte-caisse'));

        $c->set('filtreCompte', 'Caisse');
        $this->assertCount(9, $this->lignes($c, "//tr[@data-mouvement]"));
        $c->set('filtreCompte', '999');   // option inconnue : « tous »
        $this->assertCount(11, $this->lignes($c, "//tr[@data-mouvement]"));
    }

    public function test_une_periode_decalee_recalcule_l_ouverture_avec_tout_ce_qui_precede(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport('tresorerie')->set('debut', '2026-11-05')->set('fin', '2026-11-05');

        // Ouverture Caisse au 05/11 = 150 000 + 120 000 (01/11) ; mouvements du jour : +30 000 puis -10 000.
        $this->assertSame([['05/11/2026', 'Mobile Money', 'Solde d\'Ouverture', '50 000'], ['05/11/2026', 'Caisse', 'Solde d\'Ouverture', '270 000']],
            $this->lignes($c, "//tr[@data-ouverture]"));
        $this->assertSame(['300 000', '290 000'], $this->textes($c, "//tr[@data-mouvement]/td[@data-solde]"));
        $this->assertSame('290 000 FCFA', $this->nombre($c, 'compte-caisse'));
        $this->assertSame('50 000 FCFA', $this->nombre($c, 'compte-mobile-money'));
        $this->assertSame('340 000 FCFA', $this->nombre($c, 'tresorerie-nette'));
    }

    public function test_tresorerie_sans_mouvement_affiche_les_ouvertures_et_le_message(): void
    {
        $this->piece('2026-09-15 10:00:00', [['531', 40000, 0], ['101', 0, 40000]], 'OD-1');
        $c = $this->rapport('tresorerie');

        $c->assertSeeHtml('data-vide="tresorerie"')->assertSee('Aucun mouvement de trésorerie sur la période.');
        $this->assertSame('40 000 FCFA', $this->nombre($c, 'compte-caisse'));
        $this->assertSame('40 000 FCFA', $this->nombre($c, 'tresorerie-nette'));
    }

    public function test_les_deux_vues_existent_tableau_des_640_px_et_cartes_en_dessous(): void
    {
        $this->poserLeJeu();
        foreach (['recettes', 'tresorerie'] as $onglet) {
            $c = $this->rapport($onglet);
            $c->assertSeeHtml('hidden overflow-x-auto sm:block')->assertSeeHtml('data-vue="cartes"')->assertSeeHtml('sm:hidden');
        }
        $c = $this->rapport('recettes');
        $this->assertCount(6, $this->textes($c, "//*[@data-vue='cartes']/article"));
        $c = $this->rapport('tresorerie');
        $this->assertCount(13, $this->textes($c, "//*[@data-vue='cartes']/article"));   // 2 ouvertures + 11 mouvements
    }
}
