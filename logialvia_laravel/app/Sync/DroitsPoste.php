<?php

namespace App\Sync;

use App\Models\User;

/**
 * Les DROITS d'un compte, tels que le poste les apprend (`47g_`) : la reponse de connexion,
 * `GET /api/auth/me` et chaque tirage les portent. Le poste ne PROPOSE et ne PUSHE que ce
 * que son compte a le droit d'ecrire : le refus serveur (`droit_insuffisant`) reste un
 * filet de securite, jamais le fonctionnement normal.
 *
 * La reponse ne contient JAMAIS de secret : nom du compte, roles, liste des droits, noms de
 * tables, types de demandes.
 */
final class DroitsPoste
{
    /** Code stable du refus pour droit insuffisant (le poste le reconnait, jamais le texte). */
    public const CODE_REFUS = 'droit_insuffisant';

    /**
     * @return array{
     *     compte: string, nom: string, roles: list<string>, permissions: list<string>,
     *     tables_ecrites: list<string>, tables_lues: list<string>, demandes: list<string>
     * }
     */
    public static function pour(User $utilisateur): array
    {
        $ecrites = [];
        $lues = [];

        foreach ((new MoteurSynchronisation)->tables() as $table) {
            if ($table->peutLire($utilisateur)) {
                $lues[] = $table->nom();
            }
            // Un referentiel n'est jamais ecrit par push (le serveur l'ignore) : il passe par les demandes.
            if ($table->nature() === TableSync::FAIT && $table->peutEcrire($utilisateur)) {
                $ecrites[] = $table->nom();
            }
        }

        return [
            'compte' => (string) $utilisateur->username,
            'nom' => (string) $utilisateur->name,
            'roles' => $utilisateur->getRoleNames()->values()->all(),
            'permissions' => array_values(array_filter(
                config('logialvia.permissions'),
                fn (string $droit) => $utilisateur->can($droit),
            )),
            'tables_ecrites' => $ecrites,
            'tables_lues' => $lues,
            'demandes' => DemandesReferentiel::typesPermis($utilisateur),
        ];
    }
}
