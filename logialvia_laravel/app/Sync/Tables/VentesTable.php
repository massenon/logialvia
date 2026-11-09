<?php

namespace App\Sync\Tables;

use App\Models\Client;
use App\Models\LigneVente;
use App\Models\ProduitVendable;
use App\Models\Vente;
use App\Services\PosteDeStock;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Validator;

/**
 * Ventes : FAITS saisis au poste, jamais fusionnes.
 *
 *  - une vente et ses lignes forment UN lot : acceptees ou refusees ensemble (le tout
 *    dans la transaction du lot), servies ensemble au tirage (`lignes` imbriquees) ;
 *  - `reference` est le numero OFFICIEL (DV-21) : unique pour tous quand elle porte un
 *    code de poste (`V-P2-2026-001`) ou celui du web (`V-WEB-2026-001`), unique PAR POSTE
 *    quand elle n'en porte pas
 *    (`V-2026-001`, ventes d'avant l'appairage : deux postes peuvent l'avoir) ;
 *  - les lignes sont IMMUABLES apres creation ; l'entete suit « dernier ecrivain gagne » ;
 *  - ni stock, ni ecriture comptable : le serveur enregistre le fait (`46_` §2.3).
 */
class VentesTable extends TableSync
{
    public const MODES = ['Espèces', 'Mobile Money', 'Non précisé'];

    public const STATUTS = ['Payée', 'Avance', 'Annulée'];

    public const MOTIF_REFERENCE = 'Cette référence est déjà utilisée par une autre vente.';

    public function nom(): string
    {
        return 'ventes';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return Vente::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-ventes';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-ventes';
    }

    /** Code de poste de la vente saisie au web : `V-WEB-2026-001` (comme `OD-WEB-2026-0001`). */
    public const CODE_WEB = 'WEB';

    /** Une reference a code de poste (`P2`) ou du web (`WEB`) est globale ; sans code, propre au poste. */
    public static function porteeReference(string $reference, string $deviceId): string
    {
        return preg_match('/^V-(P\d+|WEB)-\d{4}-\d{3,}$/', $reference) === 1 ? '' : $deviceId;
    }

    public function exporter(Model $ligne): array
    {
        $donnees = parent::exporter($ligne);
        unset($donnees['portee_reference']); // detail d'implementation du serveur
        $donnees['lignes'] = $ligne->lignes()->orderBy('id')->get()
            ->map(fn (LigneVente $l) => $l->attributesToArray())
            ->all();

        return $donnees;
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $v = Validator::make($ligne, [
            'id' => ['required', 'uuid'],
            'reference' => ['required', 'string', 'regex:/^V-((P\d+|WEB)-)?\d{4}-\d{3,}$/'],
            'client' => ['required', 'string', 'max:255'],
            'client_id' => ['nullable', 'uuid'],
            'date_vente' => ['required', 'date'],
            'mode' => ['required', 'string', 'in:'.implode(',', self::MODES)],
            'status' => ['required', 'string', 'in:'.implode(',', self::STATUTS)],
            'total' => ['required', 'numeric', 'min:0'],
            'paye' => ['required', 'numeric', 'min:0'],
            'motif_annulation' => ['nullable', 'string', 'max:255'],
            'livraison_mode' => ['nullable', 'string', 'max:40'],
            'livraison_frais' => ['nullable', 'numeric', 'min:0'],
            'livraison_adresse' => ['nullable', 'string', 'max:255'],
            'livraison_contact' => ['nullable', 'string', 'max:255'],
            'echeance' => ['nullable', 'date'],
            'ligne_mobile_money' => ['nullable', 'string', 'max:255'],
            'poste_cible' => ['nullable', 'uuid'],
            'updated_at' => ['required', 'date'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.id' => ['required', 'uuid'],
            'lignes.*.produit_id' => ['required', 'uuid'],
            'lignes.*.name' => ['required', 'string', 'max:255'],
            'lignes.*.qte' => ['required', 'numeric', 'gt:0'],
            'lignes.*.pu' => ['required', 'numeric', 'min:0'],
            'lignes.*.espece' => ['nullable', 'string', 'max:40'],
        ], [
            'id.required' => "L'identifiant de la vente est obligatoire.",
            'id.uuid' => "L'identifiant de la vente doit être un UUID.",
            'reference.required' => 'La référence de la vente est obligatoire.',
            'reference.regex' => 'La référence de la vente est invalide (attendu : V-P2-2026-001).',
            'client.required' => 'Le client de la vente est obligatoire.',
            'date_vente.required' => 'La date de la vente est obligatoire.',
            'date_vente.date' => 'La date de la vente est invalide.',
            'mode.in' => 'Le mode de règlement est inconnu.',
            'status.in' => 'Le statut de la vente est inconnu.',
            'total.min' => 'Le total de la vente ne peut pas être négatif.',
            'paye.min' => 'Le montant payé ne peut pas être négatif.',
            'poste_cible.uuid' => 'Le poste de stock doit être un identifiant de poste valide.',
            'updated_at.required' => 'La date de saisie de la vente est obligatoire.',
            'lignes.required' => 'Une vente doit avoir au moins une ligne.',
            'lignes.min' => 'Une vente doit avoir au moins une ligne.',
            'lignes.*.qte.gt' => 'La quantité d\'une ligne doit être supérieure à 0.',
            'lignes.*.pu.min' => 'Le prix d\'une ligne ne peut pas être négatif.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }
        if ((float) $ligne['paye'] > (float) $ligne['total'] + 0.005) {
            return 'Le montant payé dépasse le total de la vente.';
        }

        // Les produits et le client doivent deja etre connus du serveur : les demandes
        // (produits) et les faits precedents (clients) partent AVANT les ventes.
        foreach ($ligne['lignes'] as $l) {
            if (! ProduitVendable::query()->whereKey($l['produit_id'])->exists()) {
                return "Produit inconnu du serveur : « {$l['name']} ».";
            }
        }
        if (! empty($ligne['client_id']) && ! Client::query()->whereKey($ligne['client_id'])->exists()) {
            return 'Client inconnu du serveur : « '.$ligne['client'].' ».';
        }

        $saisie = CarbonImmutable::parse($ligne['updated_at'])->utc();
        $existante = Vente::query()->find($ligne['id']);
        $ancienClient = $existante?->client_id; // lu AVANT l'ecriture : le modele est modifie en place

        $portee = self::porteeReference($ligne['reference'], $deviceId);
        $doublon = Vente::query()
            ->where('portee_reference', $portee)
            ->where('reference', $ligne['reference'])
            ->where('id', '!=', $ligne['id'])
            ->exists();
        if ($doublon) {
            return self::MOTIF_REFERENCE;
        }

        $entete = [
            'client' => $ligne['client'],
            'client_id' => $ligne['client_id'] ?? null,
            'date_vente' => CarbonImmutable::parse($ligne['date_vente'])->utc(),
            'mode' => $ligne['mode'],
            'status' => $ligne['status'],
            'total' => $ligne['total'],
            'paye' => $ligne['paye'],
            'motif_annulation' => $ligne['motif_annulation'] ?? null,
            'livraison_mode' => $ligne['livraison_mode'] ?? null,
            'livraison_frais' => $ligne['livraison_frais'] ?? null,
            'livraison_adresse' => $ligne['livraison_adresse'] ?? null,
            'livraison_contact' => $ligne['livraison_contact'] ?? null,
            'echeance' => empty($ligne['echeance']) ? null : CarbonImmutable::parse($ligne['echeance'])->utc(),
            'ligne_mobile_money' => $ligne['ligne_mobile_money'] ?? null,
        ];

        // `47s_` : le poste de stock se pose à la CRÉATION de la vente et ne change plus (une
        // annulation suit le même poste) ; son absence dans un envoi ne l'efface pas.
        $cible = $ligne['poste_cible'] ?? null;

        if ($existante === null) {
            if (($motif = PosteDeStock::controlerDesignation($deviceId, $cible, PosteDeStock::VENTE)) !== null) {
                return $motif;
            }
            $vente = (new Vente)->forceFill($entete + [
                'id' => $ligne['id'],
                'device_id' => $deviceId,
                'poste_cible' => $cible,
                'reference' => $ligne['reference'],
                'portee_reference' => $portee,
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ]);
            $vente->save();

            foreach (array_values($ligne['lignes']) as $rang => $l) {
                (new LigneVente)->forceFill([
                    'ordre' => $rang,
                    'id' => $l['id'],
                    'vente_id' => $vente->id,
                    'produit_id' => $l['produit_id'],
                    'name' => $l['name'],
                    'qte' => $l['qte'],
                    'pu' => $l['pu'],
                    'espece' => $l['espece'] ?? null,
                ])->save();
            }
        } elseif ($saisie->greaterThan($existante->updated_at)) {
            if ($cible !== null && $cible !== $existante->poste_cible) {
                return $existante->poste_cible !== null
                    ? PosteDeStock::MOTIF_LIEN
                    : 'Cette vente a été saisie sans poste de stock : elle ne peut plus en désigner un.';
            }
            // Dernier ecrivain gagne sur l'ENTETE ; la reference et les lignes ne bougent pas.
            $existante->forceFill($entete + [
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ])->save();
        }

        // Les DEUX clients : celui qui perd la vente (rattachee a un autre, ou a personne)
        // et celui qui la recoit. Sans cela le solde de l'ancien client restait faux.
        $this->recalculerSolde($ligne['client_id'] ?? null);
        if ($ancienClient !== null && $ancienClient !== ($ligne['client_id'] ?? null)) {
            $this->recalculerSolde($ancienClient);
        }

        return null;
    }

    /**
     * `clients.solde_creance` est une donnee DERIVEE : somme des restes dus des ventes en
     * avance non annulees. Calculee par le serveur, jamais acceptee d'un poste.
     */
    private function recalculerSolde(?string $clientId): void
    {
        if ($clientId === null) {
            return;
        }
        $solde = Vente::query()
            ->where('client_id', $clientId)
            ->where('status', 'Avance')
            ->get()
            ->sum(fn (Vente $v) => max(0.0, $v->total - $v->paye));

        Client::query()->whereKey($clientId)->update(['solde_creance' => $solde]);
    }
}
