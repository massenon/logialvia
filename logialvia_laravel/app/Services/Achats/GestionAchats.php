<?php

namespace App\Services\Achats;

use App\Livewire\Catalogue;
use App\Models\Achat;
use App\Models\Fournisseur;
use App\Models\Intrant;
use App\Models\LigneAchat;
use App\Models\User;
use App\Services\Comptabilite\EcrituresAutomatiquesAchats;
use App\Services\Comptabilite\Saisie;
use App\Support\Audit;
use App\Sync\Tables\AchatsTable;
use App\Sync\Tables\MouvementsIntrantTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Operations d'achat du web : commande, modification, reception, reglement, annulation.
 *
 * ## Regles lues dans le Dart (`approvisionnement_repository_drift.dart`, `approvisionnement_view_model.dart`)
 * - **Commande** : panier non vide, fournisseur choisi, montant regle ≥ 0 (borne au total), prix
 *   unitaire > 0 ; reference `ACH-<poste>-AAAA-NNN` ; la piece d'achat est ecrite des la commande
 *   (livree ou non) ; si « livree immediatement », la reception est faite dans la foulee.
 * - **Reception** : une commande « Commandé » seulement. Au poste : stock + PMP + journal. **Au web :
 *   journal SEUL** (decision du client « stock propre a chaque poste + journal partage ») : un
 *   mouvement `Entrée` par ligne, poste d'origine = web, AUCUN stock ni PMP, AUCUNE ecriture (le Dart
 *   n'en ecrit pas a la reception : la charge a ete constatee a la commande).
 * - **Reglement** : borne au reste du ; ecriture D 401 / C tresorerie du montant REELLEMENT verse.
 *
 * ## Ce que le web ajoute (le Dart ne le fait pas — voir `docs/logialvia/47b_ACHATS_PARITE.md`)
 * - **Modification** d'une commande « Commandé » : les pieces vivantes sont extournees et une piece
 *   neuve est ecrite d'apres la nouvelle composition.
 * - **Annulation** avec motif obligatoire : extourne des pieces, mouvement `Sortie` si la commande
 *   etait livree (journal seulement), statut « Annulé ».
 * - **Echeance** de la dette (colonne `achats.echeance` du poste, que son ecran ne renseigne pas).
 *
 * Toute ecriture passe par `TableSync::absorber` (poste « web »), jamais par un `update` direct, et
 * chaque operation est UNE transaction : un refus du serveur (mois cloture, equilibre…) n'en laisse
 * aucune trace partielle. Le droit `manage-achats` est verifie ici ET dans chaque methode Livewire.
 */
final class GestionAchats
{
    /** Modes proposes a la commande (liste deroulante du Dart). */
    public const MODES = ['Espèces', 'Mobile Money', 'Crédit'];

    /** Modes d'un reglement : un instrument reel (« Crédit » n'en est pas un). */
    public const MODES_REGLEMENT = ['Espèces', 'Mobile Money'];

    public function __construct(private readonly User $utilisateur) {}

    /**
     * @param  array{fournisseur_id: ?string, mode: ?string, paye: float|int|string|null, echeance: ?string, livree: bool, lignes: list<array{intrant_code: string, qte: mixed, pu: mixed}>}  $d
     * @return array{erreur: ?string, achat: ?Achat}
     */
    public function creer(array $d): array
    {
        $this->exigerLeDroit();

        return $this->executer(function () use ($d): Achat {
            $v = $this->valider($d);
            $maintenant = Saisie::instantMaintenant();
            $reference = $this->prochaineReference();
            $paye = min($v['paye'], $v['total']);

            $achat = $this->ecrireAchat([
                'id' => (string) Str::uuid(),
                'reference' => $reference,
                'fournisseur_id' => $v['fournisseur_id'],
                'date_achat' => $maintenant,
                'statut' => $d['livree'] ? 'Livré' : 'Commandé',
                'total' => $v['total'],
                'paye' => $paye,
                'mode' => $v['mode'],
                'echeance' => $v['echeance'],
                'updated_at' => $maintenant,
                'lignes' => $this->lignesAEcrire($v['lignes']),
            ]);

            $this->ecrireLaPiece($achat, $maintenant, $v['mode'], $paye);
            if ($d['livree']) {
                $this->journaliserReception($achat);
            }
            Audit::enregistrer('achats.creation', $this->utilisateur, ['reference' => $reference, 'total' => $v['total']]);

            return $achat;
        });
    }

    /**
     * Modification d'une commande « Commandé » : composition, fournisseur, mode, echeance. Le montant
     * deja regle est conserve (il ne se corrige que par un reglement) ; il ne peut depasser le total.
     *
     * @return array{erreur: ?string, achat: ?Achat}
     */
    public function modifier(string $achatId, array $d): array
    {
        $this->exigerLeDroit();

        return $this->executer(function () use ($achatId, $d): Achat {
            $achat = $this->charger($achatId);
            if ($achat->statut !== 'Commandé') {
                throw new RefusAchat('Seule une commande en attente de livraison peut être modifiée.');
            }
            $v = $this->valider($d + [
                'livree' => false,
                'date_commande' => $achat->date_achat->timezone(config('logialvia.fuseau'))->format('Y-m-d'),
            ]);
            if ($v['total'] + 0.005 < $achat->paye) {
                throw new RefusAchat('Le montant déjà réglé ('.$this->nombre($achat->paye).' FCFA) dépasse le nouveau total de la commande.');
            }

            $maintenant = Saisie::instantMaintenant();
            $comptes = $this->comptes();

            // Les pieces vivantes sont extournees, une piece neuve decrit la commande telle qu'elle est.
            $refus = $comptes->extourner($achat->reference, 'modification de la commande');
            if ($refus !== null) {
                throw new RefusAchat($refus);
            }

            $achat = $this->ecrireAchat($this->entete($achat, [
                'fournisseur_id' => $v['fournisseur_id'],
                'total' => $v['total'],
                'mode' => $v['mode'],
                'echeance' => $v['echeance'],
                'lignes' => $this->lignesAEcrire($v['lignes']),
            ]));
            $this->ecrireLaPiece($achat, $maintenant, $v['mode'], (float) $achat->paye);
            Audit::enregistrer('achats.modification', $this->utilisateur, ['reference' => $achat->reference, 'total' => $v['total']]);

            return $achat;
        });
    }

    /** @return array{erreur: ?string, achat: ?Achat} */
    public function receptionner(string $achatId): array
    {
        $this->exigerLeDroit();

        return $this->executer(function () use ($achatId): Achat {
            $achat = $this->charger($achatId);
            if ($achat->statut !== 'Commandé') {
                throw new RefusAchat('Cette commande n\'est pas en attente de livraison.');
            }

            $achat = $this->ecrireAchat($this->entete($achat, ['statut' => 'Livré']));
            $this->journaliserReception($achat);
            Audit::enregistrer('achats.reception', $this->utilisateur, ['reference' => $achat->reference]);

            return $achat;
        });
    }

    /**
     * Reglement d'une dette. Un versement superieur au reste du est BORNE au reste du (comme le
     * poste) et l'ecriture porte le montant reellement verse.
     *
     * @return array{erreur: ?string, achat: ?Achat, verse: float}
     */
    public function regler(string $achatId, mixed $montant, ?string $mode): array
    {
        $this->exigerLeDroit();

        $verse = 0.0;
        $bilan = $this->executer(function () use ($achatId, $montant, $mode, &$verse): Achat {
            $saisi = $this->nombreOuNull($montant);
            if ($saisi === null || $saisi <= 0) {
                throw new RefusAchat('Le montant doit être supérieur à 0.');
            }
            if (! in_array($mode, self::MODES_REGLEMENT, true)) {
                throw new RefusAchat('Choisissez le mode du règlement (Espèces ou Mobile Money).');
            }
            $achat = $this->charger($achatId);
            if ($achat->statut === 'Annulé') {
                throw new RefusAchat('Cette commande est annulée.');
            }
            $reste = round($achat->total - $achat->paye, 2);
            if ($reste <= 0) {
                throw new RefusAchat('Cette commande est déjà soldée.');
            }

            $verse = round(min($saisi, $reste), 2);
            $achat = $this->ecrireAchat($this->entete($achat, ['paye' => round($achat->paye + $verse, 2)]));

            $refus = $this->comptes()->pourReglement($achat->reference, Saisie::instantMaintenant(), $mode, $verse);
            if ($refus !== null) {
                throw new RefusAchat($refus);
            }
            Audit::enregistrer('achats.reglement', $this->utilisateur, ['reference' => $achat->reference, 'montant' => $verse, 'mode' => $mode]);

            return $achat;
        });

        return $bilan + ['verse' => $verse];
    }

    /** @return array{erreur: ?string, achat: ?Achat} */
    public function annuler(string $achatId, ?string $motif): array
    {
        $this->exigerLeDroit();

        return $this->executer(function () use ($achatId, $motif): Achat {
            $motif = trim((string) $motif);
            if ($motif === '') {
                throw new RefusAchat('Le motif de l\'annulation est obligatoire.');
            }
            $achat = $this->charger($achatId);
            if ($achat->statut === 'Annulé') {
                throw new RefusAchat('Cette commande est déjà annulée.');
            }
            $etaitLivree = $achat->statut === 'Livré';

            $refus = $this->comptes()->extourner($achat->reference, mb_substr($motif, 0, 120));
            if ($refus !== null) {
                throw new RefusAchat($refus);
            }
            $achat = $this->ecrireAchat($this->entete($achat, ['statut' => 'Annulé']));
            if ($etaitLivree) {
                $this->journaliserReception($achat, $motif);
            }
            Audit::enregistrer('achats.annulation', $this->utilisateur, ['reference' => $achat->reference, 'motif' => $motif, 'livree' => $etaitLivree]);

            return $achat;
        });
    }

    // ------------------------------------------------------------------ internes

    private function exigerLeDroit(): void
    {
        abort_unless($this->utilisateur->can('manage-achats'), 403);
    }

    /** @return array{erreur: ?string, achat: ?Achat} */
    private function executer(\Closure $operation): array
    {
        try {
            return ['erreur' => null, 'achat' => DB::transaction($operation)];
        } catch (RefusAchat $e) {
            return ['erreur' => $e->getMessage(), 'achat' => null];
        }
    }

    private function comptes(): EcrituresAutomatiquesAchats
    {
        return new EcrituresAutomatiquesAchats(new Saisie($this->utilisateur));
    }

    private function charger(string $id): Achat
    {
        $achat = Achat::query()->with('lignes')->lockForUpdate()->find($id);
        if ($achat === null) {
            throw new RefusAchat('Cette commande n\'existe plus.');
        }

        return $achat;
    }

    /**
     * Validation du formulaire, dans l'ordre et avec les messages du Dart (`validerCommande`), puis les
     * controles que le web doit faire lui-meme (quantite entiere, intrant et fournisseur connus).
     *
     * @return array{fournisseur_id: string, mode: string, paye: float, echeance: ?string, total: float, lignes: list<array{intrant_code: string, nom: string, qte: int, pu: float}>}
     */
    private function valider(array $d): array
    {
        $brutes = array_values($d['lignes'] ?? []);
        if ($brutes === []) {
            throw new RefusAchat('Le panier d\'achat est vide.');
        }
        $fournisseurId = (string) ($d['fournisseur_id'] ?? '');
        if ($fournisseurId === '') {
            throw new RefusAchat('Sélectionnez un fournisseur.');
        }
        if (! Fournisseur::query()->whereNull('supprime_le')->whereKey($fournisseurId)->exists()) {
            throw new RefusAchat('Ce fournisseur n\'existe plus.');
        }
        $paye = $this->nombreOuNull($d['paye'] ?? 0) ?? 0.0;
        if ($paye < 0) {
            throw new RefusAchat('Le montant réglé ne peut être négatif.');
        }

        $mode = (string) ($d['mode'] ?? '');
        if (! in_array($mode, self::MODES, true)) {
            throw new RefusAchat('Le mode de règlement est inconnu.');
        }

        $intrants = Intrant::query()->whereIn('code', array_column($brutes, 'intrant_code'))->get()->keyBy('code');
        $lignes = [];
        $vus = [];
        foreach ($brutes as $b) {
            $code = (string) ($b['intrant_code'] ?? '');
            $intrant = $intrants->get($code);
            if ($intrant === null) {
                throw new RefusAchat("Intrant inconnu : « $code ».");
            }
            if (isset($vus[$code])) {
                throw new RefusAchat("L'intrant « {$intrant->name} » figure deux fois dans la commande.");
            }
            $vus[$code] = true;

            $qte = $this->nombreOuNull($b['qte'] ?? null);
            if ($qte === null || $qte <= 0 || floor($qte) != $qte) {
                throw new RefusAchat('La quantité de chaque ligne doit être un entier supérieur à 0.');
            }
            $pu = $this->nombreOuNull($b['pu'] ?? null);
            if ($pu === null || $pu <= 0) {
                throw new RefusAchat('Chaque ligne doit avoir un prix unitaire positif.');
            }
            $lignes[] = ['intrant_code' => $code, 'nom' => $intrant->name, 'qte' => (int) $qte, 'pu' => round($pu, 2)];
        }
        $total = round(array_sum(array_map(fn (array $l) => $l['qte'] * $l['pu'], $lignes)), 2);

        $echeance = null;
        $jour = trim((string) ($d['echeance'] ?? ''));
        if ($jour !== '') {
            $echeance = Saisie::instantDuJour($jour);
            if ($echeance === null) {
                throw new RefusAchat('La date d\'échéance est invalide.');
            }
            // Une echeance anterieure a la commande n'a pas de sens (le prototype en avait une datee
            // de la VEILLE de l'achat qu'elle reglait).
            $commande = $d['date_commande'] ?? CarbonImmutable::now(config('logialvia.fuseau'))->format('Y-m-d');
            if ($jour < $commande) {
                throw new RefusAchat('L\'échéance ne peut précéder la date de la commande.');
            }
        }

        return [
            'fournisseur_id' => $fournisseurId,
            'mode' => $mode,
            'paye' => round($paye, 2),
            'echeance' => $echeance,
            'total' => $total,
            'lignes' => $lignes,
        ];
    }

    /** @param list<array{intrant_code: string, nom: string, qte: int, pu: float}> $lignes */
    private function lignesAEcrire(array $lignes): array
    {
        return array_map(fn (array $l) => [
            'id' => (string) Str::uuid(),
            'intrant_code' => $l['intrant_code'],
            'nom' => $l['nom'],
            'qte' => $l['qte'],
            'pu_achat' => $l['pu'],
        ], $lignes);
    }

    /** Ligne `achats` complete d'un achat existant, avec les changements de `$modif` et un instant de saisie plus recent. */
    private function entete(Achat $achat, array $modif): array
    {
        $lignes = $modif['lignes'] ?? $achat->lignes->map(fn (LigneAchat $l) => [
            'id' => $l->id, 'intrant_code' => $l->intrant_code, 'nom' => $l->nom,
            'qte' => $l->qte, 'pu_achat' => $l->pu_achat,
        ])->all();

        // Dernier ecrivain gagne, strictement : l'instant doit depasser celui de la ligne detenue.
        $instant = CarbonImmutable::now('UTC');
        $detenu = CarbonImmutable::instance($achat->updated_at);
        if (! $instant->greaterThan($detenu)) {
            $instant = $detenu->addMicrosecond();
        }

        return $modif + [
            'id' => $achat->id,
            'reference' => $achat->reference,
            'fournisseur_id' => $achat->fournisseur_id,
            'date_achat' => CarbonImmutable::instance($achat->date_achat)->utc()->format('Y-m-d\TH:i:s.u\Z'),
            'statut' => $achat->statut,
            'total' => $achat->total,
            'paye' => $achat->paye,
            'mode' => $achat->mode,
            'echeance' => $achat->echeance === null ? null : CarbonImmutable::instance($achat->echeance)->utc()->format('Y-m-d\TH:i:s.u\Z'),
            'updated_at' => $instant->format('Y-m-d\TH:i:s.u\Z'),
            'lignes' => $lignes,
        ];
    }

    /** `AchatsTable::absorber` (poste « web ») : memes validations qu'un poste ; un refus annule l'operation. */
    private function ecrireAchat(array $ligne): Achat
    {
        $motif = (new AchatsTable)->absorber(Catalogue::POSTE_WEB, $ligne);
        if ($motif !== null) {
            throw new RefusAchat($motif);
        }

        return Achat::query()->with('lignes')->findOrFail($ligne['id']);
    }

    private function ecrireLaPiece(Achat $achat, string $instant, ?string $mode, float $paye): void
    {
        $categories = Intrant::query()->whereIn('code', $achat->lignes->pluck('intrant_code'))->pluck('cat', 'code')->all();
        $ventilation = EcrituresAutomatiquesAchats::ventiler(
            $achat->lignes->map(fn (LigneAchat $l) => ['intrant_code' => $l->intrant_code, 'qte' => $l->qte, 'pu_achat' => $l->pu_achat]),
            $categories,
        );

        $refus = $this->comptes()->pourAchat($achat->reference, $instant, $mode, (float) $achat->total, $paye, $ventilation);
        if ($refus !== null) {
            throw new RefusAchat($refus);
        }
    }

    /**
     * Journal partage SEUL : une `Entrée` par ligne a la reception, une `Sortie` (quantite negative)
     * a l'annulation d'une commande livree. Aucun stock, aucun PMP : propres a chaque poste.
     */
    private function journaliserReception(Achat $achat, ?string $motifAnnulation = null): void
    {
        foreach ($achat->lignes as $l) {
            $sortie = $motifAnnulation !== null;
            $motif = $sortie
                ? mb_substr("Annulation commande {$achat->reference} — $motifAnnulation", 0, 255)
                : "Réception commande {$achat->reference}";

            $refus = (new MouvementsIntrantTable)->absorber(Catalogue::POSTE_WEB, [
                'id' => (string) Str::uuid(),
                'horodatage' => Saisie::instantMaintenant(),
                'intrant_code' => $l->intrant_code,
                'article' => $l->nom,
                'type' => $sortie ? 'Sortie' : 'Entrée',
                'motif' => $motif,
                'quantite' => $sortie ? -$l->qte : $l->qte,
                'reference' => $achat->reference,
            ]);
            if ($refus !== null) {
                throw new RefusAchat($refus);
            }
        }
    }

    /** `ACH-WEB-AAAA-NNN` : la sequence est deduite des achats reellement enregistres, jamais renumerotee. */
    private function prochaineReference(): string
    {
        $annee = (int) CarbonImmutable::now(config('logialvia.fuseau'))->year;
        $debut = 'ACH-'.AchatsTable::CODE_WEB."-$annee-";
        $maximum = 0;
        foreach (Achat::query()->where('reference', 'like', $debut.'%')->pluck('reference') as $reference) {
            $sequence = substr((string) $reference, strlen($debut));
            if (ctype_digit($sequence) && (int) $sequence > $maximum) {
                $maximum = (int) $sequence;
            }
        }

        return $debut.str_pad((string) ($maximum + 1), 3, '0', STR_PAD_LEFT);
    }

    private function nombreOuNull(mixed $valeur): ?float
    {
        if ($valeur === null || $valeur === '') {
            return null;
        }
        $texte = str_replace([' ', ','], ['', '.'], trim((string) $valeur));

        return is_numeric($texte) ? (float) $texte : null;
    }

    private function nombre(float $v): string
    {
        return number_format($v, 0, ',', ' ');
    }
}
