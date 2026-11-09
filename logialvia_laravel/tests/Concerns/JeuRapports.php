<?php

namespace Tests\Concerns;

use App\Models\Achat;
use App\Models\Client;
use App\Models\EcritureComptable;
use App\Models\ExerciceComptable;
use App\Models\Fournisseur;
use App\Models\LigneVente;
use App\Models\PieceComptable;
use App\Models\PlanComptable;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\PlanComptableSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Support\Str;
use Livewire\Features\SupportTesting\Testable;

/**
 * Outils des tests de « Rapports & Etats » : « maintenant » fige au 18/11/2026 10:00 (Africa/Porto-Novo, UTC+1,
 * sans heure d'ete), donnees posees EN BASE comme le serveur les aurait recues, lecture du HTML par XPath.
 * Les colonnes de date sont en UTC : `loc()` convertit un instant LOCAL.
 */
trait JeuRapports
{
    protected function amorcerRapports(): void
    {
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        $this->seed(PlanComptableSeeder::class);
        $this->travelTo(CarbonImmutable::parse('2026-11-18 10:00:00', 'Africa/Porto-Novo'));
    }

    protected function utilisateurRapports(string $role, string $username = 'u'): User
    {
        $u = User::query()->where('username', $username)->first();
        if ($u === null) {
            $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
            $u->assignRole($role);
        }

        return $u;
    }

    /** Instant LOCAL (Porto-Novo) -> UTC, tel qu'il est range en base. */
    protected function loc(string $instant): CarbonImmutable
    {
        return CarbonImmutable::parse($instant, 'Africa/Porto-Novo')->utc();
    }

    // ------------------------------------------------------------------ Lecture du HTML

    /** @return \DOMXPath */
    protected function xpath(Testable $c): \DOMXPath
    {
        $dom = new \DOMDocument;
        libxml_use_internal_errors(true);
        $dom->loadHTML('<?xml encoding="UTF-8">'.$c->html());
        libxml_clear_errors();

        return new \DOMXPath($dom);
    }

    /** Texte normalise du PREMIER noeud qui correspond (null s'il n'y en a pas). */
    protected function texte(Testable $c, string $xpath): ?string
    {
        $n = $this->xpath($c)->query($xpath)->item(0);

        return $n === null ? null : trim(preg_replace('/\s+/u', ' ', $n->textContent));
    }

    /** @return list<string> */
    protected function textes(Testable $c, string $xpath): array
    {
        $out = [];
        foreach ($this->xpath($c)->query($xpath) as $n) {
            $out[] = trim(preg_replace('/\s+/u', ' ', $n->textContent));
        }

        return $out;
    }

    /**
     * Lignes d'un tableau : une liste de cellules (texte normalise) par `<tr>` qui correspond.
     *
     * @return list<list<string>>
     */
    protected function lignes(Testable $c, string $xpathTr): array
    {
        $out = [];
        foreach ($this->xpath($c)->query($xpathTr) as $tr) {
            $cells = [];
            foreach ($tr->childNodes as $td) {
                if ($td instanceof \DOMElement && $td->tagName === 'td') {
                    $cells[] = trim(preg_replace('/\s+/u', ' ', $td->textContent));
                }
            }
            $out[] = $cells;
        }

        return $out;
    }

    protected function nombre(Testable $c, string $kpi): ?string
    {
        return $this->texte($c, "//*[@data-kpi='$kpi']");
    }

    // ------------------------------------------------------------------ Comptabilite

    /**
     * Une piece posee EN BASE. `$lignes` : [compte, debit, credit, id?]. `$instant` : LOCAL.
     * `updated_at` = instant de saisie du poste (departage les pieces d'un meme instant).
     */
    protected function piece(string $instant, array $lignes, ?string $numero = null, array $surcharge = [], ?string $saisie = null): PieceComptable
    {
        $date = $this->loc($instant);
        $annee = (int) $date->timezone('Africa/Porto-Novo')->year;
        ExerciceComptable::query()->firstOrCreate(['annee' => $annee], ['is_cloture' => false]);

        $piece = (new PieceComptable)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => '11111111-1111-4111-8111-111111111111',
            'numero_piece' => $numero, 'date_ecriture' => $date, 'exercice_annee' => $annee, 'journal_code' => 'OD',
            'vente_ref' => null, 'achat_ref' => null, 'contrepasse_de' => null,
            'updated_at' => $saisie === null ? $date : $this->loc($saisie), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $piece->save();

        foreach ($lignes as $l) {
            [$compte, $debit, $credit] = $l;
            (new EcritureComptable)->forceFill([
                'id' => $l[3] ?? (string) Str::uuid(),
                'piece_id' => $piece->id, 'numero_compte' => $compte, 'debit' => $debit, 'credit' => $credit,
                'libelle' => 'Libelle '.($numero ?? 'sans numero'), 'axe_analytique' => null,
            ])->save();
        }

        return $piece;
    }

    protected function compte(string $numero, string $libelle, string $classe): void
    {
        PlanComptable::query()->firstOrCreate(['numero_compte' => $numero], ['libelle' => $libelle, 'classe' => $classe, 'archive' => false]);
    }

    // ------------------------------------------------------------------ Ventes / achats

    protected function produit(string $nom = 'Poulet'): ProduitVendable
    {
        return ProduitVendable::query()->firstOrCreate(['name' => $nom], [
            'id' => (string) Str::uuid(), 'cat' => 'Volaille', 'price' => 1000, 'unit' => 'pièce', 'icon' => 'category', 'saisi_le' => now(),
        ]);
    }

    protected function client(string $nom, ?string $id = null): Client
    {
        $c = (new Client)->forceFill([
            'id' => $id ?? (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => $nom, 'solde_creance' => 0,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $c->save();

        return $c;
    }

    protected function vente(array $surcharge = []): Vente
    {
        static $n = 0;
        $n++;
        $v = (new Vente)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => "V-P1-2026-9$n",
            'portee_reference' => '', 'client' => 'Amina Bako', 'client_id' => null,
            'date_vente' => $this->loc('2026-11-10 12:00:00'), 'mode' => 'Espèces', 'status' => 'Payée',
            'total' => 0, 'paye' => 0, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $v->save();

        return $v;
    }

    protected function ligneVente(Vente $vente, float $qte, float $pu, ?string $espece = null): void
    {
        (new LigneVente)->forceFill([
            'id' => (string) Str::uuid(), 'vente_id' => $vente->id, 'produit_id' => $this->produit()->id,
            'name' => 'Poulet', 'qte' => $qte, 'pu' => $pu, 'espece' => $espece,
        ])->save();
    }

    protected function fournisseur(string $nom, ?string $id = null): Fournisseur
    {
        $f = (new Fournisseur)->forceFill([
            'id' => $id ?? (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => $nom,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $f->save();

        return $f;
    }

    protected function achat(Fournisseur $f, array $surcharge = []): Achat
    {
        static $n = 0;
        $n++;
        $a = (new Achat)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => "ACH-P1-2026-9$n",
            'portee_reference' => '', 'fournisseur_id' => $f->id, 'date_achat' => $this->loc('2026-11-03 09:00:00'),
            'statut' => 'Livré', 'total' => 0, 'paye' => 0, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $a->save();

        return $a;
    }
}
