<?php

namespace App\Sync;

use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;

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

    /** Colonnes qu'un poste peut ecrire (le reste est derive ou pose par le serveur). */
    public function colonnesEcrites(): array
    {
        return [];
    }

    /** Regles de validation d'une ligne poussee. */
    public function regles(): array
    {
        return [];
    }

    public function messages(): array
    {
        return [];
    }

    /**
     * Absorbe UNE ligne poussee par un poste (fait). Par defaut : insertion, ou
     * dernier ecrivain gagne a l'instant de SAISIE ; un rejeu est accepte sans rien
     * changer. Une table dont l'unite n'est pas une ligne plate (une vente et ses
     * lignes) surcharge cette methode.
     *
     * @return string|null Le motif du refus, ou `null` si la ligne est acceptee.
     */
    public function absorber(string $deviceId, array $ligne): ?string
    {
        $validateur = Validator::make($ligne, array_merge([
            'id' => ['required', 'uuid'],
            'updated_at' => ['required', 'date'],
        ], $this->regles()), array_merge([
            'id.required' => "L'identifiant de la ligne est obligatoire.",
            'id.uuid' => "L'identifiant de la ligne doit être un UUID.",
            'updated_at.required' => 'La date de saisie de la ligne est obligatoire.',
            'updated_at.date' => 'La date de saisie de la ligne est invalide.',
        ], $this->messages()));

        if ($validateur->fails()) {
            return $validateur->errors()->first();
        }

        $saisie = CarbonImmutable::parse($ligne['updated_at'])->utc();
        $donnees = array_intersect_key($ligne, array_flip($this->colonnesEcrites()));
        $existante = $this->requete()->find($ligne['id']);

        if ($existante === null) {
            $this->requete()->getModel()->newInstance()->forceFill($donnees + [
                'id' => $ligne['id'],
                'device_id' => $deviceId,
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ])->save();

            return null;
        }

        if ($saisie->greaterThan($existante->updated_at)) {
            $existante->forceFill($donnees + [
                'device_id' => $deviceId,
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ])->save();
        }

        return null;
    }
}
