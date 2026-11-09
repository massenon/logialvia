<?php

namespace App\Services;

use App\Models\User;
use App\Support\Audit;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Sauvegarde LOGIQUE des donnees du serveur (doc 47u §5) : un fichier JSON, telechargeable par
 * l'administrateur, qui reprend les tables metier ligne a ligne. Ce n'est PAS une copie de la base
 * (le poste, lui, copie son fichier SQLite) et le web ne sait PAS la restaurer : elle sert a garder
 * une photo des donnees, ou a la relire hors du serveur.
 *
 * SANS secret : jamais de mot de passe ni d'empreinte, jamais de jeton de poste, de session, de cache
 * ni de file d'attente. Les comptes n'y figurent que par nom, identifiant, e-mail, activite.
 */
class SauvegardeLogiqueService
{
    /** Tables techniques ou secretes : jamais sauvegardees. */
    public const EXCLUES = [
        'migrations', 'password_reset_tokens', 'sessions', 'cache', 'cache_locks', 'jobs', 'job_batches',
        'failed_jobs', 'personal_access_tokens',
    ];

    /** Colonnes secretes : retirees de toute table. */
    public const COLONNES_SECRETES = ['password', 'remember_token', 'token'];

    /** @return list<string> */
    public static function tables(): array
    {
        return collect(Schema::getTableListing(schemaQualified: false))
            ->reject(fn (string $t) => in_array($t, self::EXCLUES, true) || str_starts_with($t, 'sqlite_'))
            ->sort()->values()->all();
    }

    public static function nomDeFichier(): string
    {
        return 'logialvia-sauvegarde-logique-'.now('UTC')->format('Ymd-His').'.json';
    }

    /** Telechargement en flux (une table a la fois, une ligne a la fois). */
    public function telecharger(User $acteur): StreamedResponse
    {
        abort_unless($acteur->can('manage-parametres') && $acteur->hasRole('admin'), 403);

        $tables = self::tables();
        $compte = [];
        foreach ($tables as $t) {
            $compte[$t] = DB::table($t)->count();
        }
        Audit::enregistrer('sauvegarde.telechargee', $acteur, ['tables' => count($tables), 'lignes' => array_sum($compte)]);

        return response()->streamDownload(function () use ($tables, $compte) {
            $options = JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE;
            echo '{"application":"LogiALVIA (serveur)","type":"sauvegarde_logique","genere_le":'
                .json_encode(now('UTC')->format('Y-m-d\TH:i:s\Z')).',"restauration":"non prise en charge par le web","lignes_par_table":'
                .json_encode($compte, $options).',"tables":{';
            foreach ($tables as $i => $table) {
                echo ($i > 0 ? ',' : '').json_encode($table).':[';
                $premiere = true;
                foreach (DB::table($table)->cursor() as $ligne) {
                    $ligne = array_diff_key((array) $ligne, array_flip(self::COLONNES_SECRETES));
                    echo ($premiere ? '' : ',').json_encode($ligne, $options);
                    $premiere = false;
                }
                echo ']';
            }
            echo '}}';
        }, self::nomDeFichier(), ['Content-Type' => 'application/json; charset=utf-8']);
    }
}
