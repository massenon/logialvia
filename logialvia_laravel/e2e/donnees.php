<?php
// Jeu de donnees realiste de l'essai navigateur (execute par `php artisan tinker --execute`, voir lancer.sh).
// Les ventes, achats et fiches passent par les SERVICES du serveur (ecritures comptables et stocks coherents).
use App\Models\Client;
use App\Models\Fournisseur;
use App\Models\Intrant;
use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Services\Achats\GestionAchats;
use App\Services\Commerce\VentesWeb;
use App\Services\FichesElevage;
use Carbon\CarbonImmutable;
use Illuminate\Support\Str;

$mdp = 'EssaiPoste-2026!';
$u = [];
foreach (['admin' => ['admin', 'Admin Test'], 'comptable' => ['comptable', 'Comptable Test'], 'caissier' => ['caissier', 'Caissier Test'], 'animalier' => ['animalier', 'Animalier Test']] as $id => [$role, $nom]) {
    $x = User::query()->firstOrNew(['username' => $id.'1']);
    $x->forceFill(['name' => $nom, 'password' => $mdp, 'is_active' => true, 'must_change_password' => false])->save();
    $x->syncRoles([$role]);
    $u[$id] = $x;
}
// Compte a mot de passe temporaire (parcours de premiere connexion).
$t = User::query()->firstOrNew(['username' => 'temporaire1']);
$t->forceFill(['name' => 'Temporaire Test', 'password' => $mdp, 'is_active' => true, 'must_change_password' => true])->save();
$t->syncRoles(['caissier']);

foreach (['bovins', 'pisciculture', 'cuniculture', 'heliciculture', 'aviculture_classique'] as $m) {
    ModuleActif::query()->where('module_id', $m)->update(['is_actif' => true]);
}
ParametresEntreprise::query()->update([
    'raison_sociale' => 'ALLMANY ET COMPAGNIE', 'adresse_siege' => 'Cotonou, Benin', 'telephone' => '+229 01 97 00 00 00',
    'ifu' => '3202000000001', 'mecef_actif' => true, 'mecef_url' => 'http://127.0.0.1:9/mecef', 'mecef_nim' => 'NIM123',
]);

$produits = [
    ['Poulet de chair', 'Avicole', 3500, 'pièce', null, 20], ['Pintade adulte', 'Avicole', 4500, 'pièce', 'pintades', 10],
    ['Goliath adulte', 'Avicole', 6000, 'pièce', 'goliaths', 5], ['Plateau d\'oeufs (30)', 'Avicole', 2500, 'plateau', null, 15],
    ['Lapin', 'Cuniculture', 5000, 'pièce', 'lapins', 5], ['Poisson-chat (kg)', 'Pisciculture', 2200, 'kg', null, 10],
    ['Escargots (kg)', 'Héliciculture', 7000, 'kg', null, 3], ['Fiente séchée', 'Commerce Annexe', 500, 'sac', null, 5],
];
$ids = [];
foreach ($produits as [$nom, $cat, $prix, $unite, $esp, $seuil]) {
    $p = (new ProduitVendable)->forceFill(['id' => (string) Str::uuid(), 'name' => $nom, 'cat' => $cat, 'price' => $prix, 'unit' => $unite,
        'icon' => 'category', 'groupe_taxe' => 'A', 'threshold' => $seuil, 'espece' => $esp, 'saisi_le' => now()]);
    $p->save();
    $ids[$nom] = $p->id;
}
foreach ([['PROV-DEM', 'Provende démarrage', 'Alimentation', 'kg', 100], ['PROV-CRO', 'Provende croissance', 'Alimentation', 'kg', 100],
    ['VAC-NEW', 'Vaccin Newcastle', 'Santé', 'dose', 50], ['VIT-AMN', 'Vitamines', 'Santé', 'sachet', 10],
    ['MAIS', 'Maïs concassé', 'Alimentation', 'kg', 200], ['DESINF', 'Désinfectant', 'Hygiène', 'litre', 5]] as [$code, $nom, $cat, $unite, $seuil]) {
    (new Intrant)->forceFill(['code' => $code, 'name' => $nom, 'cat' => $cat, 'unit' => $unite, 'threshold' => $seuil, 'saisi_le' => now()])->save();
}
$cli = [];
foreach ([['Amina Bako', '+229 97 11 22 33'], ['Restaurant Le Palmier', '+229 96 44 55 66'], ['Koffi Mensah', '+229 95 77 88 99'], ['Hôtel Bénin Royal', '+229 94 00 11 22'], ['Marie Dossou', null]] as [$n, $tel]) {
    $c = (new Client)->forceFill(['id' => (string) Str::uuid(), 'device_id' => null, 'nom' => $n, 'telephone' => $tel, 'solde_creance' => 0,
        'updated_at' => now(), 'serveur_modifie_le' => now()]);
    $c->save();
    $cli[$n] = $c->id;
}
$fou = [];
foreach ([['Provenderie du Golfe', '+229 21 30 00 01', 'Aliments'], ['Pharmavet Bénin', '+229 21 30 00 02', 'Santé animale'], ['Agri-Matériel SARL', '+229 21 30 00 03', 'Équipements']] as [$n, $tel, $f]) {
    $x = (new Fournisseur)->forceFill(['id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => $n, 'telephone' => $tel, 'fournit' => $f,
        'updated_at' => now(), 'serveur_modifie_le' => now()]);
    $x->save();
    $fou[$n] = $x->id;
}

// Achats : une reception reglee, une reception a credit, une commande.
$ga = new GestionAchats($u['admin']);
$r = $ga->creer(['fournisseur_id' => $fou['Provenderie du Golfe'], 'mode' => 'Espèces', 'paye' => 400000, 'echeance' => null, 'livree' => true,
    'lignes' => [['intrant_code' => 'PROV-DEM', 'qte' => 500, 'pu' => 300], ['intrant_code' => 'MAIS', 'qte' => 1000, 'pu' => 250]]]);
echo 'a1:'.($r['erreur'] ?? 'ok')."\n";
$r = $ga->creer(['fournisseur_id' => $fou['Pharmavet Bénin'], 'mode' => 'Crédit', 'paye' => 20000, 'echeance' => now()->addDays(15)->format('Y-m-d'), 'livree' => true,
    'lignes' => [['intrant_code' => 'VAC-NEW', 'qte' => 200, 'pu' => 450], ['intrant_code' => 'VIT-AMN', 'qte' => 30, 'pu' => 800]]]);
echo 'a2:'.($r['erreur'] ?? 'ok')."\n";
$r = $ga->creer(['fournisseur_id' => $fou['Agri-Matériel SARL'], 'mode' => 'Mobile Money', 'paye' => 0, 'echeance' => null, 'livree' => false,
    'lignes' => [['intrant_code' => 'DESINF', 'qte' => 10, 'pu' => 3500]]]);
echo 'a3:'.($r['erreur'] ?? 'ok')."\n";

// Ventes : comptant, a credit (creance), client de passage.
$vw = new VentesWeb($u['admin']);
$r = $vw->encaisser(['client' => 'Amina Bako', 'client_id' => $cli['Amina Bako'], 'mode' => 'Espèces', 'condition' => 'Comptant', 'montant_recu' => 7000,
    'lignes' => [['produit_id' => $ids['Poulet de chair'], 'qte' => 2, 'montant' => 7000]]]);
echo 'v1:'.($r['motif'] ?? 'ok')."\n";
$r = $vw->encaisser(['client' => 'Restaurant Le Palmier', 'client_id' => $cli['Restaurant Le Palmier'], 'mode' => 'Mobile Money', 'condition' => 'Avance (Solde Restant Dû)', 'montant_recu' => 20000,
    'echeance' => now()->addDays(10)->format('Y-m-d'),
    'lignes' => [['produit_id' => $ids['Pintade adulte'], 'qte' => 10, 'montant' => 45000], ['produit_id' => $ids['Plateau d\'oeufs (30)'], 'qte' => 8, 'montant' => 20000]]]);
echo 'v2:'.($r['motif'] ?? 'ok')."\n";
$r = $vw->encaisser(['client' => 'Client Comptant', 'mode' => 'Espèces', 'condition' => 'Comptant', 'montant_recu' => 5000,
    'lignes' => [['produit_id' => $ids['Lapin'], 'qte' => 1, 'montant' => 5000]]]);
echo 'v3:'.($r['motif'] ?? 'ok')."\n";

// Fiches d'elevage : 12 jours de goliaths et de pintades.
foreach (['goliaths', 'pintades'] as $esp) {
    $f = new FichesElevage($esp);
    $z = array_fill(0, $f->nombreCategories(), 0);
    for ($i = 12; $i >= 1; $i--) {
        $jour = CarbonImmutable::now(config('logialvia.fuseau'))->subDays($i)->format('Y-m-d');
        $morts = $z;
        if ($i === 6) {
            $morts[0] = 1;
        }
        $m = ['achat' => $i === 12 ? 120 : 0, 'ne' => 0, 'vente' => 0, 'morts' => $morts, 'dons' => $z];
        $e = $f->enregistrer($jour, $m, null, null, false, null);
        if ($e) {
            echo "fiche $esp $jour : $e\n";
        }
    }
}
echo "donnees ok\n";
