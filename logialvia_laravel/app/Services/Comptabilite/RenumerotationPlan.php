<?php

namespace App\Services\Comptabilite;

use App\Support\PlanSyscohada;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Renumerotation de l'historique du serveur vers le plan SYSCOHADA revise (`47p_` §8). PORT de
 * `MigrationPlanSyscohada` (Dart) : memes regles (`PlanSyscohada::CORRESPONDANCE`), memes garanties.
 *
 * - **UNE transaction** : tout ou rien. Le marqueur d'idempotence est `plan_comptable.plan_version`
 *   (1 = ancien plan, 2 = SYSCOHADA) : la colonne est ajoutee AVANT, les lignes passent a 2 DANS la
 *   transaction, apres la renumerotation.
 * - **Croisement 601↔602 et 613→622** : les lignes passent d'abord par des numeros TEMPORAIRES (`~M<n>`).
 * - **Jamais de perte** : nombre de lignes, debit total, credit total et solde de chaque compte sont verifies
 *   (a la table de correspondance pres, recalculee par `PlanSyscohada::nouveauNumero`, independante du SQL) ;
 *   sinon l'exception annule tout.
 * - Les identifiants (UUID) des lignes et des pieces ne changent pas.
 *
 * Les frais de livraison sont reconnus par leur ligne : 707 SANS centre analytique, dans une piece de vente.
 */
final class RenumerotationPlan
{
    /**
     * @param  list<array{ancien: string, nouveau: string, libelle_ancien: string, frais_livraison_seulement: bool}>|null  $regles
     * @return array{lignes_renumerotees: int, debit: float, credit: float, comptes_ajoutes: int}|null `null` si deja migre
     */
    public static function executer(?array $regles = null): ?array
    {
        $regles ??= PlanSyscohada::CORRESPONDANCE;

        // Deja migre : plus aucun compte a l'ancienne version (un plan vide est « neuf »).
        $anciens = DB::table('plan_comptable')->where('plan_version', '<', PlanSyscohada::VERSION)->count();
        if ($anciens === 0) {
            return null;
        }

        return DB::transaction(fn () => self::renumeroter($regles));
    }

    /** @return array{lignes_renumerotees: int, debit: float, credit: float, comptes_ajoutes: int} */
    private static function renumeroter(array $regles): array
    {
        // ---- Etat AVANT : attendu, calcule par la fonction pure, ligne par ligne.
        $avant = DB::table('ecritures_comptables as e')
            ->join('pieces_comptables as p', 'p.id', '=', 'e.piece_id')
            ->select('e.numero_compte', 'e.debit', 'e.credit', 'e.axe_analytique', 'p.vente_ref')
            ->get();
        $attendu = [];
        $debitAvant = 0.0;
        $creditAvant = 0.0;
        $renumerotees = 0;
        foreach ($avant as $l) {
            $nouveau = PlanSyscohada::nouveauNumero($l->numero_compte, $l->axe_analytique, $l->vente_ref, $regles);
            if ($nouveau !== $l->numero_compte) {
                $renumerotees++;
            }
            $attendu[$nouveau]['debit'] = ($attendu[$nouveau]['debit'] ?? 0.0) + (float) $l->debit;
            $attendu[$nouveau]['credit'] = ($attendu[$nouveau]['credit'] ?? 0.0) + (float) $l->credit;
            $debitAvant += (float) $l->debit;
            $creditAvant += (float) $l->credit;
        }
        $nombreAvant = $avant->count();

        $planAvant = DB::table('plan_comptable')->get()->keyBy('numero_compte');
        $officiel = [];
        foreach (PlanSyscohada::COMPTES as [$numero, $libelle, $classe]) {
            $officiel[$numero] = [$libelle, $classe];
        }
        $maintenant = CarbonImmutable::now('UTC')->format('Y-m-d H:i:s.u');

        // ---- Les comptes a renumeroter : ceux du plan ET ceux des ecritures ; un triplet (ancien, nouveau,
        // frais de livraison seulement) par compte dont le numero change (la regle des frais de livraison avant la
        // regle generale du meme compte).
        $anciens = $planAvant->keys()->merge($avant->pluck('numero_compte'))->map(fn ($n) => (string) $n)->unique()->sort(SORT_STRING)->values()->all();
        $triplets = [];
        foreach ($anciens as $ancien) {
            foreach ($regles as $r) {
                if ($r['frais_livraison_seulement'] && $r['ancien'] === $ancien) {
                    $triplets[] = ['ancien' => $ancien, 'nouveau' => $r['nouveau'], 'livraison' => true];
                }
            }
            $general = PlanSyscohada::nouveauNumero($ancien, null, null, $regles);
            if ($general !== $ancien) {
                $triplets[] = ['ancien' => $ancien, 'nouveau' => $general, 'livraison' => false];
            }
        }
        $sources = array_column($triplets, 'ancien');
        $cibles = array_column($triplets, 'nouveau');

        // ---- Phase A : lignes vers des numeros temporaires.
        foreach ($triplets as $i => $t) {
            DB::table('plan_comptable')->insertOrIgnore([
                'numero_compte' => '~M'.$i, 'libelle' => 'temporaire', 'classe' => substr($t['nouveau'], 0, 1),
                'archive' => false, 'plan_version' => 1, 'created_at' => $maintenant, 'updated_at' => $maintenant,
            ]);
            $requete = DB::table('ecritures_comptables')->where('numero_compte', $t['ancien']);
            if ($t['livraison']) {
                $requete->whereNull('axe_analytique')
                    ->whereIn('piece_id', DB::table('pieces_comptables')->whereNotNull('vente_ref')->select('id'));
            }
            $requete->update(['numero_compte' => '~M'.$i]);
        }

        // ---- Phase B : numeros definitifs. Le plan recoit la cible : libelle PERSONNALISE de l'ancien compte
        // reporte (y compris sur un sous-compte), sinon libelle officiel.
        $ajoutes = 0;
        $traitees = [];
        foreach ($triplets as $i => $t) {
            $existe = DB::table('plan_comptable')->where('numero_compte', $t['nouveau'])->exists();
            $rang = $planAvant->get($t['ancien']);
            $defaut = PlanSyscohada::LIBELLES_ANCIENS[$t['ancien']] ?? null;
            $personnalise = ! $t['livraison'] && $rang !== null && ($defaut === null || $rang->libelle !== $defaut);
            $libelle = $personnalise ? $rang->libelle : ($officiel[$t['nouveau']][0] ?? $rang->libelle ?? $t['nouveau']);
            $archive = ! $t['livraison'] && ($rang?->archive ?? false);
            if (! $existe) {
                DB::table('plan_comptable')->insert([
                    'numero_compte' => $t['nouveau'], 'libelle' => $libelle, 'classe' => substr($t['nouveau'], 0, 1),
                    'archive' => (bool) $archive, 'plan_version' => 1, 'created_at' => $maintenant, 'updated_at' => $maintenant,
                ]);
                $ajoutes++;
            } elseif (! isset($traitees[$t['nouveau']]) && in_array($t['nouveau'], $sources, true) && ! $t['livraison']) {
                // La cible etait un ancien compte (601↔602, 613→622) : elle change de sens, donc de libelle.
                DB::table('plan_comptable')->where('numero_compte', $t['nouveau'])
                    ->update(['libelle' => $libelle, 'archive' => (bool) $archive, 'updated_at' => $maintenant]);
            }
            $traitees[$t['nouveau']] = true;
            DB::table('ecritures_comptables')->where('numero_compte', '~M'.$i)->update(['numero_compte' => $t['nouveau']]);
            DB::table('plan_comptable')->where('numero_compte', '~M'.$i)->delete();
        }

        // ---- Anciens comptes devenus sans objet : retires du plan s'ils ne sont la cible d'aucune regle.
        foreach (array_unique($sources) as $ancien) {
            if (in_array($ancien, $cibles, true)) {
                continue;
            }
            if (! DB::table('ecritures_comptables')->where('numero_compte', $ancien)->exists()) {
                DB::table('plan_comptable')->where('numero_compte', $ancien)->delete();
            }
        }

        // ---- Libelles par defaut de l'ancien plan → officiels ; comptes officiels absents → ajoutes.
        foreach (PlanSyscohada::COMPTES as [$numero, $libelle, $classe]) {
            $ligne = DB::table('plan_comptable')->where('numero_compte', $numero)->first();
            if ($ligne === null) {
                DB::table('plan_comptable')->insert([
                    'numero_compte' => $numero, 'libelle' => $libelle, 'classe' => $classe, 'archive' => false,
                    'plan_version' => 1, 'created_at' => $maintenant, 'updated_at' => $maintenant,
                ]);
                $ajoutes++;
            } elseif (($ligne->libelle === (PlanSyscohada::LIBELLES_ANCIENS[$numero] ?? null))
                && ! in_array($numero, $sources, true) && ! in_array($numero, $cibles, true)) {
                DB::table('plan_comptable')->where('numero_compte', $numero)->update(['libelle' => $libelle, 'updated_at' => $maintenant]);
            }
        }

        // ---- Verification APRES : rien perdu, equilibre et soldes identiques a la renumerotation pres.
        $apres = DB::table('ecritures_comptables')
            ->selectRaw('numero_compte, SUM(debit) as d, SUM(credit) as k')->groupBy('numero_compte')->get()->keyBy('numero_compte');
        $nombreApres = DB::table('ecritures_comptables')->count();
        $debitApres = (float) $apres->sum('d');
        $creditApres = (float) $apres->sum('k');
        $exiger = function (bool $ok, string $message): void {
            if (! $ok) {
                throw new RuntimeException("Migration du plan comptable annulée : $message");
            }
        };
        $exiger($nombreApres === $nombreAvant, 'nombre de lignes modifié.');
        $exiger(abs($debitApres - $debitAvant) < 0.005 && abs($creditApres - $creditAvant) < 0.005, 'totaux débit/crédit modifiés.');
        foreach ($attendu as $compte => $s) {
            $reel = $apres->get($compte);
            $exiger($reel !== null && abs((float) $reel->d - $s['debit']) < 0.005 && abs((float) $reel->k - $s['credit']) < 0.005,
                "solde du compte $compte différent de l'attendu (attendu D {$s['debit']} / C {$s['credit']}, obtenu D ".($reel->d ?? 'aucun').' / C '.($reel->k ?? 'aucun').').');
        }
        $exiger($apres->count() === count($attendu), 'comptes mouvementés différents.');
        $orphelines = DB::table('ecritures_comptables as e')
            ->leftJoin('plan_comptable as p', 'p.numero_compte', '=', 'e.numero_compte')->whereNull('p.numero_compte')->count();
        $exiger($orphelines === 0, 'écriture sans compte au plan.');

        // ---- Marqueur : tout le plan passe a la version courante (DANS la transaction).
        DB::table('plan_comptable')->update(['plan_version' => PlanSyscohada::VERSION]);

        return ['lignes_renumerotees' => $renumerotees, 'debit' => $debitApres, 'credit' => $creditApres, 'comptes_ajoutes' => $ajoutes];
    }
}
