<?php

namespace App\Sync\Tables;

use App\Models\ClotureExercice;
use App\Models\ExerciceComptable;
use App\Models\PieceComptable;
use App\Models\User;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\ReportANouveau;
use App\Services\Comptabilite\Verrous;
use App\Support\Audit;
use App\Support\UuidDeterministe;
use App\Sync\DroitsPoste;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * Cloture ANNUELLE d'un exercice : un fait LOURD (`46d_` §4).
 *
 * Le serveur ne la sert jamais (l'exercice cloture redescend par `exercice_comptable`) ;
 * il la REJOUE et decide :
 *  - **qui** : `close-fiscal-year` (l'administratrice seule, DV-15) ;
 *  - **quand** : sur une balance equilibree, toutes les pieces de l'exercice etant deja
 *    recues (le poste envoie ses pieces AVANT : ordre du moteur) ;
 *  - **effet** : l'exercice est clos (definitif : aucune declôture, BR-CPT-001), l'exercice
 *    suivant est ouvert, les ecritures sont verrouillees (derive de l'exercice) ;
 *  - **trace** : le fait est garde (qui, d'ou, quand) et un audit est ecrit.
 *
 * Une ecriture saisie hors ligne pour cet exercice et arrivant APRES la cloture est
 * refusee avec son motif (`EcrituresTable`) : le poste la garde, marquee, dans ses livres.
 * Rejoue, ou deja clos : accepte sans rien changer.
 */
class ClotureExerciceTable extends TableSync
{
    private ?User $utilisateur = null;

    public function nom(): string
    {
        return 'clotures_exercice';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return ClotureExercice::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    /** Jamais servie : l'exercice cloture redescend par `exercice_comptable`. */
    public function peutLire(User $utilisateur): bool
    {
        return false;
    }

    public function droitEcriture(): ?string
    {
        return 'close-fiscal-year';
    }

    public function peutEcrire(User $utilisateur): bool
    {
        $this->pourUtilisateur($utilisateur);

        return $utilisateur->can('close-fiscal-year');
    }

    public function pourUtilisateur(User $utilisateur): static
    {
        $this->utilisateur = $utilisateur;

        return $this;
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $v = Validator::make($ligne, [
            'id' => ['required', 'uuid'],
            'annee' => ['required', 'integer'],
            'date_cloture' => ['required', 'date'],
            'updated_at' => ['required', 'date'],
            'affectation' => ['nullable', 'array'],
        ], [
            'id.required' => "L'identifiant de la clôture est obligatoire.",
            'id.uuid' => "L'identifiant de la clôture doit être un UUID.",
            'annee.required' => "L'exercice à clôturer est obligatoire.",
            'date_cloture.required' => 'La date de clôture est obligatoire.',
            'updated_at.required' => 'La date de saisie de la clôture est obligatoire.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if ($this->utilisateur === null || ! $this->utilisateur->can('close-fiscal-year')) {
            return $this->refuserAvecCode(DroitsPoste::CODE_REFUS, 'Droit insuffisant pour clôturer un exercice (close-fiscal-year).');
        }

        $annee = (int) $ligne['annee'];
        if ($ligne['id'] !== UuidDeterministe::clotureExercice($annee)) {
            return "L'identifiant de la clôture ne désigne pas l'exercice $annee.";
        }

        $exercice = Verrous::exercice($annee);
        if ($exercice === null) {
            return "Exercice $annee hors des bornes acceptées.";
        }
        // Deja clos (rejeu, ou autre poste) : accepte sans rien changer.
        if ($exercice->is_cloture) {
            return null;
        }
        if (! Verrous::exerciceEquilibre($annee)) {
            $t = Verrous::totaux($annee);

            return sprintf(
                'Balance déséquilibrée de %s FCFA : une clôture annuelle est définitive, elle ne peut pas s\'exécuter sur une comptabilité déséquilibrée (BR-CPT-004).',
                number_format(abs($t['debit'] - $t['credit']), 0, ',', ' '),
            );
        }

        // Ordre : l'exercice suivant ne doit pas etre clos avant celui-ci.
        if (ExerciceComptable::query()->whereKey($annee + 1)->where('is_cloture', true)->exists()) {
            return "L'exercice ".($annee + 1).' est déjà clôturé : clôturez les exercices dans l\'ordre.';
        }

        // REPORT A NOUVEAU (`47c_`) : le serveur engendre lui-meme les ecritures de cloture et
        // d'a-nouveaux depuis SON livre, avec les memes identifiants que le poste (rejeu sans
        // doublon). Refus motive si l'affectation est incoherente ou si un a-nouveau ne s'equilibre pas.
        $affectation = ReportANouveau::affectation($ligne['affectation'] ?? null);
        ExerciceComptable::query()->firstOrCreate(['annee' => $annee + 1], ['is_cloture' => false]);
        $calcul = ReportANouveau::calculer(
            LivreComptable::toutes(),
            $annee,
            $affectation,
            LivreComptable::plan()->keys()->map(fn ($k) => (string) $k)->all(),
        );
        if ($calcul['anomalies'] !== []) {
            return implode(' ', $calcul['anomalies']);
        }
        try {
            DB::transaction(fn () => $this->ecrirePieces($deviceId, $calcul['pieces']));
        } catch (\RuntimeException $e) {
            return $e->getMessage();
        }

        $date = CarbonImmutable::parse($ligne['date_cloture'])->utc();
        $exercice->forceFill([
            'is_cloture' => true,
            'date_cloture' => $date,
            'cloture_par' => $this->utilisateur->getKey(),
            'affectation' => ReportANouveau::totalDistribue($affectation) > 0 ? json_encode($affectation) : null,
            'rouvert_le' => null,
        ])->save();
        $exercice->touch();

        // L'exercice suivant est ouvert automatiquement (comme au poste).
        ExerciceComptable::query()->firstOrCreate(['annee' => $annee + 1], ['is_cloture' => false]);

        (new ClotureExercice)->forceFill([
            'id' => $ligne['id'],
            'annee' => $annee,
            'device_id' => $deviceId,
            'utilisateur_id' => $this->utilisateur->getKey(),
            'date_cloture' => $date,
            'affectation' => ReportANouveau::totalDistribue($affectation) > 0 ? json_encode($affectation) : null,
            'updated_at' => CarbonImmutable::parse($ligne['updated_at'])->utc(),
            'serveur_modifie_le' => CarbonImmutable::now('UTC'),
        ])->save();

        Audit::enregistrer('comptabilite.cloture_exercice', $this->utilisateur, ['annee' => $annee, 'poste' => $deviceId]);

        return null;
    }

    /**
     * Ecrit les pieces de cloture par `EcrituresTable::absorber` (jamais d'ecriture directe),
     * identifiants deterministes : une piece deja ecrite est acceptee sans rien changer.
     *
     * @param  list<array>  $pieces
     */
    private function ecrirePieces(string $deviceId, array $pieces): void
    {
        foreach ($pieces as $p) {
            $motif = (new EcrituresTable)->pourUtilisateur($this->utilisateur)->pourCloture()->absorber($deviceId, [
                'id' => ReportANouveau::idPiece($p['cle']),
                'numero_piece' => $p['numero'],
                'date_ecriture' => $p['date']->utc()->format('Y-m-d\TH:i:s.u\Z'),
                'exercice_annee' => $p['exercice'],
                'journal_code' => $p['journal'],
                'vente_ref' => null,
                'achat_ref' => null,
                'contrepasse_de' => null,
                'plan_version' => \App\Support\PlanSyscohada::VERSION,
                'updated_at' => CarbonImmutable::now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
                'lignes' => array_map(fn (array $l) => [
                    'id' => ReportANouveau::idLigne($p['cle'], $l['compte']),
                    'numero_compte' => $l['compte'],
                    'debit' => $l['debit'],
                    'credit' => $l['credit'],
                    'libelle' => $l['libelle'],
                    'axe_analytique' => null,
                ], $p['lignes']),
            ]);
            if ($motif !== null) {
                throw new \RuntimeException($motif);
            }
        }
    }

    /**
     * REOUVERTURE d'un exercice clos (`close-fiscal-year`, l'administratrice seule) : retire les
     * ecritures de cloture (CL) de `$annee` et les a-nouveaux (AN) de l'exercice suivant — des
     * ecritures DERIVEES, jamais saisies —, rouvre l'exercice et date la reouverture
     * (`rouvert_le`) : les postes la suivent. Refusee si l'exercice suivant est clos.
     *
     * @return string|null le motif du refus, ou `null` si l'exercice est rouvert
     */
    public function rouvrir(int $annee): ?string
    {
        if ($this->utilisateur === null || ! $this->utilisateur->can('close-fiscal-year')) {
            return 'Droit insuffisant pour rouvrir un exercice (close-fiscal-year).';
        }
        $exercice = ExerciceComptable::query()->find($annee);
        if ($exercice === null || ! $exercice->is_cloture) {
            return "L'exercice $annee n'est pas clôturé.";
        }
        if (ExerciceComptable::query()->whereKey($annee + 1)->where('is_cloture', true)->exists()) {
            return "L'exercice ".($annee + 1).' est clôturé : rouvrez-le d\'abord.';
        }

        DB::transaction(function () use ($annee, $exercice) {
            PieceComptable::query()->where('exercice_annee', $annee)->where('journal_code', ReportANouveau::CLOTURE)->delete();
            PieceComptable::query()->where('exercice_annee', $annee + 1)->where('journal_code', ReportANouveau::A_NOUVEAU)->delete();
            ClotureExercice::query()->where('annee', $annee)->delete();
            $exercice->forceFill([
                'is_cloture' => false, 'date_cloture' => null, 'cloture_par' => null,
                'affectation' => null, 'rouvert_le' => CarbonImmutable::now('UTC'),
            ])->save();
            $exercice->touch();
        });
        Audit::enregistrer('comptabilite.reouverture_exercice', $this->utilisateur, ['annee' => $annee]);

        return null;
    }
}
