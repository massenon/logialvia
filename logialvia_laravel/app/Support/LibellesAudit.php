<?php

namespace App\Support;

/**
 * Libelles francais des actions du journal d'audit (`audit_logs.action`) et rendu SUR du detail.
 *
 * Une action inconnue (ajoutee plus tard par un autre ecran) s'affiche telle quelle : le journal
 * ne cache jamais rien. Le detail ne montre jamais un secret, meme si un appelant en avait mis un :
 * toute cle qui ressemble a un mot de passe, un jeton ou un secret est masquee a l'affichage.
 */
class LibellesAudit
{
    public const ACTIONS = [
        'web.login' => 'Connexion web',
        'web.mot_de_passe_change' => 'Mot de passe changé (web)',
        'api.login' => 'Appairage d\'un poste (connexion)',
        'api.mot_de_passe_change' => 'Mot de passe changé (poste)',
        'login.failed' => 'Connexion refusée (identifiants)',
        'login.refused_inactive' => 'Connexion refusée (compte désactivé)',
        'utilisateur.cree' => 'Compte créé',
        'utilisateur.modifie' => 'Compte modifié',
        'utilisateur.desactive' => 'Compte désactivé',
        'utilisateur.reactive' => 'Compte réactivé',
        'utilisateur.mdp_reinitialise' => 'Mot de passe réinitialisé',
        'utilisateur.archive' => 'Compte supprimé (archivé)',
        'utilisateur.restaure' => 'Compte restauré',
        'utilisateur.purge' => 'Compte effacé définitivement',
        'corbeille.restaure' => 'Élément restauré (corbeille)',
        'corbeille.purge' => 'Élément effacé définitivement (corbeille)',
        'sauvegarde.telechargee' => 'Sauvegarde logique téléchargée',
        'message_editeur.cree' => 'Message à l\'éditeur enregistré',
        'message_editeur.transmis' => 'Message à l\'éditeur marqué transmis',
        'message_editeur.supprime' => 'Message à l\'éditeur supprimé',
        'parametres.logo_televerse' => 'Logo / favicon mis à jour',
        'parametres.logo_retire' => 'Logo / favicon retiré',
        'sync.push' => 'Synchronisation : envoi d\'un poste',
        'sync.demande' => 'Synchronisation : demande de référentiel',
        'sync.demandes' => 'Synchronisation : demandes de référentiel',
        'sync.appairage_revoque' => 'Appairage d\'un poste révoqué',
        'sync.remise_a_zero' => 'Remise à zéro des données synchronisées',
        'sync.remise_a_zero_refusee' => 'Remise à zéro refusée',
        'sync.resynchronisation_demandee' => 'Resynchronisation demandée',
        'comptabilite.cloture_exercice' => 'Exercice clôturé',
        'comptabilite.decloture' => 'Exercice déclôturé',
    ];

    private const CLE_SECRETE = '/(password|mot_de_passe|passwd|secret|token|jeton(?!s_)|authorization|cookie)/i';

    public static function action(string $code): string
    {
        return self::ACTIONS[$code] ?? $code;
    }

    /** Module d'origine d'une action (colonne « Module » du journal personnel du Dart). */
    public static function module(string $code): string
    {
        return match (explode('.', $code)[0]) {
            'web', 'api', 'login' => 'Authentification',
            'utilisateur' => 'Administration',
            'sync' => 'Synchronisation',
            'comptabilite' => 'Comptabilité',
            'corbeille', 'sauvegarde', 'parametres' => 'Paramètres',
            'message_editeur' => 'Compte',
            default => $code,
        };
    }

    /** @return list<string> « cle : valeur », secrets masques. */
    public static function detail(?array $detail): array
    {
        $lignes = [];
        foreach ($detail ?? [] as $cle => $valeur) {
            if (is_array($valeur)) {
                $valeur = json_encode($valeur, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            } elseif (is_bool($valeur)) {
                $valeur = $valeur ? 'oui' : 'non';
            } elseif ($valeur === null) {
                $valeur = '—';
            }
            $lignes[] = $cle.' : '.(preg_match(self::CLE_SECRETE, (string) $cle) ? '••••' : (string) $valeur);
        }

        return $lignes;
    }
}
