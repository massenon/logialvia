<?php

namespace App\Sync\Tables;

use App\Models\Achat;
use App\Models\Fournisseur;
use App\Models\Intrant;
use App\Models\LigneAchat;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;

/**
 * Achats : FAITS saisis au poste, jamais fusionnes. Memes regles que les ventes :
 *
 *  - un achat et ses lignes forment UN lot (acceptes ou refuses ensemble, servis
 *    ensemble) ;
 *  - `reference` : numero OFFICIEL (DV-21), unique pour tous avec un code de poste
 *    (`ACH-P2-2026-001`), unique PAR POSTE sans code (`ACH-2026-001`) ;
 *  - lignes IMMUABLES des que l'achat n'est plus « Commandé » ; tant qu'il l'est, une saisie plus
 *    recente (modification de la commande) REMPLACE ses lignes ; entete en « dernier ecrivain gagne »,
 *    reference jamais changee ;
 *  - ni stock, ni PMP, ni ecriture comptable : le serveur enregistre le fait d'achat,
 *    il ne rejoue aucune reception (`46_` §2.3-§2.4).
 */
class AchatsTable extends TableSync
{
    /**
     * `Crédit` : proposé par la commande du poste (liste déroulante du Dart) mais absent de la liste
     * d'origine — un achat à crédit du poste était refusé en bloc par le serveur (« mode inconnu »).
     */
    public const MODES = ['Espèces', 'Mobile Money', 'Crédit', 'Non précisé'];

    /** Code du « poste » web dans les références (`ACH-WEB-2026-001`) : le web est un poste de code WEB. */
    public const CODE_WEB = 'WEB';

    public const STATUTS = ['Commandé', 'Livré', 'Annulé'];

    public const MOTIF_REFERENCE = 'Cette référence est déjà utilisée par un autre achat.';

    public function nom(): string
    {
        return 'achats';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return Achat::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-achats';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-achats';
    }

    public static function porteeReference(string $reference, string $deviceId): string
    {
        return preg_match('/^ACH-(P\d+|WEB)-\d{4}-\d{3,}$/', $reference) === 1 ? '' : $deviceId;
    }

    public function exporter(Model $ligne): array
    {
        $donnees = parent::exporter($ligne);
        unset($donnees['portee_reference']);
        $donnees['lignes'] = $ligne->lignes()->orderBy('id')->get()
            ->map(fn (LigneAchat $l) => $l->attributesToArray())
            ->all();

        return $donnees;
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $v = Validator::make($ligne, [
            'id' => ['required', 'uuid'],
            'reference' => ['required', 'string', 'regex:/^ACH-((P\d+|WEB)-)?\d{4}-\d{3,}$/'],
            'fournisseur_id' => ['required', 'uuid'],
            'date_achat' => ['required', 'date'],
            'statut' => ['required', 'string', 'in:'.implode(',', self::STATUTS)],
            'total' => ['required', 'numeric', 'min:0'],
            'paye' => ['required', 'numeric', 'min:0'],
            'mode' => ['nullable', 'string', 'in:'.implode(',', self::MODES)],
            'echeance' => ['nullable', 'date'],
            'updated_at' => ['required', 'date'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.id' => ['required', 'uuid'],
            'lignes.*.intrant_code' => ['required', 'string', 'max:40'],
            'lignes.*.nom' => ['required', 'string', 'max:255'],
            'lignes.*.qte' => ['required', 'numeric', 'gt:0'],
            'lignes.*.pu_achat' => ['required', 'numeric', 'min:0'],
        ], [
            'id.required' => "L'identifiant de l'achat est obligatoire.",
            'id.uuid' => "L'identifiant de l'achat doit être un UUID.",
            'reference.required' => "La référence de l'achat est obligatoire.",
            'reference.regex' => "La référence de l'achat est invalide (attendu : ACH-P2-2026-001 ou ACH-WEB-2026-001).",
            'fournisseur_id.required' => "Le fournisseur de l'achat est obligatoire.",
            'date_achat.required' => "La date de l'achat est obligatoire.",
            'date_achat.date' => "La date de l'achat est invalide.",
            'statut.in' => "Le statut de l'achat est inconnu.",
            'mode.in' => 'Le mode de règlement est inconnu.',
            'total.min' => "Le total de l'achat ne peut pas être négatif.",
            'paye.min' => 'Le montant payé ne peut pas être négatif.',
            'updated_at.required' => "La date de saisie de l'achat est obligatoire.",
            'lignes.required' => 'Un achat doit avoir au moins une ligne.',
            'lignes.min' => 'Un achat doit avoir au moins une ligne.',
            'lignes.*.qte.gt' => "La quantité d'une ligne doit être supérieure à 0.",
            'lignes.*.pu_achat.min' => "Le prix d'une ligne ne peut pas être négatif.",
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if ((float) $ligne['paye'] > (float) $ligne['total'] + 0.005) {
            return "Le montant payé dépasse le total de l'achat.";
        }
        if (! Fournisseur::query()->whereKey($ligne['fournisseur_id'])->exists()) {
            return 'Fournisseur inconnu du serveur.';
        }
        // Les intrants (referentiel) partent AVANT les achats : un code inconnu rend
        // l'achat inexploitable par les autres postes.
        foreach ($ligne['lignes'] as $l) {
            if (! Intrant::query()->whereKey($l['intrant_code'])->exists()) {
                return "Intrant inconnu du serveur : « {$l['intrant_code']} ».";
            }
        }

        $saisie = CarbonImmutable::parse($ligne['updated_at'])->utc();
        $existant = Achat::query()->find($ligne['id']);

        $portee = self::porteeReference($ligne['reference'], $deviceId);
        $doublon = Achat::query()
            ->where('portee_reference', $portee)
            ->where('reference', $ligne['reference'])
            ->where('id', '!=', $ligne['id'])
            ->exists();
        if ($doublon) {
            return self::MOTIF_REFERENCE;
        }

        $entete = [
            'fournisseur_id' => $ligne['fournisseur_id'],
            'date_achat' => CarbonImmutable::parse($ligne['date_achat'])->utc(),
            'statut' => $ligne['statut'],
            'total' => $ligne['total'],
            'paye' => $ligne['paye'],
            'mode' => $ligne['mode'] ?? null,
            'echeance' => empty($ligne['echeance']) ? null : CarbonImmutable::parse($ligne['echeance'])->utc(),
        ];

        if ($existant === null) {
            $achat = (new Achat)->forceFill($entete + [
                'id' => $ligne['id'],
                'device_id' => $deviceId,
                'reference' => $ligne['reference'],
                'portee_reference' => $portee,
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ]);
            $achat->save();

            foreach ($ligne['lignes'] as $l) {
                (new LigneAchat)->forceFill([
                    'id' => $l['id'],
                    'achat_id' => $achat->id,
                    'intrant_code' => $l['intrant_code'],
                    'nom' => $l['nom'],
                    'qte' => $l['qte'],
                    'pu_achat' => $l['pu_achat'],
                ])->save();
            }
        } elseif ($saisie->greaterThan($existant->updated_at)) {
            // Une commande encore « Commandé » peut etre modifiee (le web le permet) : ses lignes
            // suivent la saisie la plus recente. Livree ou annulee, ses lignes ne bougent plus
            // (le stock des postes en depend).
            $modifiable = $existant->statut === 'Commandé';
            $existant->forceFill($entete + [
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ])->save();
            if ($modifiable) {
                $this->remplacerLignes($existant, $ligne['lignes']);
            }
        }

        return null;
    }

    /** @param list<array<string, mixed>> $lignes Le jeu complet de la commande : l'absent est supprime. */
    private function remplacerLignes(Achat $achat, array $lignes): void
    {
        $gardees = array_column($lignes, 'id');
        LigneAchat::query()->where('achat_id', $achat->id)->whereNotIn('id', $gardees)->delete();

        foreach ($lignes as $l) {
            $existante = LigneAchat::query()->find($l['id']);
            if ($existante !== null && $existante->achat_id !== $achat->id) {
                continue; // un UUID de ligne appartient a un seul achat : jamais deplace
            }
            ($existante ?? new LigneAchat)->forceFill([
                'id' => $l['id'],
                'achat_id' => $achat->id,
                'intrant_code' => $l['intrant_code'],
                'nom' => $l['nom'],
                'qte' => $l['qte'],
                'pu_achat' => $l['pu_achat'],
            ])->save();
        }
    }
}
