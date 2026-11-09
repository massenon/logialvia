<?php

namespace App\Sync\Tables;

use App\Models\FicheJournee;
use App\Support\FilieresElevage;
use App\Support\UuidDeterministe;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Validation\Rule;

/**
 * Fiche journaliere d'elevage : fait saisi au poste, DERNIER ECRIVAIN GAGNE, LIGNE ENTIERE
 * (`46a_`).
 *
 * Identite : (filiere, jour). L'UUID est DETERMINISTE de cette cle et le serveur le
 * recalcule : deux postes qui saisissent le meme jour ecrivent la meme ligne ; la plus
 * recente (instant de SAISIE, strictement) l'emporte en bloc. Jamais de melange champ par
 * champ : les effectifs sont calcules a partir de la veille, melanger deux saisies
 * produirait un effectif qu'aucun poste n'a calcule.
 *
 * Le serveur n'applique aucune cascade : la ligne arrive avec ses valeurs calculees par le
 * poste qui l'a saisie, les jours suivants arrivent par leurs propres lignes.
 *
 * DIVERGENCE (`47e_`) : « dernier ecrivain gagne » ne perd plus JAMAIS une saisie en silence.
 * Le poste envoie `base_updated_at` (la version dont sa fiche est partie). Si elle n'est pas la
 * version courante, que le contenu differe et que l'auteur est un autre appareil, les deux
 * saisies ont eu lieu sans se voir : la plus recente reste COURANTE, l'autre est conservee dans
 * `variantes` (redistribuee a tous) jusqu'a ce qu'une personne choisisse. Choisir =
 * renvoyer la fiche avec `resolution: true` : les variantes sont alors effacees.
 */
class FichesJourneeTable extends TableSync
{
    /** Entiers obligatoires (>= 0). */
    public const ENTIERS = [
        'achat', 'ne', 'vente',
        'mort_cat1', 'mort_cat2', 'mort_cat3',
        'don_cat1', 'don_cat2', 'don_cat3',
        'effectif', 'eff_cat1_day', 'eff_cat2_day', 'eff_cat3_day',
    ];

    /** Entiers facultatifs (`null` ou >= 0). */
    public const ENTIERS_FACULTATIFS = [
        'mort_cat4', 'don_cat4', 'eff_cat4_day',
        'srh', 'ts', 'stock_final_oeufs',
        'oeufs_pondus', 'oeufs_casses', 'sorties_plateaux',
        'poids_general_g',
    ];

    public function nom(): string
    {
        return 'fiche_journee';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return FicheJournee::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-elevage';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-elevage';
    }

    public function colonnesEcrites(): array
    {
        return [
            'espece', 'date', ...self::ENTIERS, ...self::ENTIERS_FACULTATIFS,
            'traitement_obs', 'traitement_valide', 'is_recorded',
        ];
    }

    public function regles(): array
    {
        $regles = [
            'espece' => ['required', Rule::in(FilieresElevage::identifiants())],
            'date' => ['required', 'date_format:Y-m-d'],
        ];
        foreach (self::ENTIERS as $champ) {
            $regles[$champ] = ['required', 'integer:strict', 'min:0'];
        }
        foreach (self::ENTIERS_FACULTATIFS as $champ) {
            $regles[$champ] = ['nullable', 'integer:strict', 'min:0'];
        }
        $regles['traitement_obs'] = ['nullable', 'string', 'max:2000'];
        $regles['traitement_valide'] = ['required', 'boolean:strict'];
        $regles['is_recorded'] = ['required', 'boolean:strict'];
        $regles['base_updated_at'] = ['nullable', 'date'];
        $regles['resolution'] = ['nullable', 'boolean:strict'];

        return $regles;
    }

    public function messages(): array
    {
        $messages = [
            'id.uuid' => "L'identifiant de la fiche doit être un UUID.",
            'espece.required' => 'La filière de la fiche est obligatoire.',
            'espece.in' => 'La filière « :input » est inconnue.',
            'date.required' => 'La date de la fiche est obligatoire.',
            'date.date_format' => 'La date de la fiche est invalide.',
            'traitement_obs.max' => "L'observation de traitement est trop longue.",
            'traitement_valide.required' => "L'indicateur « traitement_valide » est obligatoire.",
            'traitement_valide.boolean' => "L'indicateur « traitement_valide » doit être vrai ou faux.",
            'is_recorded.required' => "L'indicateur « is_recorded » est obligatoire.",
            'is_recorded.boolean' => "L'indicateur « is_recorded » doit être vrai ou faux.",
            'base_updated_at.date' => 'La version de départ de la fiche est invalide.',
            'resolution.boolean' => "L'indicateur « resolution » doit être vrai ou faux.",
        ];
        foreach ([...self::ENTIERS, ...self::ENTIERS_FACULTATIFS] as $champ) {
            $messages["$champ.required"] = "La valeur de « $champ » est obligatoire.";
            $messages["$champ.integer"] = "La valeur de « $champ » doit être un entier positif ou nul.";
            $messages["$champ.min"] = "La valeur de « $champ » doit être un entier positif ou nul.";
        }

        return $messages;
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        // L'identite d'une fiche est sa cle (filiere, jour) : un UUID qui n'en est pas le
        // calcul romprait la convergence entre postes. Controle fait seulement quand la
        // cle est lisible ; sinon la validation de la classe mere dit le vrai motif.
        if (is_string($ligne['id'] ?? null) && \Illuminate\Support\Str::isUuid($ligne['id']) && FilieresElevage::existe($ligne['espece'] ?? null)
            && $this->jourValide($ligne['date'] ?? null)
            && $ligne['id'] !== UuidDeterministe::ficheJournee($ligne['espece'], $ligne['date'])) {
            return "L'identifiant de la fiche ne correspond pas à sa filière et à sa date.";
        }

        // LIGNE ENTIERE : une colonne facultative absente est ecrite a `null`, jamais
        // laissee a sa valeur precedente (sinon deux saisies se melangeraient).
        foreach (self::ENTIERS_FACULTATIFS as $champ) {
            $ligne[$champ] = $ligne[$champ] ?? null;
        }
        $ligne['traitement_obs'] = $ligne['traitement_obs'] ?? null;

        $existante = is_string($ligne['id'] ?? null) ? $this->requete()->find($ligne['id']) : null;
        $avant = $existante === null ? null : [
            'contenu' => $this->contenu($existante->attributesToArray()),
            'device_id' => $existante->device_id,
            'updated_at' => CarbonImmutable::parse($existante->updated_at)->utc(),
        ];

        $motif = parent::absorber($deviceId, $ligne);
        if ($motif !== null || $avant === null) {
            return $motif;
        }

        $saisie = CarbonImmutable::parse($ligne['updated_at'])->utc();
        $resolution = ($ligne['resolution'] ?? false) === true;
        $entrant = $this->contenu($ligne);
        $plusRecente = $saisie->greaterThan($avant['updated_at']);

        if ($resolution) {
            // Le choix d'une personne : seule une ecriture PLUS RECENTE que la version
            // courante est appliquee (par la classe mere), et elle efface les variantes.
            if ($plusRecente) {
                $this->requete()->whereKey($ligne['id'])->update(['variantes' => null]);
            }

            return null;
        }

        if ($entrant === $avant['contenu'] || $avant['device_id'] === $deviceId) {
            return null; // rejeu, ou suite d'un meme appareil : aucune divergence
        }
        $base = isset($ligne['base_updated_at']) ? CarbonImmutable::parse($ligne['base_updated_at'])->utc() : null;
        if ($base !== null && $base->equalTo($avant['updated_at'])) {
            return null; // le poste avait VU la version courante : modification successive
        }

        // Divergence : la perdante est conservee, jamais ecartee.
        $perdante = $plusRecente
            ? ['device_id' => $avant['device_id'], 'updated_at' => $avant['updated_at'], 'contenu' => $avant['contenu']]
            : ['device_id' => $deviceId, 'updated_at' => $saisie, 'contenu' => $entrant];
        $modele = $this->requete()->find($ligne['id']);
        $variantes = $modele->variantes ?? [];
        foreach ($variantes as $v) {
            if (($v['device_id'] ?? null) === $perdante['device_id']
                && CarbonImmutable::parse($v['updated_at'])->equalTo($perdante['updated_at'])
                && ($v['contenu'] ?? null) === $perdante['contenu']) {
                return null; // deja conservee (rejeu)
            }
        }
        $variantes[] = [
            'device_id' => $perdante['device_id'],
            'updated_at' => $perdante['updated_at']->format('Y-m-d\TH:i:s.u\Z'),
            'contenu' => $perdante['contenu'],
        ];
        // `serveur_modifie_le` avance : la divergence est redistribuee a tous les postes.
        $modele->forceFill([
            'variantes' => $variantes,
            'serveur_modifie_le' => CarbonImmutable::now('UTC'),
        ])->save();

        return null;
    }

    /**
     * Le CONTENU d'une fiche (ce qu'une personne a saisi ou que le poste a calcule), normalise
     * pour etre compare : entiers en entiers, booleens en booleens, absent = `null`.
     *
     * @return array<string, mixed>
     */
    public function contenu(array $ligne): array
    {
        $contenu = [];
        foreach ($this->colonnesEcrites() as $colonne) {
            $valeur = $ligne[$colonne] ?? null;
            if (in_array($colonne, [...self::ENTIERS, ...self::ENTIERS_FACULTATIFS], true) && $valeur !== null) {
                $valeur = (int) $valeur;
            } elseif (in_array($colonne, ['traitement_valide', 'is_recorded'], true)) {
                $valeur = (bool) $valeur;
            } elseif ($colonne === 'date' && is_string($valeur)) {
                $valeur = substr($valeur, 0, 10);
            }
            $contenu[$colonne] = $valeur;
        }

        return $contenu;
    }

    private function jourValide(mixed $jour): bool
    {
        if (! is_string($jour)) {
            return false;
        }
        $analyse = \DateTime::createFromFormat('!Y-m-d', $jour);

        return $analyse !== false && $analyse->format('Y-m-d') === $jour;
    }
}
