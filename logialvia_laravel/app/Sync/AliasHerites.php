<?php

namespace App\Sync;

use App\Support\FilieresElevage;
use App\Support\UuidDeterministe;

/**
 * Alias HERITES de la synchronisation (DV-22) : la filiere `bovins` est devenue `ovins` a la demande du client.
 *
 * Un poste qui n'a pas encore migre (schema v50) peut encore envoyer `bovins` : filiere d'une fiche, d'un compteur,
 * d'une bande, d'un soin ou d'une ligne de vente, module ou espece d'une demande de referentiel, categorie
 * « Élevage bovin ». Le serveur NORMALISE a l'entree (`bovins` -> `ovins`) et n'ecrit jamais l'ancien nom.
 *
 * Les identifiants DETERMINISTES (fiche journaliere, compteur de ventes) se calculent a partir de la filiere : un poste
 * ancien envoie l'UUID calcule avec `bovins`. Il est recalcule avec `ovins` (le serveur verifie ensuite l'UUID comme
 * d'habitude) ; l'accuse de reception, lui, reprend l'identifiant ENVOYE par le poste. Un identifiant qui n'est pas
 * celui de sa cle reste tel quel et sera refuse par la table comme avant.
 *
 * Les valeurs d'origine du stade jeune (`Veau`) deviennent `Agneau` pour un bareme envoye sous l'ancien nom.
 */
final class AliasHerites
{
    /** Ancien identifiant de filiere/module => identifiant actuel. */
    public const ESPECES = ['bovins' => 'ovins'];

    /** Ancienne categorie de produit => categorie actuelle. */
    public const CATEGORIES = ['Élevage bovin' => 'Élevage ovin'];

    /** Stade jeune d'un bareme envoye sous l'ancien nom. */
    private const STADES_BOVINS = ['Veau' => 'Agneau'];

    /** `bovins` => `ovins` ; toute autre valeur (y compris non textuelle) est rendue telle quelle. */
    public static function espece(mixed $valeur): mixed
    {
        return is_string($valeur) && array_key_exists($valeur, self::ESPECES) ? self::ESPECES[$valeur] : $valeur;
    }

    /**
     * Ligne poussee par un poste (fait), normalisee. Seuls les champs connus sont touches.
     *
     * @param  array<string, mixed>  $ligne
     * @return array<string, mixed>
     */
    public static function normaliserLigne(string $table, array $ligne, string $deviceId): array
    {
        $ancienne = $ligne['espece'] ?? null;
        $herite = is_string($ancienne) && array_key_exists($ancienne, self::ESPECES);

        if ($herite) {
            $ligne['espece'] = self::ESPECES[$ancienne];

            $jour = $ligne['date'] ?? null;
            if (is_string($jour) && is_string($ligne['id'] ?? null)) {
                if ($table === 'fiche_journee' && $ligne['id'] === UuidDeterministe::ficheJournee($ancienne, $jour)) {
                    $ligne['id'] = UuidDeterministe::ficheJournee($ligne['espece'], $jour);
                }
                if ($table === 'fiche_ventes_jour' && $ligne['id'] === UuidDeterministe::ventesJour($ancienne, $jour, $deviceId)) {
                    $ligne['id'] = UuidDeterministe::ventesJour($ligne['espece'], $jour, $deviceId);
                }
            }
        }

        // Une vente porte l'espece sur chacune de ses lignes.
        if (is_array($ligne['lignes'] ?? null)) {
            $ligne['lignes'] = array_map(function ($l) {
                if (is_array($l) && array_key_exists('espece', $l)) {
                    $l['espece'] = self::espece($l['espece']);
                }

                return $l;
            }, $ligne['lignes']);
        }

        return $ligne;
    }

    /**
     * Demande de referentiel normalisee : module, espece (bareme, taux, echeance, produit), stade jeune
     * et categorie de produit. L'identifiant d'un bareme, d'un taux ou d'une echeance n'est recalcule que
     * s'il etait le deterministe de l'ancienne cle (une ligne saisie, UUID aleatoire, garde le sien).
     *
     * @param  array<string, mixed>  $demande
     * @return array<string, mixed>
     */
    public static function normaliserDemande(array $demande): array
    {
        $donnees = $demande['donnees'] ?? null;
        if (! is_array($donnees)) {
            return $demande;
        }

        if (($donnees['module_id'] ?? null) !== null) {
            $donnees['module_id'] = self::espece($donnees['module_id']);
        }

        $ancienne = $donnees['espece'] ?? null;
        if (is_string($ancienne) && array_key_exists($ancienne, self::ESPECES)) {
            $nouvelle = self::ESPECES[$ancienne];
            $donnees['espece'] = $nouvelle;
            $id = $donnees['id'] ?? null;

            if (isset($donnees['stade']) && is_string($donnees['stade'])) {
                $stade = $donnees['stade'];
                $stadeNouveau = self::STADES_BOVINS[$stade] ?? $stade;
                if ($id === FilieresElevage::idBareme($ancienne, $stade)) {
                    $donnees['id'] = FilieresElevage::idBareme($nouvelle, $stadeNouveau);
                }
                $donnees['stade'] = $stadeNouveau;
            } elseif (isset($donnees['poids_min_g']) && is_int($donnees['poids_min_g'])
                && $id === FilieresElevage::idTaux($ancienne, $donnees['poids_min_g'])) {
                $donnees['id'] = FilieresElevage::idTaux($nouvelle, $donnees['poids_min_g']);
            } elseif (isset($donnees['jour_cycle'], $donnees['traitement'], $donnees['produit'])
                && $id === FilieresElevage::idEcheance($ancienne, (int) $donnees['jour_cycle'], (string) $donnees['traitement'], (string) $donnees['produit'])) {
                $donnees['id'] = FilieresElevage::idEcheance($nouvelle, (int) $donnees['jour_cycle'], (string) $donnees['traitement'], (string) $donnees['produit']);
            }
        }

        if (isset($donnees['cat']) && is_string($donnees['cat']) && array_key_exists($donnees['cat'], self::CATEGORIES)) {
            $donnees['cat'] = self::CATEGORIES[$donnees['cat']];
        }

        $demande['donnees'] = $donnees;

        return $demande;
    }
}
