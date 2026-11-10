<?php

namespace App\Sync;

use App\Models\User;
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

    /** Poste nul du web (`Catalogue::POSTE_WEB`) : les ecrans du serveur ecrivent par les memes absorbeurs. */
    private const POSTE_WEB = '00000000-0000-0000-0000-000000000000';

    /** Code stable du dernier refus de cette table (`null` : refus ordinaire, sans code). */
    private ?string $codeRefus = null;

    abstract public function nom(): string;

    /** Code stable (`droit_insuffisant`, `horloge_en_avance`) du dernier refus rendu par [absorber]. */
    public function codeRefus(): ?string
    {
        return $this->codeRefus;
    }

    public function reinitialiserCodeRefus(): void
    {
        $this->codeRefus = null;
    }

    /** Pose le code du refus et rend son motif. */
    protected function refuserAvecCode(string $code, string $motif): string
    {
        $this->codeRefus = $code;

        return $motif;
    }

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

    /**
     * Ce compte peut-il LIRE cette table ? Par defaut : le droit de lecture ; une table
     * partagee par plusieurs metiers (les intrants : stocks, achats, elevage) surcharge.
     */
    public function peutLire(User $utilisateur): bool
    {
        return $this->droitLecture() === null || $utilisateur->can($this->droitLecture());
    }

    /** Ce compte peut-il ECRIRE un fait dans cette table ? Meme principe. */
    public function peutEcrire(User $utilisateur): bool
    {
        return $this->droitEcriture() === null || $utilisateur->can($this->droitEcriture());
    }

    /** Vrai si le compte a l'un de ces droits. */
    protected function aUnDesDroits(User $utilisateur, array $droits): bool
    {
        foreach ($droits as $droit) {
            if ($utilisateur->can($droit)) {
                return true;
            }
        }

        return false;
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
     * Controles croises d'une ligne DEJA valide champ par champ (coherence entre champs,
     * existence d'une ligne referencee). Par defaut aucun. Renvoie le motif du refus.
     */
    protected function controler(array $ligne): ?string
    {
        return null;
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

        // Garde d'horloge (`47g_`) : un instant de saisie dans le futur gelerait la ligne. Les ecrans
        // du web (poste nul) y echappent : ils datent leur ecriture APRES la ligne qu'ils remplacent
        // (`max(maintenant, existante + 1 µs)`), y compris une ligne deja gelee par une horloge en avance.
        if ($deviceId !== self::POSTE_WEB && ($motif = GardeHorloge::controler($ligne)) !== null) {
            return $this->refuserAvecCode(GardeHorloge::CODE, $motif);
        }

        // Controles croises (plusieurs champs, ou une ligne d'une autre table).
        if (($motif = $this->controler($ligne)) !== null) {
            return $motif;
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
