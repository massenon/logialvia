<?php

namespace App\Sync;

use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * Une table synchronisee (`46_` §2). Deux natures :
 *
 *  - `referentiel` : le serveur gagne, le poste recoit ; un envoi du poste est
 *    IGNORE et journalise ;
 *  - `fait` : saisi au poste, rejoue tel quel au serveur (dernier ecrivain gagne
 *    par UUID), puis redescend vers les autres postes.
 */
abstract class TableSync
{
    public const REFERENTIEL = 'referentiel';

    public const FAIT = 'fait';

    abstract public function nom(): string;

    abstract public function nature(): string;

    /** @return class-string<Model> */
    abstract protected function modele(): string;

    /** Colonne du CURSEUR de tirage (jamais l'horloge du poste). */
    abstract public function colonneCurseur(): string;

    /** Droit de lecture ; `null` = tout compte authentifie. */
    public function droitLecture(): ?string
    {
        return null;
    }

    /** Droit d'ecriture d'un fait ; sans objet pour un referentiel. */
    public function droitEcriture(): ?string
    {
        return null;
    }

    public function requete(): Builder
    {
        return $this->modele()::query();
    }

    /** Lignes dont le curseur est dans `[depuis, jusqua]`, dans un ordre STABLE. */
    public function requeteTirage(?CarbonInterface $depuis, CarbonInterface $jusqua): Builder
    {
        $colonne = $this->colonneCurseur();
        $requete = $this->requete()->where($colonne, '<=', $jusqua->format('Y-m-d H:i:s.u'));

        if ($depuis !== null) {
            $requete->where($colonne, '>=', $depuis->format('Y-m-d H:i:s.u'));
        }

        return $requete->orderBy($colonne)->orderBy('id');
    }

    /** @return array<string, mixed> La ligne telle qu'elle part vers un poste. */
    public function exporter(Model $ligne): array
    {
        $donnees = [];

        foreach ($ligne->attributesToArray() as $cle => $valeur) {
            $donnees[$cle] = $valeur;
        }

        return $donnees;
    }
}
