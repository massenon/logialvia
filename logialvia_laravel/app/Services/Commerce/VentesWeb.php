<?php

namespace App\Services\Commerce;

use App\Livewire\Catalogue;
use App\Models\Client;
use App\Models\FicheVentesJour;
use App\Models\ParametresEntreprise;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use App\Services\PosteDeStock;
use App\Services\Comptabilite\EcrituresAutomatiquesVentes as Ecritures;
use App\Services\Comptabilite\Saisie;
use App\Services\Comptabilite\Verrous;
use App\Support\UuidDeterministe;
use App\Sync\Tables\VentesJourTable;
use App\Sync\Tables\VentesTable;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Commerce au web : caisse, annulation, modification, recouvrement. Port de `ventes_view_model.dart`,
 * `ventes_repository_drift.dart` et `clients_view_model.dart`. Le Dart est la source.
 *
 * ## Regles (voir `47a_COMMERCE_PARITE.md`)
 * - Une vente est un FAIT avec ses lignes imbriquees ; elle s'ecrit par `VentesTable::absorber` (meme
 *   validation que pour un poste), device `WEB`, reference `V-WEB-AAAA-NNN` jamais renumerotee.
 * - **Stock propre a chaque poste** (decision du client) : une vente au web ne decremente AUCUN stock.
 * - Le compteur `fiche_ventes_jour` du web (une ligne par poste) suit `46a_` : +qte a la vente, −qte a
 *   l'annulation d'une vente DU WEB (le compteur d'un poste n'est jamais touche par un autre).
 * - Les ecritures (`EcrituresAutomatiquesVentes`) sont passees DANS LA MEME TRANSACTION : si la piece est
 *   refusee (mois cloture, compte archive…), l'operation entiere est refusee avec le motif du serveur.
 *   Le poste, lui, garde la vente sans ecriture (echec avale) : ecart a valider.
 * - Chaque ecriture porte un instant de saisie strictement posterieur a celui de la ligne connue : le web
 *   gagne toujours contre une ligne plus ancienne, jamais ignore en silence (`46a_` D7).
 * - Le droit `manage-ventes` est reverifie ici (en plus du composant) : un appel sans droit est refuse.
 */
final class VentesWeb
{
    public const MODES = ['Espèces', 'Mobile Money'];

    public const COMPTANT = 'Comptant';

    public const AVANCE = 'Avance (Solde Restant Dû)';

    public const CONDITIONS = [self::COMPTANT, self::AVANCE];

    public const MOTIFS_ANNULATION = ['Erreur de saisie', 'Client non honoré', 'Produit indisponible', 'Autre'];

    /** code => libelle (`ModeLivraison` du Dart). */
    public const LIVRAISONS = [
        'gratuite' => 'Livraison gratuite (offerte)',
        'client' => 'Livraison assurée par le client',
        'incluse' => 'Prix de livraison inclus dans le montant',
        'facturee' => 'Livraison facturée séparément',
    ];

    public const CLIENT_COMPTANT = 'Client Comptant';

    private const MOTIF_REFUS_SANS_DROIT = 'Droit insuffisant : enregistrer une vente exige de gérer les ventes.';

    public function __construct(private readonly User $utilisateur) {}

    // -------------------------------------------------------------------- numerotation

    /** `V-WEB-AAAA-NNN` : la sequence est deduite des ventes reellement enregistrees (jamais renumerotee). */
    public static function numeroSuivant(int $annee): string
    {
        $debut = 'V-'.VentesTable::CODE_WEB."-$annee-";
        $maximum = 0;
        foreach (Vente::query()->where('reference', 'like', $debut.'%')->pluck('reference') as $reference) {
            $sequence = substr((string) $reference, strlen($debut));
            if (ctype_digit($sequence) && (int) $sequence > $maximum) {
                $maximum = (int) $sequence;
            }
        }

        return $debut.str_pad((string) ($maximum + 1), 3, '0', STR_PAD_LEFT);
    }

    // ---------------------------------------------------------------------- validations

    /** Total d'un panier `[produit_id, qte, montant]` : la somme des montants SAISIS (jamais qte × prix). */
    public static function totalLignes(array $panier): float
    {
        return array_sum(array_map(fn (array $l) => (float) $l['montant'], $panier));
    }

    /** Supplement d'une livraison : seule une livraison FACTUREE separement s'ajoute au total. */
    public static function supplementLivraison(?array $livraison): float
    {
        return ($livraison['mode'] ?? null) === 'facturee' ? (float) ($livraison['frais'] ?? 0) : 0.0;
    }

    /** `Livraison.valider()` du Dart. */
    public static function validerLivraison(?array $livraison): ?string
    {
        if ($livraison === null) {
            return null;
        }
        if (! array_key_exists($livraison['mode'] ?? '', self::LIVRAISONS)) {
            return 'Le mode de livraison est inconnu.';
        }
        $frais = $livraison['frais'] ?? null;
        if (($livraison['mode'] ?? null) === 'facturee' && ($frais === null || (float) $frais <= 0)) {
            return 'Une livraison facturée séparément exige un montant de frais.';
        }
        if ($frais !== null && (float) $frais < 0) {
            return 'Les frais de livraison ne peuvent pas être négatifs.';
        }

        return null;
    }

    /** La ligne creditee en Mobile Money : le « Telephone Principal » des Parametres Generaux (comme le poste). */
    public static function ligneMobileMoney(): ?string
    {
        $telephone = trim((string) ParametresEntreprise::courant()->telephone);

        return $telephone === '' ? null : $telephone;
    }

    /** `validerAvantEncaissement()` du Dart, message pour message. */
    public static function validerEncaissement(
        array $panier,
        string $mode,
        string $condition,
        float $montantRecu,
        ?array $livraison,
    ): ?string {
        if ($panier === []) {
            return 'Le panier est vide.';
        }
        if ($mode === 'Mobile Money' && self::ligneMobileMoney() === null) {
            return 'Aucun numéro Mobile Money n\'est enregistré. Renseignez le Téléphone Principal dans Paramètres Généraux avant d\'encaisser par Mobile Money.';
        }
        $total = self::totalLignes($panier) + self::supplementLivraison($livraison);
        $avance = $condition === self::AVANCE;
        if ($avance && $montantRecu <= 0) {
            return 'Veuillez saisir le montant reçu pour une vente à crédit.';
        }
        if ($avance && $montantRecu >= $total) {
            // Sinon la vente serait « Avance » avec un reste du nul : une creance sans rien a recouvrer.
            return 'Le montant reçu solde la vente : choisissez « Comptant ».';
        }
        if (! $avance && $montantRecu < $total) {
            return 'Le montant reçu est inférieur au total de la vente.';
        }

        return null;
    }

    // --------------------------------------------------------------------------- caisse

    /**
     * Encaisse une vente. `$d` : `client`, `client_id?`, `mode`, `condition`, `montant_recu`, `lignes`
     * (`[produit_id, qte, montant]`), `livraison?` (`mode`, `frais?`, `adresse?`, `contact?`), `echeance?` (Y-m-d),
     * `poste_cible?` : le POSTE DE STOCK dont le stock est decremente (`47s_`) — verifie (connu, non revoque,
     * deja synchronise, compte qui lit les ventes) ; sans poste, la vente n'est que du journal partage.
     *
     * @return array{motif: ?string, vente: ?Vente}
     */
    public function encaisser(array $d): array
    {
        if (! $this->peutGerer()) {
            return ['motif' => self::MOTIF_REFUS_SANS_DROIT, 'vente' => null];
        }

        $panier = array_values($d['lignes'] ?? []);
        $livraison = $d['livraison'] ?? null;
        $mode = (string) ($d['mode'] ?? '');
        $condition = (string) ($d['condition'] ?? self::COMPTANT);
        $montantRecu = (float) ($d['montant_recu'] ?? 0);

        if ($panier !== [] && ! in_array($mode, self::MODES, true)) {
            return ['motif' => 'Le mode de règlement est inconnu.', 'vente' => null];
        }
        if (! in_array($condition, self::CONDITIONS, true)) {
            return ['motif' => 'La condition de paiement est inconnue.', 'vente' => null];
        }
        foreach ($panier as $l) {
            if (! is_numeric($l['qte'] ?? null) || (float) $l['qte'] < 1 || floor((float) $l['qte']) != (float) $l['qte']
                || ! is_numeric($l['montant'] ?? null) || (float) $l['montant'] <= 0) {
                return ['motif' => 'Veuillez saisir une quantité et un montant valides.', 'vente' => null];
            }
            $produit = ProduitVendable::query()->find($l['produit_id'] ?? '');
            if ($produit === null || $produit->archive_le !== null) {
                return ['motif' => 'Ce produit n\'est plus au catalogue.', 'vente' => null];
            }
        }
        if (($motif = self::validerLivraison($livraison)) !== null
            || ($motif = self::validerEncaissement($panier, $mode, $condition, $montantRecu, $livraison)) !== null) {
            return ['motif' => $motif, 'vente' => null];
        }

        $cible = trim((string) ($d['poste_cible'] ?? ''));
        if ($cible === '') {
            if ($panier !== [] && PosteDeStock::obligatoire()) {
                return ['motif' => PosteDeStock::MOTIF_OBLIGATOIRE, 'vente' => null];
            }
            $cible = null;
        } elseif (($motif = PosteDeStock::verifier($cible, PosteDeStock::VENTE)) !== null) {
            return ['motif' => $motif, 'vente' => null];
        }

        $avance = $condition === self::AVANCE;
        $echeance = null;
        if ($avance && ! empty($d['echeance'])) {
            $echeance = Saisie::instantDuJour((string) $d['echeance']);
            if ($echeance === null) {
                return ['motif' => 'L\'échéance de paiement est invalide.', 'vente' => null];
            }
        }

        $maintenant = CarbonImmutable::now('UTC');
        $total = self::totalLignes($panier) + self::supplementLivraison($livraison);
        $paye = $avance ? $montantRecu : $total; // comptant : solde, pas le montant remis en main
        [$clientId, $nomClient] = $this->clientRetenu((string) ($d['client'] ?? ''), $d['client_id'] ?? null);

        $vente = null;
        $motif = $this->transaction(function () use (&$vente, $d, $panier, $livraison, $mode, $avance, $echeance, $maintenant, $total, $paye, $clientId, $nomClient, $cible) {
            // Reference : si deux comptes valident en meme temps, la seconde est refusee (unicite) → on recompte.
            for ($essai = 0; $essai < 3; $essai++) {
                $annee = (int) $maintenant->timezone(config('logialvia.fuseau'))->year;
                $reference = self::numeroSuivant($annee);
                $id = (string) Str::uuid();
                $refus = (new VentesTable)->absorber(Catalogue::POSTE_WEB, [
                    'id' => $id,
                    'reference' => $reference,
                    'client' => $nomClient,
                    'client_id' => $clientId,
                    'date_vente' => self::iso($maintenant),
                    'mode' => $mode,
                    'status' => $avance ? 'Avance' : 'Payée',
                    'total' => $total,
                    'paye' => $paye,
                    'motif_annulation' => null,
                    'livraison_mode' => $livraison['mode'] ?? null,
                    'livraison_frais' => ($livraison['mode'] ?? null) === 'facturee' ? (float) $livraison['frais'] : null,
                    'livraison_adresse' => $this->texte($livraison['adresse'] ?? null),
                    'livraison_contact' => $this->texte($livraison['contact'] ?? null),
                    'echeance' => $echeance,
                    'ligne_mobile_money' => $mode === 'Mobile Money' ? self::ligneMobileMoney() : null,
                    'poste_cible' => $cible,
                    'updated_at' => self::iso($maintenant),
                    'lignes' => array_map(function (array $l) {
                        $produit = ProduitVendable::query()->find($l['produit_id']);

                        return [
                            'id' => (string) Str::uuid(),
                            'produit_id' => $produit->id,
                            'name' => $produit->name,
                            'qte' => (float) $l['qte'],
                            'pu' => (float) $l['montant'] / (float) $l['qte'], // DEDUIT : jamais saisi, jamais multiplie
                            'espece' => $produit->espece,
                        ];
                    }, $panier),
                ]);
                if ($refus === VentesTable::MOTIF_REFERENCE) {
                    continue;
                }
                if ($refus !== null) {
                    return $refus;
                }
                $vente = Vente::query()->with('lignes')->find($id);
                break;
            }
            if ($vente === null) {
                return 'La référence de la vente n\'a pas pu être attribuée : réessayez.';
            }

            // 1. compteur de ventes du jour du web, 2. ecritures — dans la meme transaction.
            foreach ($vente->lignes as $l) {
                if ($l->espece !== null) {
                    $this->ajusterCompteurDuJour($l->espece, $vente->date_vente, (int) round($l->qte));
                }
            }

            return $this->ecrituresEncaissement($vente, $panier);
        });

        if ($motif === null) {
            PosteDeStock::memoriser($this->utilisateur, PosteDeStock::VENTE, $cible);
        }

        return $motif === null ? ['motif' => null, 'vente' => $vente] : ['motif' => $motif, 'vente' => null];
    }

    private function ecrituresEncaissement(Vente $vente, array $panier): ?string
    {
        $lignes = Ecritures::lignesVente(
            $vente->reference, $vente->mode, $vente->total, $vente->paye,
            Ecritures::ventiler(array_map(fn (array $l) => ['produit_id' => $l['produit_id'], 'montant' => $l['montant']], $panier)),
            $vente->livraison_mode === 'facturee' ? (float) $vente->livraison_frais : 0.0,
        );

        return (new Ecritures($this->utilisateur))->enregistrer(
            CarbonImmutable::instance($vente->date_vente), 'VT', $vente->reference, $lignes, $vente->reference,
        );
    }

    // ------------------------------------------------------------------------ annulation

    /** Annule une vente (annulation LOGIQUE, BR-VTE-004) et contrepasse ses ecritures. */
    public function annuler(string $venteId, ?string $motif): ?string
    {
        if (! $this->peutGerer()) {
            return self::MOTIF_REFUS_SANS_DROIT;
        }
        $motif = trim((string) $motif);
        if ($motif === '') {
            return 'Le motif d\'annulation est obligatoire.';
        }
        if (mb_strlen($motif) > 255) {
            return 'Le motif d\'annulation est trop long.';
        }

        return $this->transaction(function () use ($venteId, $motif) {
            $vente = Vente::query()->with('lignes')->lockForUpdate()->find($venteId);
            if ($vente === null) {
                return 'Cette vente n\'existe plus.';
            }
            if ($vente->status === 'Annulée') {
                return "Vente {$vente->reference} déjà annulée.";
            }

            // La contrepassation reprend ce que le grand livre porte REELLEMENT pour cette vente.
            $pieces = Ecritures::piecesDeLaVente($vente);
            $lignes = Ecritures::lignesAnnulation($vente->reference, Ecritures::netsDeLaVente($vente));
            if ($lignes === []) {
                return $pieces->isEmpty()
                    ? 'Les écritures de cette vente ne sont pas encore parvenues au serveur : synchronisez le poste qui l\'a saisie avant de l\'annuler.'
                    : 'Les écritures de cette vente sont déjà contrepassées.';
            }

            $refus = $this->ecrireEntete($vente, ['status' => 'Annulée', 'motif_annulation' => $motif]);
            if ($refus !== null) {
                return $refus;
            }

            // Le compteur d'UN poste ne se corrige que par ce poste : au web, seulement une vente du web.
            if ($vente->device_id === Catalogue::POSTE_WEB) {
                foreach ($vente->lignes as $l) {
                    if ($l->espece !== null) {
                        $this->ajusterCompteurDuJour($l->espece, $vente->date_vente, -(int) round($l->qte));
                    }
                }
            }

            return (new Ecritures($this->utilisateur))->enregistrer(
                CarbonImmutable::now('UTC'), 'OD', 'ANN-'.$vente->reference, $lignes, $vente->reference,
            );
        });
    }

    // ----------------------------------------------------------------------- modification

    /** Champs modifiables d'une vente : aucun n'a d'effet comptable (le reste passe par l'annulation ou le recouvrement). */
    public const CHAMPS_MODIFIABLES = ['client', 'client_id', 'echeance', 'livraison_adresse', 'livraison_contact'];

    /**
     * Modifie les champs autorises d'une vente. `$champs` : `client` (nom), `client_id?`, `echeance?` (Y-m-d ou ''),
     * `livraison_adresse?`, `livraison_contact?`. Les autres cles sont refusees.
     */
    public function modifier(string $venteId, array $champs): ?string
    {
        if (! $this->peutGerer()) {
            return self::MOTIF_REFUS_SANS_DROIT;
        }
        $inconnus = array_diff(array_keys($champs), self::CHAMPS_MODIFIABLES);
        if ($inconnus !== []) {
            return 'Ce champ ne se modifie pas : '.array_values($inconnus)[0].'. Annulez la vente pour la corriger.';
        }

        return $this->transaction(function () use ($venteId, $champs) {
            $vente = Vente::query()->with('lignes')->lockForUpdate()->find($venteId);
            if ($vente === null) {
                return 'Cette vente n\'existe plus.';
            }
            if ($vente->status === 'Annulée') {
                return 'Une vente annulée ne se modifie pas.';
            }

            $surcharge = [];
            if (array_key_exists('client', $champs) || array_key_exists('client_id', $champs)) {
                $nom = trim((string) ($champs['client'] ?? $vente->client));
                if ($nom === '') {
                    return 'Le client de la vente est obligatoire.';
                }
                if (mb_strlen($nom) > 255) {
                    return 'Le nom du client est trop long.';
                }
                if (! empty($champs['client_id']) && ! Client::query()->whereNull('supprime_le')->whereKey($champs['client_id'])->exists()) {
                    return 'Ce client n\'existe plus.';
                }
                [$clientId, $nomRetenu] = $this->clientRetenu($nom, $champs['client_id'] ?? null);
                $surcharge['client'] = $nomRetenu;
                $surcharge['client_id'] = $clientId;
            }
            if (array_key_exists('echeance', $champs)) {
                if (($champs['echeance'] ?? '') === '' || $champs['echeance'] === null) {
                    $surcharge['echeance'] = null;
                } else {
                    if ($vente->status !== 'Avance') {
                        return 'Une vente soldée n\'a pas d\'échéance de paiement.';
                    }
                    $instant = Saisie::instantDuJour((string) $champs['echeance']);
                    if ($instant === null) {
                        return 'L\'échéance de paiement est invalide.';
                    }
                    $surcharge['echeance'] = $instant;
                }
            }
            foreach (['livraison_adresse', 'livraison_contact'] as $cle) {
                if (array_key_exists($cle, $champs)) {
                    if ($vente->livraison_mode === null && $this->texte($champs[$cle]) !== null) {
                        return 'Cette vente n\'a pas de livraison.';
                    }
                    $valeur = $this->texte($champs[$cle]);
                    if ($valeur !== null && mb_strlen($valeur) > 255) {
                        return 'Le texte de livraison est trop long.';
                    }
                    $surcharge[$cle] = $valeur;
                }
            }

            return $this->ecrireEntete($vente, $surcharge);
        });
    }

    // ----------------------------------------------------------------------- recouvrement

    /**
     * Recouvrement (total ou partiel) d'une creance : `paye` augmente, la vente passe « Payée » une fois soldee,
     * piece `REG-<reference>` (tresorerie au debit, 411 au credit). Le solde du client est RECALCULE par le serveur.
     */
    public function recouvrer(string $venteId, float $montant, string $mode): ?string
    {
        if (! $this->peutGerer()) {
            return self::MOTIF_REFUS_SANS_DROIT;
        }
        if ($montant <= 0) {
            return 'Le montant recouvré doit être supérieur à 0.';
        }
        if (! in_array($mode, self::MODES, true)) {
            return 'Le mode de règlement est inconnu.';
        }

        return $this->transaction(function () use ($venteId, $montant, $mode) {
            $vente = Vente::query()->with('lignes')->lockForUpdate()->find($venteId);
            if ($vente === null) {
                return 'Cette vente n\'existe plus.';
            }
            if ($vente->status === 'Annulée') {
                return 'Une vente annulée ne peut pas être encaissée.';
            }
            $reste = max(0.0, $vente->total - $vente->paye);
            if ($vente->status !== 'Avance' || $reste < 0.005) {
                return 'Cette vente est déjà soldée : il n\'y a rien à recouvrer.';
            }
            if ($montant > $reste + 0.005) {
                return sprintf('Le montant dépasse le reste dû (%s FCFA).', number_format($reste, 0, ',', ' '));
            }
            if ($mode === 'Mobile Money' && self::ligneMobileMoney() === null) {
                return 'Aucun numéro Mobile Money n\'est enregistré. Renseignez le Téléphone Principal dans Paramètres Généraux avant d\'encaisser par Mobile Money.';
            }

            $solde = $montant >= $reste - 0.005; // soldee : `paye` vaut exactement le total
            $refus = $this->ecrireEntete($vente, [
                'paye' => $solde ? $vente->total : $vente->paye + $montant,
                'status' => $solde ? 'Payée' : 'Avance',
            ]);
            if ($refus !== null) {
                return $refus;
            }

            return (new Ecritures($this->utilisateur))->enregistrer(
                CarbonImmutable::now('UTC'), 'CA', 'REG-'.$vente->reference,
                Ecritures::lignesReglement($vente->reference, $mode, $solde ? $reste : $montant), $vente->reference,
            );
        });
    }

    // --------------------------------------------------------------------------- internes

    private function peutGerer(): bool
    {
        return $this->utilisateur->can('manage-ventes');
    }

    /** Execute `$f` dans une transaction ; un motif de refus (retour non nul) l'ANNULE entierement. */
    private function transaction(callable $f): ?string
    {
        try {
            DB::transaction(function () use ($f) {
                $motif = $f();
                if ($motif !== null) {
                    throw new RefusDeVente($motif);
                }
            });
        } catch (RefusDeVente $e) {
            return $e->getMessage();
        }

        return null;
    }

    /**
     * Reecrit l'ENTETE d'une vente par `VentesTable::absorber` (les lignes sont immuables, mais la table
     * exige de les recevoir). Instant de saisie : strictement apres celui de la ligne connue.
     *
     * @param  array<string, mixed>  $surcharge  colonnes de l'entete a changer
     */
    private function ecrireEntete(Vente $vente, array $surcharge): ?string
    {
        $entete = [
            'id' => $vente->id,
            'reference' => $vente->reference,
            'client' => $vente->client,
            'client_id' => $vente->client_id,
            'date_vente' => self::iso($vente->date_vente),
            'mode' => $vente->mode,
            'status' => $vente->status,
            'total' => $vente->total,
            'paye' => $vente->paye,
            'motif_annulation' => $vente->motif_annulation,
            'livraison_mode' => $vente->livraison_mode,
            'livraison_frais' => $vente->livraison_frais,
            'livraison_adresse' => $vente->livraison_adresse,
            'livraison_contact' => $vente->livraison_contact,
            'echeance' => $vente->echeance === null ? null : self::iso($vente->echeance),
            'ligne_mobile_money' => $vente->ligne_mobile_money,
            // `47s_` : le poste de stock est lie a la vente ; toute reecriture de l'entete le reprend.
            'poste_cible' => $vente->poste_cible,
            'updated_at' => self::instantApres($vente->updated_at),
            'lignes' => $vente->lignes->map(fn ($l) => [
                'id' => $l->id, 'produit_id' => $l->produit_id, 'name' => $l->name,
                'qte' => $l->qte, 'pu' => $l->pu, 'espece' => $l->espece,
            ])->all(),
        ];

        // La ligne est celle de l'ORIGINE : un poste qui avait vendu garde son `device_id`.
        return (new VentesTable)->absorber(Catalogue::POSTE_WEB, array_merge($entete, $surcharge));
    }

    /**
     * Le client CHOISI s'il existe ; sinon celui que designe le nom, s'il n'y en a qu'un (casse et espaces
     * ignores). Deux homonymes : `null`, on ne devine pas qui a achete.
     *
     * @return array{0: ?string, 1: string} [client_id, nom a ecrire sur la vente]
     */
    private function clientRetenu(string $nom, mixed $clientId): array
    {
        if (is_string($clientId) && $clientId !== '') {
            $client = Client::query()->whereNull('supprime_le')->find($clientId);
            if ($client !== null) {
                return [$client->id, $client->nom];
            }
        }
        $nom = trim($nom) === '' ? self::CLIENT_COMPTANT : trim($nom);
        $cherche = mb_strtolower($nom);
        $trouves = Client::query()->whereNull('supprime_le')->get()
            ->filter(fn (Client $c) => mb_strtolower(trim($c->nom)) === $cherche);

        return [$trouves->count() === 1 ? $trouves->first()->id : null, $nom];
    }

    /** Compteur de ventes du jour DU WEB (`46a_` §3.2) : `qte` remplacee, jamais negative, ligne unique par (filiere, jour). */
    private function ajusterCompteurDuJour(string $espece, CarbonInterface $dateVente, int $delta): void
    {
        $jour = CarbonImmutable::instance($dateVente)->timezone(config('logialvia.fuseau'))->format('Y-m-d');
        $id = UuidDeterministe::ventesJour($espece, $jour, Catalogue::POSTE_WEB);
        $existant = FicheVentesJour::query()->find($id);
        if ($existant === null && $delta <= 0) {
            return;
        }

        $refus = (new VentesJourTable)->absorber(Catalogue::POSTE_WEB, [
            'id' => $id,
            'espece' => $espece,
            'date' => $jour,
            'qte' => max(0, ($existant?->qte ?? 0) + $delta),
            'updated_at' => self::instantApres($existant?->updated_at),
        ]);
        if ($refus !== null) {
            throw new RefusDeVente($refus);
        }
    }

    private function texte(mixed $valeur): ?string
    {
        $valeur = trim((string) $valeur);

        return $valeur === '' ? null : $valeur;
    }

    private static function iso(CarbonInterface $instant): string
    {
        return CarbonImmutable::instance($instant)->utc()->format('Y-m-d\TH:i:s.u\Z');
    }

    /** Maintenant, ou 1 µs apres l'instant connu s'il est dans le futur (horloge d'un poste en avance). */
    private static function instantApres(?CarbonInterface $connu): string
    {
        $maintenant = CarbonImmutable::now('UTC');
        if ($connu !== null && $maintenant->lessThanOrEqualTo($connu)) {
            $maintenant = CarbonImmutable::instance($connu)->utc()->addMicrosecond();
        }

        return self::iso($maintenant);
    }
}
