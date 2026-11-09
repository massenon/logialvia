<?php

namespace App\Services;

use App\Models\ParametresEntreprise;
use App\Models\Poste;
use App\Models\User;
use App\Support\Audit;
use App\Sync\MoteurSynchronisation;
use App\Sync\TableSync;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Remise a zero des donnees d'ACTIVITE (blueprint §6). Comptes, roles, referentiels et
 * journal d'audit sont preserves. Trois verrous : bascule activee, mot de
 * confirmation exact, audit. La nouvelle MARQUE fait refuser (409) tout envoi d'un
 * poste qui ne la connait pas : ses donnees d'avant la remise a zero ressusciteraient.
 */
class RemiseAZeroService
{
    public const MESSAGE_DESACTIVEE = "La remise à zéro est désactivée sur ce serveur.";
    public const MESSAGE_MOT = "Le mot de confirmation est incorrect : rien n'a été effacé.";

    public function executer(User $acteur, string $confirmation): ?string
    {
        if (! config('logialvia.remise_a_zero.activee')) {
            return self::MESSAGE_DESACTIVEE;
        }
        if (! hash_equals((string) config('logialvia.remise_a_zero.mot'), $confirmation)) {
            Audit::enregistrer('sync.remise_a_zero_refusee', $acteur);

            return self::MESSAGE_MOT;
        }

        $supprimees = [];
        DB::transaction(function () use ($acteur, &$supprimees) {
            foreach (app(MoteurSynchronisation::class)->tables() as $table) {
                if ($table->nature() === TableSync::FAIT) {
                    $supprimees[$table->nom()] = $table->requete()->getModel()->newQuery()->delete();
                }
            }

            ParametresEntreprise::courant()->forceFill(['marque_remise_a_zero' => 'rz-'.Str::uuid()])->save();
            // Les postes repartent d'un tirage complet ; les demandes en cours n'ont plus d'objet.
            Poste::query()->update(['curseur_tirage' => null, 'resync_demandee_le' => null]);
            DB::table('demandes_synchronisation')->delete();

            Audit::enregistrer('sync.remise_a_zero', $acteur, ['lignes_supprimees' => $supprimees]);
        });

        return null;
    }
}
