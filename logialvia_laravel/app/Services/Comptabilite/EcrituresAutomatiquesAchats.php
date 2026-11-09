<?php

namespace App\Services\Comptabilite;

use App\Models\PieceComptable;
use Illuminate\Support\Collection;

/**
 * Ecritures AUTOMATIQUES des achats d'intrants : port fidele de `GenererEcrituresAutomatiques`
 * (Dart : `comptabilite/domain/usecases/generer_ecritures_automatiques.dart`, `pourAchat` et
 * `pourReglement`), BR-CPT-003, plus l'extourne d'un achat annule.
 *
 * ## Ce que le Dart fait (et que ce service reproduit a l'identique)
 * ```
 * Achat (journal AC, piece = reference de l'achat, achat_ref = reference)
 *   601|602|622  D  total ventile par categorie d'intrant   « Achat <ref> »
 *   531 ou 512   C  paye                                     « Règlement achat <ref> »
 *   401          C  total − paye                             « Dette fournisseur — achat <ref> »
 * Reglement (journal CA, piece = REG-<ref>, achat_ref = reference)
 *   401          D  montant                                  « Règlement dette <ref> »
 *   531 ou 512   C  montant                                  « Règlement dette <ref> »
 * ```
 * - **La charge est constatee a la COMMANDE**, pas a la reception : le Dart ecrit la piece dans
 *   `enregistrerAchat` que la commande soit livree ou non, et `receptionnerAchat` n'ecrit rien.
 * - Ventilation : categorie « Vétérinaire » → 622, « Marchandises » → 602, le reste → 601.
 * - Tresorerie : « Mobile Money » → 512, tout le reste (Espèces, Crédit, Non précisé) → 531.
 * - **Pas de TVA** : le Dart n'en genere pas sur les achats (aucun 4452 au plan comptable du poste) ;
 *   le web fait de meme.
 *
 * ## Ce que le web ajoute (le Dart ne le fait pas)
 * - **Extourne** (`annuler`) : le Dart n'annule pas un achat. Le web contrepasse chaque piece vivante
 *   de l'achat (la piece d'achat, ses reglements) par `Saisie::contrepasser` : pieces `ANN-<numero>`,
 *   journal OD, a la date du jour, sens inverse, meme compte, verifiees ligne a ligne par le serveur.
 * - Les montants sont arrondis au centime (`round(…, 2)`) : un prix a deux decimales ne laisse jamais
 *   un reste de virgule flottante qui desequilibrerait la piece (tolerance du serveur : 0,01).
 */
final class EcrituresAutomatiquesAchats
{
    public const CAISSE = '531';

    public const MOBILE_MONEY = '512';

    public const FOURNISSEURS = '401';

    public const ACHATS_MATIERES = '601';

    public const ACHATS_MARCHANDISES = '602';

    public const FRAIS_VETERINAIRES = '622';

    public function __construct(private readonly Saisie $saisie) {}

    /** Compte de tresorerie du mode de reglement (Dart : `tresoreriePour`). */
    public static function tresoreriePour(?string $mode): string
    {
        return $mode === 'Mobile Money' ? self::MOBILE_MONEY : self::CAISSE;
    }

    /**
     * Ventile les lignes d'un achat entre les comptes de charge selon la categorie de l'intrant
     * (Dart : `_ventilerAchat`). L'ordre des comptes est celui de la premiere apparition.
     *
     * @param  iterable<array{intrant_code: string, qte: float|int|string, pu_achat: float|int|string}>  $lignes
     * @param  array<string, string>  $categories  code d'intrant => categorie
     * @return array<string, float> compte => montant
     */
    public static function ventiler(iterable $lignes, array $categories): array
    {
        $ventilation = [];
        foreach ($lignes as $l) {
            $compte = match ($categories[$l['intrant_code']] ?? null) {
                'Vétérinaire' => self::FRAIS_VETERINAIRES,
                'Marchandises' => self::ACHATS_MARCHANDISES,
                default => self::ACHATS_MATIERES,
            };
            $ventilation[$compte] = round(($ventilation[$compte] ?? 0) + (float) $l['qte'] * (float) $l['pu_achat'], 2);
        }

        return $ventilation;
    }

    /**
     * Piece d'achat (Dart : `pourAchat`). Rien n'est ecrit si le total n'est pas positif.
     *
     * @param  array<string, float>  $ventilation  compte => montant
     * @return string|null Le motif du refus, ou `null` (piece acceptee, ou rien a ecrire).
     */
    public function pourAchat(
        string $reference,
        string $instant,
        ?string $mode,
        float $total,
        float $paye,
        array $ventilation,
    ): ?string {
        if ($total <= 0) {
            return null;
        }

        $lignes = [];
        foreach ($ventilation as $compte => $montant) {
            if ($montant <= 0) {
                continue;
            }
            $lignes[] = ['compte' => (string) $compte, 'debit' => round($montant, 2), 'credit' => 0, 'libelle' => "Achat $reference"];
        }

        $paye = round($paye, 2);
        $resteDu = round(min(max($total - $paye, 0.0), $total), 2);
        if ($paye > 0) {
            $lignes[] = ['compte' => self::tresoreriePour($mode), 'debit' => 0, 'credit' => $paye, 'libelle' => "Règlement achat $reference"];
        }
        if ($resteDu > 0) {
            $lignes[] = ['compte' => self::FOURNISSEURS, 'debit' => 0, 'credit' => $resteDu, 'libelle' => "Dette fournisseur — achat $reference"];
        }

        return $this->saisie->enregistrer($instant, 'AC', $reference, $lignes, null, $reference);
    }

    /**
     * Reglement d'une dette fournisseur (Dart : `pourReglement`, `estEncaissement: false`).
     * `$montant` est le montant REELLEMENT verse (borne au reste du), jamais le montant saisi.
     */
    public function pourReglement(string $reference, string $instant, ?string $mode, float $montant): ?string
    {
        if ($montant <= 0) {
            return null;
        }
        $montant = round($montant, 2);

        return $this->saisie->enregistrer($instant, 'CA', "REG-$reference", [
            ['compte' => self::FOURNISSEURS, 'debit' => $montant, 'credit' => 0, 'libelle' => "Règlement dette $reference"],
            ['compte' => self::tresoreriePour($mode), 'debit' => 0, 'credit' => $montant, 'libelle' => "Règlement dette $reference"],
        ], null, $reference);
    }

    /**
     * Pieces VIVANTES d'un achat : celles qui portent sa reference, qui ne sont pas elles-memes une
     * contrepassation et qu'aucune contrepassation n'a deja annulees.
     *
     * @return Collection<int, PieceComptable>
     */
    public static function piecesVivantes(string $reference): Collection
    {
        $pieces = PieceComptable::query()->where('achat_ref', $reference)->orderBy('date_ecriture')->orderBy('updated_at')->get();
        $annulees = $pieces->whereNotNull('contrepasse_de')->pluck('contrepasse_de')->flip();

        return $pieces->filter(fn (PieceComptable $p) => $p->contrepasse_de === null && ! $annulees->has($p->id))->values();
    }

    /**
     * Extourne : contrepasse toutes les pieces vivantes de l'achat (la piece d'achat et ses
     * reglements), a la date du jour. `$motif` figure dans le libelle de chaque ligne inverse.
     *
     * @return string|null Le motif du premier refus (l'appelant annule alors sa transaction).
     */
    public function extourner(string $reference, ?string $motif = null): ?string
    {
        foreach (self::piecesVivantes($reference) as $piece) {
            $refus = $this->saisie->contrepasser($piece->id, true, $motif);
            if ($refus !== null) {
                return $refus;
            }
        }

        return null;
    }
}
