<?php

namespace Tests\Concerns;

use App\Models\User;
use App\Services\PostesService;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Support\Str;

/** Postes appaires pour les tests de synchronisation. */
trait PostesDeTest
{
    protected function amorcerSocle(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        \App\Models\ParametresEntreprise::courant();
    }

    protected function compteAvecRole(string $role, string $username): User
    {
        $utilisateur = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $utilisateur->assignRole($role);

        return $utilisateur;
    }

    /** @return array{jeton: string, device: string, utilisateur: User} */
    protected function poste(string $role = 'caissier', ?string $username = null): array
    {
        $utilisateur = $this->compteAvecRole($role, $username ?? $role.'-'.Str::random(5));
        $device = (string) Str::uuid();
        $appairage = app(PostesService::class)->appairer($utilisateur, $device);

        return ['jeton' => $appairage['jeton'], 'device' => $device, 'utilisateur' => $utilisateur];
    }

    /**
     * Requete portant ce jeton. Les requetes d'un MEME test partagent la garde
     * d'authentification : on l'oublie avant chaque appel, comme le fait un vrai
     * serveur entre deux requetes.
     */
    protected function avecJeton(string $jeton): static
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($jeton);
    }

    /** Une ligne `clients` telle qu'un poste l'enverrait. */
    protected function ligneClient(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'nom' => 'Client '.Str::random(4),
            'telephone' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    /** Un incubateur tel qu'un poste l'enverrait. */
    protected function ligneMachine(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'code' => 'INC-01',
            'libelle' => 'Couveuse atelier 528 œufs',
            'capacite_oeufs' => 528,
            'active' => true,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    /** Un lot de couveuse tel qu'un poste l'enverrait (mirages encore a faire). */
    protected function ligneCycle(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'code_incubation' => 'C-P1-2026-001',
            'espece' => 'goliath',
            'date_incubation' => '2026-08-01',
            'oeufs_couves' => 200,
            'poussins_nes' => null,
            'oeufs_perdus' => null,
            'statut' => 'En Incubation',
            'machine_id' => null,
            'oeufs_blancs_j7' => null,
            'oeufs_gates_j14' => null,
            'lot_parent_id' => null,
            'supprime_le' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    /** Un produit tel qu'un poste le propose (sans stock : jamais synchronise). */
    protected function ligneProduit(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'sku' => 'PRD-001',
            'name' => 'Goliath mature',
            'cat' => 'Avicole',
            'price' => 25000,
            'price_max' => null,
            'unit' => 'u',
            'icon' => 'egg',
            'cout_revient' => null,
            'groupe_taxe' => 'A',
            'threshold' => 2,
            'espece' => 'goliaths',
        ], $surcharge);
    }

    /** Cree un produit au serveur par une demande acceptee ; renvoie son id. */
    protected function produitConnu(array $poste, array $surcharge = []): string
    {
        $produit = $this->ligneProduit($surcharge);
        $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => [[
                'id' => (string) Str::uuid(),
                'type' => 'produit_vendable',
                'saisi_le' => now()->format('Y-m-d\TH:i:s.u\Z'),
                'donnees' => $produit,
            ]],
        ])->assertOk()->assertJsonPath('rejected', []);

        return $produit['id'];
    }

    /** Une vente (avec une ligne) telle qu'un poste l'enverrait. */
    protected function ligneVente(string $produitId, array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'reference' => 'V-P1-2026-001',
            'client' => 'Client Comptant',
            'client_id' => null,
            'date_vente' => now()->format('Y-m-d\TH:i:s.u\Z'),
            'mode' => 'Espèces',
            'status' => 'Payée',
            'total' => 50000,
            'paye' => 50000,
            'motif_annulation' => null,
            'echeance' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
            'lignes' => [[
                'id' => (string) Str::uuid(),
                'produit_id' => $produitId,
                'name' => 'Goliath mature',
                'qte' => 2,
                'pu' => 25000,
                'espece' => 'goliaths',
            ]],
        ], $surcharge);
    }

    /** Un fournisseur tel qu'un poste l'enverrait. */
    protected function ligneFournisseur(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'nom' => 'Maïs Local',
            'telephone' => '97000001',
            'adresse' => null,
            'fournit' => 'Maïs, Soja',
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    /** Un achat (avec une ligne) tel qu'un poste l'enverrait. */
    protected function ligneAchat(string $fournisseurId, array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'reference' => 'ACH-P1-2026-001',
            'fournisseur_id' => $fournisseurId,
            'date_achat' => now()->format('Y-m-d\TH:i:s.u\Z'),
            'statut' => 'Commandé',
            'total' => 30000,
            'paye' => 10000,
            'mode' => 'Espèces',
            'echeance' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
            'lignes' => [[
                'id' => (string) Str::uuid(),
                'intrant_code' => 'INT-001',
                'nom' => 'Maïs',
                'qte' => 100,
                'pu_achat' => 300,
            ]],
        ], $surcharge);
    }

    /** Un intrant tel qu'un poste le propose (sans stock ni PMP : propres a chaque poste). */
    protected function ligneIntrant(array $surcharge = []): array
    {
        return array_merge([
            'code' => 'INT-001',
            'name' => 'Maïs',
            'cat' => 'Aliment',
            'unit' => 'kg',
            'threshold' => 25,
        ], $surcharge);
    }

    /** Cree un intrant au serveur par une demande acceptee ; renvoie son code. */
    protected function intrantConnu(array $poste, array $surcharge = []): string
    {
        $intrant = $this->ligneIntrant($surcharge);
        $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => [[
                'id' => (string) Str::uuid(),
                'type' => 'intrant',
                'saisi_le' => now()->format('Y-m-d\TH:i:s.u\Z'),
                'donnees' => $intrant,
            ]],
        ])->assertOk()->assertJsonPath('rejected', []);

        return $intrant['code'];
    }

    /** Un mouvement du journal tel qu'un poste l'enverrait. */
    protected function ligneMouvement(string $code = 'INT-001', array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'horodatage' => now()->format('Y-m-d\TH:i:s.u\Z'),
            'intrant_code' => $code,
            'article' => 'Maïs',
            'type' => 'Entrée',
            'motif' => 'Réception commande ACH-P1-2026-001',
            'quantite' => 100,
            'reference' => 'ACH-P1-2026-001',
        ], $surcharge);
    }

    protected function ligneMouvementProduit(string $produitId, array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'horodatage' => now()->format('Y-m-d\TH:i:s.u\Z'),
            'produit_id' => $produitId,
            'article' => 'Poulet de chair',
            'motif' => 'Correction de stock (catalogue)',
            'quantite' => -3,
        ], $surcharge);
    }

    /** Une facture de vente (avec une ligne, groupe B a 18 %) telle qu'un poste l'enverrait. */
    protected function ligneFacture(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'reference' => 'FV-P1-2026-001',
            'type' => 'FV',
            'vente_ref' => null,
            'origine_ref' => null,
            'date_facture' => now()->format('Y-m-d\TH:i:s.u\Z'),
            'client' => 'DOSSOU Félicité',
            'client_ifu' => null,
            'client_adresse' => null,
            'total_ht' => 10000,
            'total_taxe' => 1800,
            'total_ttc' => 11800,
            'motif' => null,
            'statut' => 'a_transmettre',
            'code_mecef' => null,
            'nim' => null,
            'compteur' => null,
            'lien_verification' => null,
            'date_normalisation' => null,
            'erreur_transmission' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
            'lignes' => [[
                'id' => (string) Str::uuid(),
                'designation' => 'Goliath mature',
                'quantite' => 1,
                'unite' => 'u',
                'prix_unitaire_ht' => 10000,
                'groupe_taxe' => 'B',
                'taux_taxe' => 18,
                'montant_ht' => 10000,
                'montant_taxe' => 1800,
            ]],
        ], $surcharge);
    }

    /** Une facture NORMALISEE (code et NIM rendus par la DGI). */
    protected function ligneFactureNormalisee(array $surcharge = []): array
    {
        return $this->ligneFacture(array_merge([
            'statut' => 'normalisee',
            'code_mecef' => 'CODE-A',
            'nim' => 'NIM-1',
            'compteur' => '12/50',
            'lien_verification' => 'https://dgi.example/v/1',
            'date_normalisation' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge));
    }

    /** Une fiche journaliere telle qu'un poste l'enverrait (UUID deterministe de espece + date). */
    protected function ligneFicheJournee(string $espece = 'goliaths', string $jour = '2026-11-05', array $surcharge = []): array
    {
        return array_merge([
            'id' => \App\Support\UuidDeterministe::ficheJournee($espece, $jour),
            'espece' => $espece,
            'date' => $jour,
            'achat' => 0, 'ne' => 0, 'vente' => 0,
            'mort_cat1' => 0, 'mort_cat2' => 0, 'mort_cat3' => 0, 'mort_cat4' => null,
            'don_cat1' => 0, 'don_cat2' => 0, 'don_cat3' => 0, 'don_cat4' => null,
            'effectif' => 10, 'eff_cat1_day' => 4, 'eff_cat2_day' => 3, 'eff_cat3_day' => 3, 'eff_cat4_day' => null,
            'srh' => null, 'ts' => null, 'stock_final_oeufs' => null,
            'oeufs_pondus' => null, 'oeufs_casses' => null, 'sorties_plateaux' => null,
            'poids_general_g' => null,
            'traitement_obs' => null,
            'traitement_valide' => false,
            'is_recorded' => true,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    /** Le compteur de ventes du jour d'UN poste (UUID deterministe de espece + date + poste). */
    protected function ligneVentesJour(string $device, string $espece = 'goliaths', string $jour = '2026-11-05', array $surcharge = []): array
    {
        return array_merge([
            'id' => \App\Support\UuidDeterministe::ventesJour($espece, $jour, $device),
            'espece' => $espece,
            'date' => $jour,
            'qte' => 2,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    /** Une bande telle qu'un poste l'enverrait. */
    protected function ligneBande(string $code = 'B1', array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'espece' => 'goliaths',
            'code' => $code,
            'date_mise_en_bande' => '2026-10-01',
            'effectif_initial' => 100,
            'date_cloture' => null,
            'observations' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }
}
