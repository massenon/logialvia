<?php

namespace App\Services\Commerce;

use App\Livewire\Catalogue;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Services\Comptabilite\Saisie;
use App\Services\PosteDeStock;
use App\Support\Audit;
use App\Sync\Tables\MouvementsProduitTable;
use Illuminate\Support\Str;

/**
 * Correction du stock d'un produit vendable saisie au web (`47s_`).
 *
 * Le web n'a pas de stock : une correction DÉSIGNE le poste dont le stock la subit. Elle s'écrit au
 * journal partagé (`mouvements_produit`, poste d'origine : web) avec `poste_cible` ; le poste désigné,
 * et lui seul, ajoute la variation signée à SON stock en absorbant la ligne — une seule fois,
 * plancher à 0 avec avertissement tracé. Les autres postes la lisent comme de l'historique.
 *
 * Le poste est OBLIGATOIRE ici : une correction sans poste ne corrigerait rien. Droit : `manage-stocks`
 * ou `manage-ventes`, vérifié à chaque appel (comme l'écriture du journal par un poste).
 */
final class CorrectionsStockWeb
{
    public const MOTIF_VARIATION = 'La variation de stock doit être un entier non nul (négatif pour retirer).';

    public const MOTIF_JUSTIFICATION = 'Indiquez le motif de la correction de stock.';

    public function __construct(private readonly User $utilisateur) {}

    /**
     * @param  mixed  $variation  entier signé, jamais nul
     * @return string|null le motif du refus, `null` si la correction est inscrite
     */
    public function corriger(string $produitId, mixed $variation, ?string $motif, ?string $poste): ?string
    {
        abort_unless($this->utilisateur->can('manage-stocks') || $this->utilisateur->can('manage-ventes'), 403);

        $produit = ProduitVendable::query()->whereNull('archive_le')->find($produitId);
        if ($produit === null) {
            return "Ce produit n'est plus au catalogue.";
        }
        $texte = trim(str_replace([' ', ','], ['', '.'], (string) $variation));
        if (! is_numeric($texte) || floor((float) $texte) != (float) $texte || (int) $texte === 0) {
            return self::MOTIF_VARIATION;
        }
        $motif = trim((string) $motif);
        if ($motif === '') {
            return self::MOTIF_JUSTIFICATION;
        }
        if (mb_strlen($motif) > 255) {
            return 'Le motif de la correction est trop long.';
        }
        $poste = trim((string) $poste);
        if ($poste === '') {
            return 'Désignez le poste dont le stock est corrigé : le web n\'a pas de stock.';
        }
        if (($refus = PosteDeStock::verifier($poste, PosteDeStock::CORRECTION)) !== null) {
            return $refus;
        }

        $refus = (new MouvementsProduitTable)->absorber(Catalogue::POSTE_WEB, [
            'id' => (string) Str::uuid(),
            'horodatage' => Saisie::instantMaintenant(),
            'produit_id' => $produit->id,
            'article' => $produit->name,
            'motif' => $motif,
            'quantite' => (int) $texte,
            'poste_cible' => $poste,
        ]);
        if ($refus !== null) {
            return $refus;
        }

        PosteDeStock::memoriser($this->utilisateur, PosteDeStock::CORRECTION, $poste);
        Audit::enregistrer('stock.correction_produit_web', $this->utilisateur, [
            'produit' => $produit->name, 'variation' => (int) $texte, 'poste' => PosteDeStock::code($poste),
        ]);

        return null;
    }
}
