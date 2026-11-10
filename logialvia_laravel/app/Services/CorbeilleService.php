<?php

namespace App\Services;

use App\Livewire\Catalogue;
use App\Models\BaremeRation;
use App\Models\Client;
use App\Models\CycleCouveuse;
use App\Models\EcheanceProphylaxie;
use App\Models\Fournisseur;
use App\Models\MachineIncubateur;
use App\Models\Poste;
use App\Models\ProduitVendable;
use App\Models\TauxRationPoids;
use App\Models\User;
use App\Support\Audit;
use App\Sync\DemandesReferentiel;
use App\Sync\Tables\ClientsTable;
use App\Sync\Tables\CyclesCouveuseTable;
use App\Sync\Tables\FournisseursTable;
use App\Sync\Tables\MachinesIncubateurTable;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Collection;
use Illuminate\Support\Str;

/**
 * Corbeille du SERVEUR (Dart : `service_archivage.dart`, onglet Corbeille ; doc 47u §3).
 *
 * Au serveur, « supprime » = une PIERRE TOMBALE : `supprime_le` (faits : clients, fournisseurs,
 * lots, incubateurs), `archive_le` (referentiels : produits, baremes, taux, echeances) ou la
 * suppression logique d'un compte. La ligne reste en base ; les postes l'archivent a leur tour.
 *
 * - LISTE : tout ce qui porte une pierre tombale (liste blanche ci-dessous : jamais un nom de
 *   table venu d'une saisie).
 * - RESTAURATION : une ECRITURE qui leve la pierre tombale, par les MEMES chemins que pour un
 *   poste (`TableSync::absorber` pour un fait, `DemandesReferentiel::traiter` pour un
 *   referentiel) : memes validations, meme droit d'ecriture, dernier ecrivain gagne. La ligne
 *   restauree redescend vers tous les postes. Un type `reserveALAdmin` (comptes, comme au poste)
 *   ne se restaure que par un administrateur.
 * - PURGE definitive : reservee a l'administrateur, mais SEULEMENT pour les comptes. Les autres
 *   pierres tombales ne s'effacent jamais : elles seules empechent un poste hors ligne de
 *   ressusciter l'element (`46_` §15), et effacer un client detacherait ses ventes.
 */
class CorbeilleService
{
    /** Messages d'erreur communs avec le Dart. */
    public const MOTIF_ABSENT = 'Cet élément n\'est plus en corbeille.';

    /**
     * Liste blanche des types : cle => descripteur.
     *
     * @return array<string, array<string, mixed>>
     */
    public static function types(): array
    {
        $types = [
            'utilisateurs' => [
                'libelle' => 'Utilisateur', 'module' => 'Administration', 'admin' => true, 'purgeable' => true,
                'modele' => User::class, 'colonne' => 'deleted_at', 'mode' => 'compte',
                'designation' => fn (User $m) => "{$m->name} ({$m->username})",
            ],
            'produits' => [
                'libelle' => 'Produit du catalogue', 'module' => 'Commercial', 'admin' => false,
                'modele' => ProduitVendable::class, 'colonne' => 'archive_le', 'mode' => 'demande',
                'demande' => DemandesReferentiel::TYPE_PRODUIT, 'droit' => 'manage-ventes', 'horodatage' => 'saisi_le',
                'champs' => ['id', 'sku', 'name', 'cat', 'price', 'price_max', 'unit', 'icon', 'cout_revient', 'groupe_taxe', 'threshold', 'espece'],
                'designation' => fn (ProduitVendable $m) => $m->name,
            ],
            'clients' => [
                'libelle' => 'Client', 'module' => 'Commercial', 'admin' => false,
                'modele' => Client::class, 'colonne' => 'supprime_le', 'mode' => 'fait', 'table' => ClientsTable::class,
                'designation' => fn (Client $m) => $m->nom,
            ],
            'fournisseurs' => [
                'libelle' => 'Fournisseur', 'module' => 'Approvisionnement', 'admin' => false,
                'modele' => Fournisseur::class, 'colonne' => 'supprime_le', 'mode' => 'fait', 'table' => FournisseursTable::class,
                'designation' => fn (Fournisseur $m) => $m->nom,
            ],
            'lots' => [
                'libelle' => 'Lot d\'incubation', 'module' => 'Élevage', 'admin' => false,
                'modele' => CycleCouveuse::class, 'colonne' => 'supprime_le', 'mode' => 'fait', 'table' => CyclesCouveuseTable::class,
                'designation' => fn (CycleCouveuse $m) => "{$m->code_incubation} — {$m->oeufs_couves} œufs",
            ],
            'incubateurs' => [
                'libelle' => 'Incubateur', 'module' => 'Élevage', 'admin' => false,
                'modele' => MachineIncubateur::class, 'colonne' => 'supprime_le', 'mode' => 'fait', 'table' => MachinesIncubateurTable::class,
                'designation' => fn (MachineIncubateur $m) => "{$m->code} — {$m->libelle}",
            ],
            'baremes' => [
                'libelle' => 'Barème de rationnement', 'module' => 'Élevage', 'admin' => false,
                'modele' => BaremeRation::class, 'colonne' => 'archive_le', 'mode' => 'demande',
                'demande' => DemandesReferentiel::TYPE_BAREME, 'droit' => 'manage-elevage', 'horodatage' => 'saisi_le',
                'champs' => ['id', 'espece', 'stade', 'ration_grammes_par_jour', 'confirme'],
                'designation' => fn (BaremeRation $m) => "{$m->espece} — {$m->stade}",
            ],
            'taux' => [
                'libelle' => 'Taux de ration par classe de poids', 'module' => 'Élevage', 'admin' => false,
                'modele' => TauxRationPoids::class, 'colonne' => 'archive_le', 'mode' => 'demande',
                'demande' => DemandesReferentiel::TYPE_TAUX_POIDS, 'droit' => 'manage-elevage', 'horodatage' => 'saisi_le',
                'champs' => ['id', 'espece', 'poids_min_g', 'poids_max_g', 'taux_pourcent', 'confirme'],
                'designation' => fn (TauxRationPoids $m) => "{$m->espece} — à partir de {$m->poids_min_g} g",
            ],
            'echeances' => [
                'libelle' => 'Échéance de prophylaxie', 'module' => 'Élevage', 'admin' => false,
                'modele' => EcheanceProphylaxie::class, 'colonne' => 'archive_le', 'mode' => 'demande',
                'demande' => DemandesReferentiel::TYPE_ECHEANCE, 'droit' => 'manage-elevage', 'horodatage' => 'saisi_le',
                'champs' => ['id', 'espece', 'jour_cycle', 'traitement', 'produit', 'remanence_jours', 'dose'],
                'designation' => fn (EcheanceProphylaxie $m) => "{$m->espece} — J{$m->jour_cycle} {$m->traitement}",
            ],
        ];

        // Messages a l'editeur (doc 47u §4) : un fait comme les autres, restaurable par son auteur ou l'administrateur.
        if (class_exists(\App\Models\MessageEditeur::class)) {
            $types['messages'] = [
                'libelle' => 'Message à l\'éditeur', 'module' => 'Compte', 'admin' => false,
                'modele' => \App\Models\MessageEditeur::class, 'colonne' => 'supprime_le', 'mode' => 'fait',
                'table' => \App\Sync\Tables\MessagesEditeurTable::class,
                'designation' => fn (Model $m) => (string) $m->sujet,
            ];
        }

        return $types;
    }

    private function descripteur(string $type): ?array
    {
        return self::types()[$type] ?? null;
    }

    /** Instant d'ecriture de la restauration : maintenant, mais toujours APRES la pierre tombale. */
    private function instant(?Model $ligne, string $colonne): CarbonImmutable
    {
        $maintenant = CarbonImmutable::now('UTC');
        $existant = $ligne?->getAttribute($colonne);

        return $existant !== null && CarbonImmutable::parse($existant)->utc()->greaterThanOrEqualTo($maintenant)
            ? CarbonImmutable::parse($existant)->utc()->addMillisecond()
            : $maintenant;
    }

    private function peutRestaurer(User $u, array $d): bool
    {
        if ($d['admin'] && ! $u->hasRole('admin')) {
            return false;
        }

        return match ($d['mode']) {
            'compte' => $u->can('manage-users'),
            'demande' => $u->can($d['droit']),
            default => (new $d['table'])->peutEcrire($u),
        };
    }

    /**
     * Les elements en corbeille, le plus recent d'abord.
     *
     * @return Collection<int, array<string, mixed>>
     */
    public function elements(User $voyeur): Collection
    {
        $postes = Poste::query()->pluck('code', 'device_id');
        $elements = collect();

        foreach (self::types() as $cle => $d) {
            $requete = $d['mode'] === 'compte' ? $d['modele']::onlyTrashed() : $d['modele']::query()->whereNotNull($d['colonne']);
            foreach ($requete->limit(1000)->get() as $ligne) {
                $quand = $ligne->getAttribute($d['colonne']);
                $origine = $ligne->getAttribute('device_id');
                $elements->push([
                    'type' => $cle,
                    'id' => (string) $ligne->getKey(),
                    'module' => $d['module'],
                    'libelle' => $d['libelle'],
                    'designation' => ($d['designation'])($ligne),
                    'archive_le' => CarbonImmutable::parse($quand),
                    'origine' => match (true) {
                        $origine === null => '—',
                        $origine === Catalogue::POSTE_WEB => 'Web',
                        default => $postes[$origine] ?? 'Poste inconnu',
                    },
                    'reserve_admin' => $d['admin'],
                    'restaurable' => $this->peutRestaurer($voyeur, $d),
                    'purgeable' => ($d['purgeable'] ?? false) && $voyeur->hasRole('admin'),
                ]);
            }
        }

        return $elements->sortByDesc(fn (array $e) => $e['archive_le']->getTimestampMs())->values();
    }

    /** Leve la pierre tombale. @return string|null motif du refus. */
    public function restaurer(User $acteur, string $type, string $id): ?string
    {
        $d = $this->descripteur($type);
        if ($d === null) {
            return "Type d'élément inconnu : $type.";
        }
        // Droit verifie ICI, avant toute lecture : un refus ne revele rien.
        abort_unless($acteur->can('view-parametres'), 403);
        if ($d['admin'] && ! $acteur->hasRole('admin')) {
            return "Seul un administrateur peut restaurer un élément de type « {$d['libelle']} ».";
        }
        abort_unless($this->peutRestaurer($acteur, $d), 403);

        if ($d['mode'] === 'compte') {
            return app(UtilisateursService::class)->restaurer($acteur, $id);
        }

        $ligne = $d['modele']::query()->whereKey($id)->whereNotNull($d['colonne'])->first();
        if ($ligne === null) {
            return self::MOTIF_ABSENT;
        }

        $designation = ($d['designation'])($ligne);
        $motif = $d['mode'] === 'fait' ? $this->restaurerFait($acteur, $d, $ligne) : $this->restaurerReferentiel($acteur, $d, $ligne);
        if ($motif !== null) {
            return $motif;
        }

        Audit::enregistrer('corbeille.restaure', $acteur, ['type' => $type, 'id' => $id, 'designation' => $designation]);

        return null;
    }

    private function restaurerFait(User $acteur, array $d, Model $ligne): ?string
    {
        /** @var \App\Sync\TableSync $table */
        $table = new $d['table'];
        $instant = $this->instant($ligne, 'updated_at');

        $donnees = $table->exporter($ligne);
        $donnees['supprime_le'] = null;
        $donnees['updated_at'] = $instant->format('Y-m-d\TH:i:s.u\Z');

        $motif = $table->absorber(Catalogue::POSTE_WEB, $donnees);
        if ($motif !== null) {
            return $motif;
        }
        // Garde-fou : l'ecriture doit avoir leve la pierre tombale (sinon une version plus recente a gagne).
        if ($d['modele']::query()->whereKey($ligne->getKey())->whereNotNull($d['colonne'])->exists()) {
            return 'Une modification plus récente existe sur le serveur : la restauration est refusée.';
        }

        return null;
    }

    private function restaurerReferentiel(User $acteur, array $d, Model $ligne): ?string
    {
        $donnees = ['archive' => false];
        foreach ($d['champs'] as $champ) {
            $donnees[$champ] = $ligne->getAttribute($champ);
        }
        $instant = $this->instant($ligne, $d['horodatage']);

        $bilan = app(DemandesReferentiel::class)->traiter($acteur, Catalogue::POSTE_WEB, [[
            'id' => (string) Str::uuid(),
            'type' => $d['demande'],
            'saisi_le' => $instant->format('Y-m-d\TH:i:s.u\Z'),
            'donnees' => $donnees,
        ]]);

        return $bilan['rejected'][0]['motif'] ?? null;
    }

    /** Efface DEFINITIVEMENT un compte archive (seul type purgeable). @return string|null motif du refus. */
    public function purger(User $acteur, string $type, string $id): ?string
    {
        $d = $this->descripteur($type);
        if ($d === null) {
            return "Type d'élément inconnu : $type.";
        }
        abort_unless($acteur->can('view-parametres'), 403);
        if (! $acteur->hasRole('admin')) {
            return 'Seul un administrateur peut vider la corbeille.';
        }
        if (! ($d['purgeable'] ?? false)) {
            return "Un élément de type « {$d['libelle']} » ne s'efface jamais définitivement au serveur : sa pierre tombale empêche un poste hors ligne de le ressusciter.";
        }

        return app(UtilisateursService::class)->purger($acteur, $id);
    }
}
