<?php

namespace App\Sync\Tables;

use App\Livewire\Catalogue;
use App\Models\Facture;
use App\Models\LigneFacture;
use App\Models\Poste;
use App\Models\User;
use App\Sync\TableSync;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * Factures (FV) et factures d'avoir (FA) : FAITS saisis au poste, jamais fusionnes (`46e_`).
 *
 *  - une facture et ses lignes forment UN lot : acceptees ou refusees ensemble, servies ensemble au
 *    tirage (`lignes` imbriquees) ; les lignes et tout le contenu sont IMMUABLES apres creation
 *    (corriger une facture emise = emettre un avoir) ;
 *  - `reference` est le numero OFFICIEL (DV-21), jamais renumerote : unique pour tous quand elle
 *    porte un code de poste (`FV-P2-2026-001`), unique PAR POSTE sinon ;
 *  - UNE facture de vente par vente, et un avoir ne vise qu'une facture de vente connue ;
 *  - **le serveur ne transmet JAMAIS a la DGI** : il n'a ni jeton ni URL e-MECeF, il enregistre ce que
 *    le poste emetteur a obtenu (statut, code de normalisation, NIM imprime sur la facture) ;
 *  - **le statut ne regresse jamais** (rang : a_transmettre < rejetee < normalisee). Entre deux postes
 *    qui divergent, c'est le RANG qui l'emporte, pas l'horloge ; deux rejets : le plus recent. Une facture
 *    normalisee est IMMUABLE : un second code différent est REFUSE avec son motif, jamais departage en silence ;
 *  - **facture emise au WEB** (`FV-WEB-AAAA-NNN`, `device_id` = poste web, sans poste emetteur) : n'importe quel poste
 *    appaire disposant de `manage-facturation` peut la transmettre, mais seulement apres l'avoir RESERVEE
 *    (`reserverTransmission`, un seul poste a la fois, {@see self::DUREE_RESERVATION_MINUTES} min) ; seul le detenteur
 *    peut ensuite envoyer sa normalisation ou son rejet. Un rejet libere la reservation (`47a2_`).
 */
class FacturesTable extends TableSync
{
    public const TYPES = ['FV', 'FA'];

    public const STATUTS = ['a_transmettre', 'rejetee', 'normalisee'];

    /** Rang de la machine a etats. */
    public const RANG = ['a_transmettre' => 0, 'rejetee' => 1, 'normalisee' => 2];

    public const MOTIF_REFERENCE = 'Cette référence est déjà utilisée par une autre facture.';

    public const MOTIF_IMMUABLE = 'Une facture émise ne se modifie pas : émettez un avoir.';

    /** Duree de la reservation d'une transmission (facture emise au web). */
    public const DUREE_RESERVATION_MINUTES = 15;

    public const MOTIF_RESERVATION = 'Cette facture a été émise au web : sa transmission doit être réservée au serveur avant d\'être envoyée.';

    /** Tolerance d'arrondi entre un total et la somme de ses lignes (FCFA). */
    private const TOLERANCE = 0.01;

    public function nom(): string
    {
        return 'factures';
    }

    public function nature(): string
    {
        return self::FAIT;
    }

    protected function modele(): string
    {
        return Facture::class;
    }

    public function colonneCurseur(): string
    {
        return 'serveur_modifie_le';
    }

    public function droitLecture(): ?string
    {
        return 'view-facturation';
    }

    public function droitEcriture(): ?string
    {
        return 'manage-facturation';
    }

    /** Une reference a code de poste est globale ; sans code, elle est propre au poste. */
    public static function porteeReference(string $reference, string $deviceId): string
    {
        return preg_match('/^F[VA]-(P\d+|WEB)-\d{4}-\d{3,}$/', $reference) === 1 ? '' : $deviceId;
    }

    /** Une reference de VENTE a code de poste est globale ; sans code, elle est propre au poste. */
    private static function venteGlobale(string $venteRef): bool
    {
        return preg_match('/^V-(P\d+|WEB)-\d{4}-\d{3,}$/', $venteRef) === 1;
    }

    public function exporter(Model $ligne): array
    {
        $donnees = parent::exporter($ligne);
        // Details d'implementation du serveur : jamais servis.
        unset($donnees['portee_reference'], $donnees['transmission_poste'], $donnees['transmission_reservee_jusqua']);
        $donnees['lignes'] = $ligne->lignes()->orderBy('id')->get()
            ->map(fn (LigneFacture $l) => $l->attributesToArray())
            ->all();

        return $donnees;
    }

    public function absorber(string $deviceId, array $ligne): ?string
    {
        $motif = $this->valider($ligne);
        if ($motif !== null) {
            return $motif;
        }

        $saisie = CarbonImmutable::parse($ligne['updated_at'])->utc();
        $existante = Facture::query()->find($ligne['id']);

        if ($existante === null) {
            return $this->creer($deviceId, $ligne, $saisie);
        }

        return $this->mettreAJourLeStatut($existante, $ligne, $saisie, $deviceId);
    }

    private function valider(array $ligne): ?string
    {
        $v = Validator::make($ligne, [
            'id' => ['required', 'uuid'],
            'reference' => ['required', 'string', 'regex:/^(FV|FA)-(P\d+-|WEB-)?\d{4}-\d{3,}$/'],
            'type' => ['required', 'string', 'in:'.implode(',', self::TYPES)],
            'vente_ref' => ['nullable', 'string', 'regex:/^V-(P\d+-|WEB-)?\d{4}-\d{3,}$/'],
            'origine_ref' => ['nullable', 'string', 'regex:/^FV-(P\d+-|WEB-)?\d{4}-\d{3,}$/'],
            'date_facture' => ['required', 'date'],
            'client' => ['required', 'string', 'max:255'],
            'client_ifu' => ['nullable', 'string', 'max:40'],
            'client_adresse' => ['nullable', 'string', 'max:255'],
            'total_ht' => ['required', 'numeric', 'min:0'],
            'total_taxe' => ['required', 'numeric', 'min:0'],
            'total_ttc' => ['required', 'numeric', 'min:0'],
            'motif' => ['nullable', 'string', 'max:255'],
            'statut' => ['required', 'string', 'in:'.implode(',', self::STATUTS)],
            'code_mecef' => ['nullable', 'string', 'max:255'],
            'nim' => ['nullable', 'string', 'max:60'],
            'compteur' => ['nullable', 'string', 'max:40'],
            'lien_verification' => ['nullable', 'string', 'max:1000'],
            'date_normalisation' => ['nullable', 'date'],
            'erreur_transmission' => ['nullable', 'string', 'max:1000'],
            'updated_at' => ['required', 'date'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.id' => ['required', 'uuid'],
            'lignes.*.designation' => ['required', 'string', 'max:255'],
            'lignes.*.quantite' => ['required', 'numeric', 'gt:0'],
            'lignes.*.unite' => ['nullable', 'string', 'max:40'],
            'lignes.*.prix_unitaire_ht' => ['required', 'numeric', 'min:0'],
            'lignes.*.groupe_taxe' => ['required', 'string', 'regex:/^[A-Z]$/'],
            'lignes.*.taux_taxe' => ['required', 'numeric', 'min:0', 'max:100'],
            'lignes.*.montant_ht' => ['required', 'numeric', 'min:0'],
            'lignes.*.montant_taxe' => ['required', 'numeric', 'min:0'],
        ], [
            'id.required' => "L'identifiant de la facture est obligatoire.",
            'id.uuid' => "L'identifiant de la facture doit être un UUID.",
            'reference.required' => 'La référence de la facture est obligatoire.',
            'reference.regex' => 'La référence de la facture est invalide (attendu : FV-P2-2026-001).',
            'type.in' => 'Le type de la facture est inconnu (FV ou FA).',
            'vente_ref.regex' => 'La référence de la vente est invalide.',
            'origine_ref.regex' => "La référence de la facture d'origine est invalide.",
            'date_facture.required' => 'La date de la facture est obligatoire.',
            'date_facture.date' => 'La date de la facture est invalide.',
            'client.required' => 'Le client de la facture est obligatoire.',
            'total_ht.min' => 'Le total hors taxe ne peut pas être négatif.',
            'total_taxe.min' => 'Le total de la taxe ne peut pas être négatif.',
            'total_ttc.min' => 'Le total toutes taxes comprises ne peut pas être négatif.',
            'statut.in' => 'Le statut de la facture est inconnu.',
            'updated_at.required' => 'La date de saisie de la facture est obligatoire.',
            'lignes.required' => 'Une facture doit avoir au moins une ligne.',
            'lignes.min' => 'Une facture doit avoir au moins une ligne.',
            'lignes.*.quantite.gt' => "La quantité d'une ligne doit être supérieure à 0.",
            'lignes.*.groupe_taxe.regex' => 'Le groupe de taxe est une lettre majuscule (A, B…).',
            'lignes.*.taux_taxe.max' => 'Le taux de taxe ne peut pas dépasser 100 %.',
        ]);
        if ($v->fails()) {
            return $v->errors()->first();
        }

        if (! str_starts_with($ligne['reference'], $ligne['type'].'-')) {
            return 'La référence ne correspond pas au type de la facture.';
        }
        // Un avoir designe la facture qu'il corrige et dit pourquoi ; une facture de vente ne designe rien.
        if ($ligne['type'] === 'FA' && (empty($ligne['origine_ref']) || trim((string) ($ligne['motif'] ?? '')) === '')) {
            return "Un avoir désigne la facture qu'il corrige et en donne le motif.";
        }
        if ($ligne['type'] === 'FV' && ! empty($ligne['origine_ref'])) {
            return "Une facture de vente ne désigne aucune facture d'origine.";
        }

        // Normalisee = un code ET un NIM reels et une date, jamais l'un sans l'autre ; sinon aucun.
        $code = trim((string) ($ligne['code_mecef'] ?? ''));
        $nim = trim((string) ($ligne['nim'] ?? ''));
        if ($ligne['statut'] === 'normalisee') {
            if ($code === '' || $nim === '' || empty($ligne['date_normalisation'])) {
                return 'Une facture normalisée porte un code de normalisation, un NIM et sa date.';
            }
        } elseif ($code !== '' || $nim !== '') {
            return 'Une facture non normalisée ne porte ni code de normalisation ni NIM.';
        }

        // Les totaux sont ceux des lignes : une facture dont l'entete ment est refusee.
        $ht = 0.0;
        $taxe = 0.0;
        foreach ($ligne['lignes'] as $l) {
            $ht += (float) $l['montant_ht'];
            $taxe += (float) $l['montant_taxe'];
        }
        $n = count($ligne['lignes']);
        if (abs(((float) $ligne['total_ht'] + (float) $ligne['total_taxe']) - (float) $ligne['total_ttc']) > self::TOLERANCE
            || abs($ht - (float) $ligne['total_ht']) > self::TOLERANCE * $n
            || abs($taxe - (float) $ligne['total_taxe']) > self::TOLERANCE * $n) {
            return 'Les totaux de la facture ne sont pas ceux de ses lignes.';
        }

        return null;
    }

    private function creer(string $deviceId, array $ligne, CarbonImmutable $saisie): ?string
    {
        $portee = self::porteeReference($ligne['reference'], $deviceId);
        $doublon = Facture::query()
            ->where('portee_reference', $portee)
            ->where('reference', $ligne['reference'])
            ->where('id', '!=', $ligne['id'])
            ->exists();
        if ($doublon) {
            return self::MOTIF_REFERENCE;
        }

        // Un avoir vise une facture de VENTE deja connue (la facture precede son avoir au push).
        if ($ligne['type'] === 'FA') {
            $origine = Facture::query()
                ->where('type', 'FV')
                ->where('reference', $ligne['origine_ref'])
                ->where('portee_reference', self::porteeReference($ligne['origine_ref'], $deviceId))
                ->exists();
            if (! $origine) {
                return "La facture d'origine est inconnue du serveur.";
            }
        }

        // UNE facture de vente par vente (deux postes qui facturent la meme vente = double facturation).
        if ($ligne['type'] === 'FV' && ! empty($ligne['vente_ref'])) {
            $requete = Facture::query()
                ->where('type', 'FV')
                ->where('vente_ref', $ligne['vente_ref'])
                ->where('id', '!=', $ligne['id']);
            if (! self::venteGlobale($ligne['vente_ref'])) {
                // Une vente sans code de poste : la facture du poste OU celle emise au web pour elle.
                $requete->whereIn('device_id', [$deviceId, Catalogue::POSTE_WEB]);
            }
            $autre = $requete->first();
            if ($autre !== null) {
                return "Cette vente porte déjà la facture {$autre->reference}.";
            }
        }

        $facture = (new Facture)->forceFill([
            'id' => $ligne['id'],
            'device_id' => $deviceId,
            'reference' => $ligne['reference'],
            'portee_reference' => $portee,
            'type' => $ligne['type'],
            'vente_ref' => $ligne['vente_ref'] ?? null,
            'origine_ref' => $ligne['origine_ref'] ?? null,
            'date_facture' => CarbonImmutable::parse($ligne['date_facture'])->utc(),
            'client' => trim($ligne['client']),
            'client_ifu' => $ligne['client_ifu'] ?? null,
            'client_adresse' => $ligne['client_adresse'] ?? null,
            'total_ht' => $ligne['total_ht'],
            'total_taxe' => $ligne['total_taxe'],
            'total_ttc' => $ligne['total_ttc'],
            'motif' => $ligne['motif'] ?? null,
            'updated_at' => $saisie,
            'serveur_modifie_le' => CarbonImmutable::now('UTC'),
        ] + $this->champsDgi($ligne));
        $facture->save();

        foreach (array_values($ligne['lignes']) as $rang => $l) {
            (new LigneFacture)->forceFill([
                'ordre' => $rang,
                'id' => $l['id'],
                'facture_id' => $facture->id,
                'designation' => trim($l['designation']),
                'quantite' => $l['quantite'],
                'unite' => $l['unite'] ?? null,
                'prix_unitaire_ht' => $l['prix_unitaire_ht'],
                'groupe_taxe' => $l['groupe_taxe'],
                'taux_taxe' => $l['taux_taxe'],
                'montant_ht' => $l['montant_ht'],
                'montant_taxe' => $l['montant_taxe'],
            ])->save();
        }

        return null;
    }

    /** Statut et ce que la DGI a rendu : les SEULES colonnes qui evoluent. */
    private function champsDgi(array $ligne): array
    {
        return [
            'statut' => $ligne['statut'],
            'code_mecef' => $ligne['code_mecef'] ?? null,
            'nim' => $ligne['nim'] ?? null,
            'compteur' => $ligne['compteur'] ?? null,
            'lien_verification' => $ligne['lien_verification'] ?? null,
            'date_normalisation' => empty($ligne['date_normalisation'])
                ? null
                : CarbonImmutable::parse($ligne['date_normalisation'])->utc(),
            'erreur_transmission' => $ligne['erreur_transmission'] ?? null,
        ];
    }

    /** Le contenu ne change JAMAIS ; le statut ne regresse JAMAIS. */
    private function mettreAJourLeStatut(Facture $existante, array $ligne, CarbonImmutable $saisie, string $deviceId): ?string
    {
        if (! $this->memeContenu($existante, $ligne)) {
            return self::MOTIF_IMMUABLE;
        }

        // Facture emise au web : seul le poste qui a RESERVE sa transmission peut en changer le statut.
        if ($existante->device_id === Catalogue::POSTE_WEB && $deviceId !== Catalogue::POSTE_WEB
            && $existante->transmission_poste !== $deviceId) {
            return self::MOTIF_RESERVATION;
        }

        $rangServeur = self::RANG[$existante->statut];
        $rangRecu = self::RANG[$ligne['statut']];

        if ($rangRecu < $rangServeur) {
            return "La facture est déjà « {$this->libelle($existante->statut)} » sur le serveur : un statut ne régresse jamais.";
        }

        if ($rangRecu === $rangServeur && $ligne['statut'] === 'normalisee') {
            if ($existante->code_mecef !== trim($ligne['code_mecef']) || $existante->nim !== trim($ligne['nim'])) {
                return "Cette facture est déjà normalisée sous un autre code ({$existante->code_mecef}) : une normalisation ne change pas.";
            }

            return null; // rejeu : rien ne change
        }

        $applique = $rangRecu > $rangServeur
            || ($ligne['statut'] === 'rejetee' && $saisie->greaterThan($existante->updated_at));
        if ($applique) {
            $existante->forceFill($this->champsDgi($ligne) + [
                // Un rejet libere la reservation : un autre poste (ou celui-ci) pourra retransmettre.
                'transmission_poste' => $ligne['statut'] === 'rejetee' ? null : $existante->transmission_poste,
                'transmission_reservee_jusqua' => $ligne['statut'] === 'rejetee' ? null : $existante->transmission_reservee_jusqua,
                'updated_at' => $saisie,
                'serveur_modifie_le' => CarbonImmutable::now('UTC'),
            ])->save();
        }

        return null;
    }

    /**
     * Reserve la TRANSMISSION d'une facture emise au web pour ce poste (verrou contre la double normalisation).
     * Atomique : la mise a jour ne reussit que si personne d'autre ne detient une reservation en cours.
     *
     * @return array{0: int, 1: array<string, mixed>} statut HTTP et corps de la reponse
     */
    public function reserverTransmission(User $utilisateur, string $deviceId, string $factureId): array
    {
        if (! $utilisateur->can('manage-facturation')) {
            return [403, ['message' => "Ce compte n'a pas le droit de transmettre des factures.", 'code' => 'droit_insuffisant']];
        }

        $facture = Facture::query()->find($factureId);
        if ($facture === null) {
            return [404, ['message' => 'Facture inconnue du serveur.']];
        }
        if ($facture->device_id !== Catalogue::POSTE_WEB) {
            return [422, ['message' => 'Cette facture a été émise par un poste : seul ce poste la transmet.']];
        }
        if ($facture->statut === 'normalisee') {
            return [409, ['message' => 'Cette facture est déjà normalisée : elle ne se retransmet pas.']];
        }

        $maintenant = CarbonImmutable::now('UTC');
        $format = 'Y-m-d H:i:s.u';
        $jusqua = $maintenant->addMinutes(self::DUREE_RESERVATION_MINUTES);

        $modifiees = DB::transaction(fn () => Facture::query()
            ->whereKey($factureId)
            ->where('statut', '!=', 'normalisee')
            ->where(fn ($q) => $q
                ->whereNull('transmission_poste')
                ->orWhere('transmission_poste', $deviceId)
                ->orWhere('transmission_reservee_jusqua', '<=', $maintenant->format($format)))
            ->update([
                'transmission_poste' => $deviceId,
                'transmission_reservee_jusqua' => $jusqua->format($format),
            ]));

        if ($modifiees === 0) {
            $detenteur = Facture::query()->whereKey($factureId)->value('transmission_poste');
            $code = $detenteur ? Poste::query()->where('device_id', $detenteur)->value('code') : null;

            return [409, ['message' => 'Cette facture est en cours de transmission depuis '.($code ? "le poste $code" : 'un autre poste').' : réessayez dans quelques minutes.']];
        }

        return [200, ['message' => 'Transmission réservée.', 'reservee_jusqua' => $jusqua->format('Y-m-d\TH:i:s.u\Z')]];
    }

    private function libelle(string $statut): string
    {
        return ['a_transmettre' => 'À transmettre', 'rejetee' => 'Rejetée', 'normalisee' => 'Normalisée'][$statut];
    }

    /** Entete et lignes sont ceux de la facture deja enregistree. */
    private function memeContenu(Facture $existante, array $ligne): bool
    {
        if ($existante->reference !== $ligne['reference']
            || $existante->type !== $ligne['type']
            || ($existante->vente_ref ?? null) !== ($ligne['vente_ref'] ?? null)
            || ($existante->origine_ref ?? null) !== ($ligne['origine_ref'] ?? null)
            || $existante->client !== trim($ligne['client'])
            || abs($existante->total_ht - (float) $ligne['total_ht']) > self::TOLERANCE
            || abs($existante->total_taxe - (float) $ligne['total_taxe']) > self::TOLERANCE
            || abs($existante->total_ttc - (float) $ligne['total_ttc']) > self::TOLERANCE) {
            return false;
        }

        $connues = $existante->lignes()->pluck('id')->sort()->values()->all();
        $recues = collect($ligne['lignes'])->pluck('id')->sort()->values()->all();

        return $connues === $recues;
    }
}
