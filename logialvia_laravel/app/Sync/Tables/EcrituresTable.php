<?php

namespace App\Sync\Tables;

use App\Models\EcritureComptable;
use App\Models\PieceComptable;
use App\Models\PlanComptable;
use App\Models\User;
use App\Services\Comptabilite\Verrous;
use App\Support\PlanSyscohada;
use App\Sync\DroitsPoste;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;

/**
 * Ecritures comptables : des FAITS IMMUABLES, une PIECE (partie double) a la fois.
 *
 *  - la piece et ses lignes forment UN lot : acceptees ou refusees ensemble (dans la
 *    transaction du lot), servies ensemble au tirage (`lignes` imbriquees) ;
 *  - le serveur verifie l'EQUILIBRE (debit = credit, tolerance 0,01) et la partie double
 *    de chaque ligne ; une piece desequilibree est refusee ENTIERE, avec son motif ;
 *  - double verrouillage (exercice cloture, mois cloture) verifie ICI, pour tous les postes ;
 *  - une piece acceptee ne change JAMAIS : rejouee, elle est acceptee sans rien changer ;
 *    se corriger, c'est la CONTREPASSER (`contrepasse_de`), verifiee ligne a ligne ;
 *  - le serveur n'engendre aucune ecriture a partir d'une vente ou d'un achat recus : le
 *    poste qui a vendu envoie SA piece, et c'est elle qui compte (ni double comptage, ni trou).
 *
 * ## Droits
 * Lecture : `view-comptabilite`. Ecriture : une piece MANUELLE exige `manage-comptabilite` ;
 * une piece AUTOMATIQUE (`vente_ref`, `achat_ref`) est aussi acceptee de celui qui vend
 * (`manage-ventes`) ou achete (`manage-achats`) : le poste de caisse genere ses ecritures.
 */
class EcrituresTable extends TableSync
{
    public const JOURNAUX = ['VT', 'AC', 'CA', 'OD'];

    /**
     * Journaux ENGENDRES par la cloture annuelle (`47c_`) : jamais acceptes d'un poste, seulement
     * du serveur lui-meme (`pourCloture`), pour l'administratrice (`close-fiscal-year`).
     */
    public const JOURNAUX_DE_CLOTURE = ['CL', 'AN'];

    private ?User $utilisateur = null;

    private bool $pourCloture = false;

    public function nom(): string
    {
        return 'ecriture_comptable';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return PieceComptable::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-comptabilite';
    }

    public function peutEcrire(User $utilisateur): bool
    {
        $this->pourUtilisateur($utilisateur);

        return $this->aUnDesDroits($utilisateur, ['manage-comptabilite', 'manage-ventes', 'manage-achats']);
    }

    /** Pieces de cloture / d'a-nouveaux ecrites par le serveur lui-meme (journaux CL et AN). */
    public function pourCloture(): static
    {
        $this->pourCloture = true;

        return $this;
    }

    /** Qui ecrit : le moteur le fixe par `peutEcrire`, le web par cet appel explicite. */
    public function pourUtilisateur(User $utilisateur): static
    {
        $this->utilisateur = $utilisateur;

        return $this;
    }

    public function exporter(Model $ligne): array
    {
        $donnees = parent::exporter($ligne);
        $donnees['lignes'] = $ligne->lignes()->orderBy('id')->get()
            ->map(fn (EcritureComptable $l) => $l->attributesToArray())
            ->all();
        // Toute piece du serveur est dans le plan courant (la migration a renumerote l'historique).
        $donnees['plan_version'] = PlanSyscohada::VERSION;

        return $donnees;
    }

    /** Motif de refus d'un lot d'un poste qui n'est pas sur le plan comptable courant (garde de version, `47p_`). */
    public const MOTIF_ANCIEN_PLAN = "Ce poste utilise l'ancien plan comptable : mettez-le à jour avant d'envoyer des écritures.";

    public function absorber(string $deviceId, array $ligne): ?string
    {
        // GARDE DE VERSION : un poste non migre enverrait d'anciens numeros (601/602 inverses !) qui seraient
        // silencieusement mal comptabilises. Sans la bonne `plan_version`, le lot est refuse ENTIER.
        if (($ligne['plan_version'] ?? null) !== PlanSyscohada::VERSION) {
            return self::MOTIF_ANCIEN_PLAN;
        }
        $v = Validator::make($ligne, [
            'id' => ['required', 'uuid'],
            'numero_piece' => ['nullable', 'string', 'max:60'],
            'date_ecriture' => ['required', 'date'],
            'exercice_annee' => ['required', 'integer'],
            'journal_code' => ['required', 'string', 'in:'.implode(',', $this->pourCloture ? [...self::JOURNAUX, ...self::JOURNAUX_DE_CLOTURE] : self::JOURNAUX)],
            'vente_ref' => ['nullable', 'string', 'max:60'],
            'achat_ref' => ['nullable', 'string', 'max:60'],
            'contrepasse_de' => ['nullable', 'uuid'],
            'plan_version' => ['required', 'integer'],
            'updated_at' => ['required', 'date'],
            'lignes' => ['required', 'array', 'min:2'],
            'lignes.*.id' => ['required', 'uuid'],
            'lignes.*.numero_compte' => ['required', 'string', 'max:20'],
            'lignes.*.debit' => ['required', 'numeric', 'min:0'],
            'lignes.*.credit' => ['required', 'numeric', 'min:0'],
            'lignes.*.libelle' => ['required', 'string', 'max:255'],
            'lignes.*.axe_analytique' => ['nullable', 'string', 'max:80'],
        ], [
            'id.required' => "L'identifiant de la pièce est obligatoire.",
            'id.uuid' => "L'identifiant de la pièce doit être un UUID.",
            'date_ecriture.required' => 'La date de la pièce est obligatoire.',
            'date_ecriture.date' => 'La date de la pièce est invalide.',
            'exercice_annee.required' => "L'exercice de la pièce est obligatoire.",
            'journal_code.in' => 'Le code journal est inconnu (VT, AC, CA ou OD).',
            'updated_at.required' => 'La date de saisie de la pièce est obligatoire.',
            'lignes.required' => 'Une pièce comptable doit avoir au moins deux lignes.',
            'lignes.min' => 'Une pièce comptable doit avoir au moins deux lignes.',
            'lignes.*.id.uuid' => "L'identifiant d'une ligne doit être un UUID.",
            'lignes.*.numero_compte.required' => 'Le compte est obligatoire.',
            'lignes.*.debit.min' => 'Les montants ne peuvent être négatifs.',
            'lignes.*.credit.min' => 'Les montants ne peuvent être négatifs.',
            'lignes.*.libelle.required' => 'Le libellé est obligatoire.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if ($this->utilisateur === null) {
            return "Utilisateur inconnu : l'écriture ne peut pas être rattachée à un droit.";
        }

        // Immuable : une piece deja connue est acceptee sans rien changer (rejeu).
        if (PieceComptable::query()->whereKey($ligne['id'])->exists()) {
            return null;
        }

        // Droit selon la nature de la piece. Une piece de cloture exige la cloture annuelle.
        $manuelle = empty($ligne['vente_ref']) && empty($ligne['achat_ref']);
        $droits = $this->pourCloture ? ['close-fiscal-year'] : ['manage-comptabilite'];
        if (! empty($ligne['vente_ref'])) {
            $droits[] = 'manage-ventes';
        }
        if (! empty($ligne['achat_ref'])) {
            $droits[] = 'manage-achats';
        }
        if (! $this->aUnDesDroits($this->utilisateur, $droits)) {
            return $this->refuserAvecCode(DroitsPoste::CODE_REFUS, $manuelle
                ? 'Droit insuffisant : une écriture manuelle exige de gérer la comptabilité.'
                : 'Droit insuffisant pour enregistrer cette écriture.');
        }

        // Partie double : une ligne porte un debit OU un credit, jamais les deux.
        $debit = 0.0;
        $credit = 0.0;
        $comptes = [];
        foreach ($ligne['lignes'] as $l) {
            $d = (float) $l['debit'];
            $c = (float) $l['credit'];
            if ($d > 0 && $c > 0) {
                return 'Une écriture porte un débit OU un crédit, jamais les deux.';
            }
            if ($d == 0.0 && $c == 0.0) {
                return 'Saisissez un montant au débit ou au crédit.';
            }
            $debit += $d;
            $credit += $c;
            $comptes[$l['numero_compte']] = true;
        }

        // L'EQUILIBRE est verifie par le serveur, pour tous les postes.
        if (abs($debit - $credit) > Verrous::TOLERANCE) {
            return sprintf(
                'Pièce déséquilibrée : débit %s ≠ crédit %s.',
                number_format($debit, 0, ',', ' '),
                number_format($credit, 0, ',', ' '),
            );
        }

        $inconnus = array_diff(
            array_keys($comptes),
            PlanComptable::query()->whereIn('numero_compte', array_keys($comptes))->pluck('numero_compte')->all(),
        );
        if ($inconnus !== []) {
            return 'Compte inconnu du serveur : « '.array_values($inconnus)[0].' ».';
        }

        // Exercice et mois : dans le fuseau de l'exploitation.
        $date = CarbonImmutable::parse($ligne['date_ecriture'])->utc();
        [$annee, $mois] = Verrous::anneeMois($date);
        if ($annee !== (int) $ligne['exercice_annee']) {
            return "L'exercice de la pièce ({$ligne['exercice_annee']}) ne correspond pas à sa date ($annee).";
        }
        if (Verrous::exercice($annee) === null) {
            return "Exercice $annee hors des bornes acceptées.";
        }
        // La cloture annuelle prime sur le verrou mensuel : ses pieces s'ecrivent au 31/12 et au 01/01.
        $motif = $this->pourCloture ? Verrous::motifVerrouExercice($annee) : Verrous::motifVerrou($annee, $mois);
        if ($motif !== null) {
            return $motif;
        }

        if (! empty($ligne['contrepasse_de'])) {
            $motif = $this->verifierContrepassation($ligne);
            if ($motif !== null) {
                return $motif;
            }
        }

        $piece = (new PieceComptable)->forceFill([
            'id' => $ligne['id'],
            'device_id' => $deviceId,
            'numero_piece' => $ligne['numero_piece'] ?? null,
            'date_ecriture' => $date,
            'exercice_annee' => $annee,
            'journal_code' => $ligne['journal_code'],
            'vente_ref' => $ligne['vente_ref'] ?? null,
            'achat_ref' => $ligne['achat_ref'] ?? null,
            'contrepasse_de' => $ligne['contrepasse_de'] ?? null,
            'updated_at' => CarbonImmutable::parse($ligne['updated_at'])->utc(),
            'serveur_modifie_le' => CarbonImmutable::now('UTC'),
        ]);
        $piece->save();

        foreach ($ligne['lignes'] as $l) {
            (new EcritureComptable)->forceFill([
                'id' => $l['id'],
                'piece_id' => $piece->id,
                'numero_compte' => $l['numero_compte'],
                'debit' => $l['debit'],
                'credit' => $l['credit'],
                'libelle' => $l['libelle'],
                'axe_analytique' => $l['axe_analytique'] ?? null,
            ])->save();
        }

        return null;
    }

    /**
     * Une contrepassation reprend la piece annulee LIGNE POUR LIGNE, sens inverse : sans
     * ce controle, « annuler » serait un moyen detourne de passer n'importe quelle ecriture.
     * Une piece ne s'annule qu'une fois, et une annulation ne s'annule pas.
     */
    private function verifierContrepassation(array $ligne): ?string
    {
        $originale = PieceComptable::query()->with('lignes')->find($ligne['contrepasse_de']);
        if ($originale === null) {
            return "Pièce annulée inconnue du serveur : elle doit être transmise d'abord.";
        }
        if ($originale->contrepasse_de !== null) {
            return "Une écriture d'annulation ne s'annule pas : saisissez une nouvelle écriture.";
        }
        if (PieceComptable::query()->where('contrepasse_de', $originale->id)->exists()) {
            return 'Cette pièce est déjà annulée.';
        }

        $net = [];
        foreach ($originale->lignes as $l) {
            $net[$l->numero_compte] = ($net[$l->numero_compte] ?? 0) + $l->debit - $l->credit;
        }
        foreach ($ligne['lignes'] as $l) {
            $net[$l['numero_compte']] = ($net[$l['numero_compte']] ?? 0) + (float) $l['debit'] - (float) $l['credit'];
        }
        foreach ($net as $solde) {
            if (abs($solde) > Verrous::TOLERANCE) {
                return "L'écriture d'annulation ne reprend pas la pièce annulée, ligne pour ligne.";
            }
        }

        return null;
    }
}
