<?php

namespace App\Sync;

use App\Models\ParametresEntreprise;
use App\Models\User;
use App\Support\Audit;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

/**
 * Moteur de synchronisation (`46_` §4). Le serveur est la verite.
 *
 *  - TIRAGE (pull) : curseur rendu par le SERVEUR, jamais l'horloge du poste ; pages
 *    stables (`until`) ; seules les tables que le compte peut lire.
 *  - ENVOI (push) : tout le lot dans UNE transaction (rejouee 3 fois sur
 *    interblocage), idempotent par UUID, reponse table par table. Un refus porte son
 *    motif en francais : jamais d'echec silencieux.
 */
class MoteurSynchronisation
{
    /** @return list<TableSync> Toutes les tables, dans l'ordre des dependances. */
    public function tables(): array
    {
        return array_map(
            fn (string $classe) => new $classe,
            config('logialvia.sync.tables'),
        );
    }

    /** @return list<TableSync> Les tables que ce compte a le droit de LIRE. */
    public function tablesLisibles(User $utilisateur): array
    {
        return array_values(array_filter(
            $this->tables(),
            fn (TableSync $t) => $t->droitLecture() === null || $utilisateur->can($t->droitLecture()),
        ));
    }

    /** Marque de remise a zero courante (servie au tirage, exigee a l'envoi). */
    public function marqueCourante(): string
    {
        return ParametresEntreprise::courant()->marque_remise_a_zero;
    }

    // ---------------------------------------------------------------- Tirage

    /**
     * @return array<string, mixed>
     */
    public function tirage(User $utilisateur, ?string $since, ?string $until, int $page): array
    {
        // `until` fige l'ensemble des lignes pendant toute la pagination : sans lui, une
        // ecriture arrivee entre deux pages decalerait les pages et ferait sauter une ligne.
        $jusqua = $until !== null ? CarbonImmutable::parse($until)->utc() : CarbonImmutable::now('UTC');

        $depuis = $since !== null
            ? CarbonImmutable::parse($since)->utc()->subSeconds((int) config('logialvia.sync.recouvrement_secondes'))
            : null;

        $parPage = max(1, (int) config('logialvia.sync.lignes_par_page'));
        $dernierePage = 1;
        $tables = [];

        foreach ($this->tablesLisibles($utilisateur) as $table) {
            $requete = $table->requeteTirage($depuis, $jusqua);
            $total = (clone $requete)->count();
            $dernierePage = max($dernierePage, (int) ceil($total / $parPage));

            $tables[$table->nom()] = $requete
                ->offset(($page - 1) * $parPage)
                ->limit($parPage)
                ->get()
                ->map(fn (Model $ligne) => $table->exporter($ligne))
                ->all();
        }

        return [
            // Le curseur n'avance chez le poste qu'apres la DERNIERE page.
            'server_time' => $jusqua->format('Y-m-d\TH:i:s.u\Z'),
            'page' => $page,
            'last_page' => $dernierePage,
            'reset_mark' => $this->marqueCourante(),
            'tables' => $tables,
        ];
    }

    // ----------------------------------------------------------------- Envoi

    /**
     * @param  array<string, mixed>  $lot  table => lignes
     * @return array{statut: int, corps: array<string, mixed>}
     */
    public function envoi(User $utilisateur, string $deviceId, string $marque, array $lot): array
    {
        // Des donnees d'avant une remise a zero ressusciteraient : refus net.
        if ($marque !== $this->marqueCourante()) {
            return ['statut' => 409, 'corps' => [
                'message' => "Ce poste ne connaît pas la dernière remise à zéro. Il doit d'abord recevoir les données du serveur.",
                'code' => 'remise_a_zero_inconnue',
                'reset_mark' => $this->marqueCourante(),
            ]];
        }

        $reponse = DB::transaction(function () use ($utilisateur, $deviceId, $lot) {
            $reponse = [];
            $connues = [];

            foreach ($this->tables() as $table) {
                $connues[] = $table->nom();

                if (! array_key_exists($table->nom(), $lot)) {
                    continue;
                }

                $reponse[$table->nom()] = $this->absorberTable($utilisateur, $deviceId, $table, (array) $lot[$table->nom()]);
            }

            // Une table inconnue est refusee ligne par ligne, avec son motif.
            foreach ($lot as $nom => $lignes) {
                if (! in_array($nom, $connues, true)) {
                    $reponse[$nom] = $this->tableRefusee((array) $lignes, "Table inconnue du serveur : « $nom ».");
                }
            }

            return $reponse;
        }, 3);

        $this->journaliser($utilisateur, $deviceId, $reponse);

        return ['statut' => 200, 'corps' => $reponse];
    }

    /** @return array{accepted: list<string>, rejected: list<array>, ignored: list<array>} */
    private function absorberTable(User $utilisateur, string $deviceId, TableSync $table, array $lignes): array
    {
        if ($table->nature() === TableSync::REFERENTIEL) {
            // Le serveur gagne : on n'ecrit rien, on le dit, et c'est journalise.
            return [
                'accepted' => [],
                'rejected' => [],
                'ignored' => array_map(fn ($l) => [
                    'id' => $this->identifiant($l),
                    'motif' => 'Référentiel : le serveur fait foi, la modification du poste est ignorée.',
                ], $lignes),
            ];
        }

        $droit = $table->droitEcriture();
        if ($droit !== null && ! $utilisateur->can($droit)) {
            return $this->tableRefusee($lignes, "Droit insuffisant pour écrire dans « {$table->nom()} ».");
        }

        $resultat = ['accepted' => [], 'rejected' => [], 'ignored' => []];

        foreach ($lignes as $ligne) {
            $ligne = (array) $ligne;
            $motif = $table->absorber($deviceId, $ligne);

            if ($motif === null) {
                $resultat['accepted'][] = $ligne['id'];
            } else {
                $resultat['rejected'][] = ['id' => $this->identifiant($ligne), 'motif' => $motif];
            }
        }

        return $resultat;
    }

    /** @return array{accepted: list<string>, rejected: list<array>, ignored: list<array>} */
    private function tableRefusee(array $lignes, string $motif): array
    {
        return [
            'accepted' => [],
            'rejected' => array_map(fn ($l) => ['id' => $this->identifiant($l), 'motif' => $motif], $lignes),
            'ignored' => [],
        ];
    }

    private function identifiant(mixed $ligne): ?string
    {
        return is_array($ligne) && isset($ligne['id']) && is_string($ligne['id']) ? $ligne['id'] : null;
    }

    /** Un envoi qui contenait quelque chose laisse UNE trace ; un lot vide n'en laisse aucune. */
    private function journaliser(User $utilisateur, string $deviceId, array $reponse): void
    {
        $resume = [];
        foreach ($reponse as $nom => $r) {
            $n = [count($r['accepted']), count($r['rejected']), count($r['ignored'])];
            if (array_sum($n) > 0) {
                $resume[$nom] = ['acceptees' => $n[0], 'refusees' => $n[1], 'ignorees' => $n[2]];
            }
        }

        if ($resume !== []) {
            Audit::enregistrer('sync.push', $utilisateur, ['device_id' => $deviceId, 'tables' => $resume]);
        }
    }
}
