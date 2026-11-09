<?php

namespace App\Support;

use App\Models\Facture;
use App\Models\GroupeTaxe;
use App\Models\ProduitVendable;
use App\Models\Vente;
use Illuminate\Support\Str;
use InvalidArgumentException;

/**
 * Calcul d'une facture de vente ou d'un avoir, **a l'identique du poste** (`factures_mecef_repository_drift.dart`,
 * `facture_mecef.dart`) — memes operations dans le meme ordre, donc memes nombres (IEEE 754 des deux cotes) :
 *
 *  - les prix du panier sont des montants negocies TOUTES TAXES COMPRISES : ramenes hors taxe selon le groupe du
 *    produit (`ht = ttc / (1 + taux/100)`, `prix_unitaire_ht = ht / qte`) ; facturer le montant negocie en HT puis
 *    y ajouter la taxe ferait payer au client plus que ce qu'il a regle ;
 *  - `montant_ht = qte * prix_unitaire_ht`, `montant_taxe = montant_ht * taux / 100` ;
 *  - AUCUN arrondi n'est stocke (comme le poste) : les montants s'arrondissent a l'affichage seulement ;
 *  - `total_ht` / `total_taxe` sont les sommes des lignes, `total_ttc = total_ht + total_taxe` ;
 *  - groupe du produit absent de la grille : « A » (exonere), comme `GroupeTaxe.parDefaut` : facturer une taxe non
 *    due engage l'entreprise, un oubli se corrige par un avoir.
 */
final class CalculFacture
{
    /** @return array{code: string, taux: float} */
    private static function groupe(string $code): array
    {
        $g = GroupeTaxe::query()->where('code', $code)->first();

        return $g !== null ? ['code' => $g->code, 'taux' => (float) $g->taux] : ['code' => 'A', 'taux' => 0.0];
    }

    /**
     * Lignes de facture d'une vente.
     *
     * @return list<array<string, mixed>>
     */
    public static function lignesDeVente(Vente $vente): array
    {
        $lignes = [];
        foreach ($vente->lignes()->orderBy('id')->get() as $l) {
            if ($l->qte <= 0) {
                throw new InvalidArgumentException("La ligne « {$l->name} » a une quantité nulle : la vente ne peut pas être facturée.");
            }
            $produit = ProduitVendable::query()->find($l->produit_id);
            $g = self::groupe($produit?->groupe_taxe ?? 'A');

            $ttc = $l->qte * $l->pu;
            $ht = $ttc / (1 + $g['taux'] / 100);
            $lignes[] = self::ligne($l->name, (float) $l->qte, $produit?->unit, $ht / $l->qte, $g['code'], $g['taux']);
        }
        if ($lignes === []) {
            throw new InvalidArgumentException('Une facture sans ligne ne facture rien.');
        }

        return $lignes;
    }

    /**
     * Une ligne (montants derives de la quantite et du prix unitaire hors taxe).
     *
     * @return array<string, mixed>
     */
    public static function ligne(string $designation, float $quantite, ?string $unite, float $prixUnitaireHt, string $groupe, float $taux): array
    {
        $montantHt = $quantite * $prixUnitaireHt;

        return [
            'id' => (string) Str::uuid(),
            'designation' => $designation,
            'quantite' => $quantite,
            'unite' => $unite,
            'prix_unitaire_ht' => $prixUnitaireHt,
            'groupe_taxe' => $groupe,
            'taux_taxe' => $taux,
            'montant_ht' => $montantHt,
            'montant_taxe' => $montantHt * $taux / 100,
        ];
    }

    /**
     * Totaux d'une facture : somme des lignes.
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return array{total_ht: float, total_taxe: float, total_ttc: float}
     */
    public static function totaux(array $lignes): array
    {
        $ht = 0.0;
        $taxe = 0.0;
        foreach ($lignes as $l) {
            $ht += $l['montant_ht'];
            $taxe += $l['montant_taxe'];
        }

        return ['total_ht' => $ht, 'total_taxe' => $taxe, 'total_ttc' => $ht + $taxe];
    }

    /**
     * Lignes d'un avoir a partir de celles de la facture corrigee.
     *
     * @param  array<string, float>|null  $quantites  ligne d'origine (id) => quantite creditee ; `null` = avoir total
     * @return list<array<string, mixed>>
     */
    public static function lignesAvoir(Facture $origine, ?array $quantites): array
    {
        $lignes = [];
        foreach ($origine->lignes()->orderBy('id')->get() as $l) {
            $quantite = $quantites === null ? (float) $l->quantite : (float) ($quantites[$l->id] ?? 0);
            if ($quantite <= 0) {
                continue;
            }
            if ($quantite > $l->quantite + 1e-9) {
                throw new InvalidArgumentException("La quantité créditée de « {$l->designation} » dépasse celle de la facture.");
            }
            $lignes[] = self::ligne($l->designation, $quantite, $l->unite, (float) $l->prix_unitaire_ht, $l->groupe_taxe, (float) $l->taux_taxe);
        }
        if ($lignes === []) {
            throw new InvalidArgumentException('Un avoir sans ligne ne corrige rien : indiquez au moins une quantité.');
        }

        return $lignes;
    }
}
