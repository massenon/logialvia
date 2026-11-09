<?php

namespace App\Services\Comptabilite;

use App\Livewire\Catalogue;
use App\Models\PieceComptable;
use App\Models\Poste;
use App\Models\User;
use App\Sync\Tables\EcrituresTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Saisie d'ecritures depuis le web : TOUJOURS par `EcrituresTable::absorber`, comme un poste.
 * Memes validations, memes motifs de refus, meme double verrouillage, meme equilibre. Jamais
 * d'`update` direct : une piece acceptee est un fait IMMUABLE, se corriger c'est la CONTREPASSER.
 *
 * Le web est un « poste » de code `WEB` : ses pieces portent le prefixe de poste (DV-21),
 * `OD-WEB-2026-0001`, et ne sont jamais renumerotees.
 */
final class Saisie
{
    public const CODE_POSTE = 'WEB';

    public function __construct(private readonly User $utilisateur) {}

    public static function instantMaintenant(): string
    {
        return CarbonImmutable::now('UTC')->format('Y-m-d\TH:i:s.u\Z');
    }

    /** Un jour saisi (Y-m-d) devient l'instant de midi dans le fuseau de l'exploitation. */
    public static function instantDuJour(string $jour): ?string
    {
        try {
            $date = CarbonImmutable::createFromFormat('!Y-m-d', $jour, config('logialvia.fuseau'));
        } catch (\Throwable) {
            return null;
        }
        if ($date === false || $date->format('Y-m-d') !== $jour) {
            return null;
        }

        return $date->setTime(12, 0)->utc()->format('Y-m-d\TH:i:s.u\Z');
    }

    /** `PREFIXE-WEB-AAAA-NNNN` : la sequence est deduite des pieces reellement enregistrees. */
    public static function numeroSuivant(string $prefixe, int $annee): string
    {
        $debut = "$prefixe-".self::CODE_POSTE."-$annee-";
        $maximum = 0;
        foreach (PieceComptable::query()->where('numero_piece', 'like', $debut.'%')->pluck('numero_piece') as $numero) {
            $sequence = substr((string) $numero, strlen($debut));
            if (ctype_digit($sequence) && (int) $sequence > $maximum) {
                $maximum = (int) $sequence;
            }
        }

        return $debut.str_pad((string) ($maximum + 1), 4, '0', STR_PAD_LEFT);
    }

    /**
     * Enregistre une piece. `$lignes` : `[compte, debit, credit, libelle, axe?]`.
     *
     * @return string|null Le motif du refus, ou `null` si la piece est acceptee.
     */
    public function enregistrer(
        string $instant,
        string $journal,
        string $numeroPiece,
        array $lignes,
        ?string $contrepasseDe = null,
        ?string $achatRef = null,
    ): ?string {
        $date = CarbonImmutable::parse($instant)->utc();
        [$annee] = Verrous::anneeMois($date);

        $piece = [
            'id' => (string) Str::uuid(),
            'numero_piece' => $numeroPiece,
            'date_ecriture' => $date->format('Y-m-d\TH:i:s.u\Z'),
            'exercice_annee' => $annee,
            'journal_code' => $journal,
            'vente_ref' => null,
            'achat_ref' => $achatRef,
            'contrepasse_de' => $contrepasseDe,
            'updated_at' => self::instantMaintenant(),
            'lignes' => array_map(fn (array $l) => [
                'id' => (string) Str::uuid(),
                'numero_compte' => $l['compte'],
                'debit' => (float) $l['debit'],
                'credit' => (float) $l['credit'],
                'libelle' => $l['libelle'],
                'axe_analytique' => $l['axe'] ?? null,
            ], $lignes),
        ];

        // Une piece est tout ou rien : la transaction que le moteur de synchronisation ouvre
        // pour un lot, le web l'ouvre ici pour sa piece.
        return DB::transaction(
            fn () => (new EcrituresTable)->pourUtilisateur($this->utilisateur)->absorber(Catalogue::POSTE_WEB, $piece),
        );
    }

    /**
     * Contrepasse une piece : l'ecriture INVERSE, a la date du jour, journal OD, numero
     * `ANN-<numero>`. Le serveur verifie qu'elle reprend la piece ligne pour ligne, qu'elle n'est
     * annulee qu'une fois et qu'une annulation ne s'annule pas.
     */
    public function contrepasser(string $pieceId, bool $automatique = false, ?string $motif = null): ?string
    {
        $originale = PieceComptable::query()->with('lignes')->find($pieceId);
        if ($originale === null) {
            return 'Cette pièce n\'existe plus.';
        }
        // Une piece AUTOMATIQUE (vente, achat) ne s'annule pas a la main : on annule l'operation
        // d'origine, qui la contrepasse elle-meme (`$automatique = true`, seul appel permis).
        if (! $automatique && ($originale->vente_ref !== null || $originale->achat_ref !== null)) {
            return 'Cette pièce est générée automatiquement par '.($originale->vente_ref ?? $originale->achat_ref)
                .'. Annulez l\'opération d\'origine plutôt que l\'écriture.';
        }

        return $this->enregistrer(
            self::instantMaintenant(),
            'OD',
            'ANN-'.($originale->numero_piece ?? substr($originale->id, 0, 8)),
            $originale->lignes->map(fn ($l) => [
                'compte' => $l->numero_compte,
                'debit' => $l->credit,
                'credit' => $l->debit,
                'libelle' => mb_substr('Annulation — '.$l->libelle.($motif !== null ? " ($motif)" : ''), 0, 255),
                'axe' => $l->axe_analytique,
            ])->all(),
            $originale->id,
            $originale->achat_ref,
        );
    }

    /** Poste d'origine d'une piece : « Web », son code (`P2`), ou repli sur l'identifiant. */
    public static function libellePoste(string $deviceId, array $codes): string
    {
        if ($deviceId === Catalogue::POSTE_WEB) {
            return 'Web';
        }

        return $codes[$deviceId] ?? 'Poste '.Str::substr($deviceId, 0, 8);
    }

    /** @return array<string, string> device_id => code du poste */
    public static function codesDesPostes(): array
    {
        return Poste::query()->pluck('code', 'device_id')->all();
    }
}
