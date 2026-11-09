<?php

namespace App\Livewire;

use App\Livewire\Concerns\LitLeLivre;
use App\Services\Comptabilite\LigneEcriture;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use Carbon\CarbonImmutable;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Grand Livre (Dart : `GrandLivreScreen`, `grand_livre_screen.dart`).
 *
 * Les ecritures d'UN compte, avec solde progressif dans le sens NATUREL du compte (BR-CPT-007),
 * calculees par le serveur sur TOUTES les ecritures recues de tous les postes. Le solde
 * d'ouverture = reports des exercices anterieurs + ecritures de l'exercice anterieures a la
 * date de debut : sans ce second terme, restreindre la periode afficherait un solde faux.
 *
 * LECTURE seule. Ecart avec le Dart : pas d'export PDF.
 */
#[Layout('components.layouts.app')]
class GrandLivre extends Component
{
    use LitLeLivre;

    public string $compte = '';

    public string $debut = '';

    public string $fin = '';

    public string $recherche = '';

    public function retirerBorne(string $quelle): void
    {
        if ($quelle === 'debut') {
            $this->debut = '';
        } elseif ($quelle === 'fin') {
            $this->fin = '';
        }
    }

    /** Une borne saisie (Y-m-d) ; `null` si vide ou invalide. */
    private function jour(string $valeur): ?CarbonImmutable
    {
        if ($valeur === '') {
            return null;
        }
        try {
            $d = CarbonImmutable::createFromFormat('!Y-m-d', $valeur, config('logialvia.fuseau'));
        } catch (\Throwable) {
            return null;
        }

        return $d !== false && $d->format('Y-m-d') === $valeur ? $d : null;
    }

    public function render()
    {
        $annee = $this->annee();
        [$ecritures, $anterieures] = $this->ecritures($annee);
        $plan = LivreComptable::plan();
        $compte = $this->compte !== '' ? $plan->get($this->compte) : null;

        $donnees = ['compte_choisi' => $compte, 'lignes' => [], 'ouverture' => 0.0, 'debit' => 0.0, 'credit' => 0.0, 'solde_final' => 0.0];

        if ($compte !== null) {
            $debut = $this->jour($this->debut);
            $fin = $this->jour($this->fin);
            $avant = fn (LigneEcriture $e) => $debut !== null && $e->date->lessThan($debut);
            $dans = function (LigneEcriture $e) use ($debut, $fin, $avant) {
                if ($avant($e)) {
                    return false;
                }

                // Borne incluse : une ecriture du 08/08 entre dans « au 08/08 ».
                return $fin === null || $e->date->lessThanOrEqualTo($fin->setTime(23, 59, 59));
            };

            $duCompte = fn (LigneEcriture $e) => $e->compte === $compte->numero_compte;
            $net = $anterieures->filter($duCompte)->sum(fn ($e) => $e->debit - $e->credit)
                + $ecritures->filter(fn ($e) => $duCompte($e) && $avant($e))->sum(fn ($e) => $e->debit - $e->credit);
            $ouverture = $compte->estDebiteurParNature() ? $net : -$net;

            $periode = $ecritures->filter(fn ($e) => $duCompte($e) && $dans($e))->values();
            $toutes = MoteurComptable::grandLivre($compte, $ouverture, $periode);

            $terme = mb_strtolower(trim($this->recherche));
            $lignes = $terme === '' ? $toutes : array_values(array_filter($toutes, function (array $l) use ($terme) {
                $e = $l['ecriture'];

                return str_contains(mb_strtolower($e->libelle), $terme)
                    || str_contains(mb_strtolower((string) $e->numeroPiece), $terme)
                    || str_contains(mb_strtolower((string) $e->venteRef), $terme)
                    || str_contains(mb_strtolower((string) $e->achatRef), $terme);
            }));

            // Les KPI et le solde progressif se calculent sur TOUTE la periode, recherche non appliquee.
            $donnees = [
                'compte_choisi' => $compte,
                'lignes' => $lignes,
                'ouverture' => $ouverture,
                'debit' => $periode->sum('debit'),
                'credit' => $periode->sum('credit'),
                'solde_final' => $toutes === [] ? $ouverture : end($toutes)['solde'],
            ];
        }

        return view('livewire.comptabilite.grand-livre', $this->communes($annee) + $donnees + [
            'titre' => 'Grand Livre',
            'description' => 'Liste chronologique des écritures d\'un compte, avec solde progressif.',
            'comptesActifs' => $plan->where('archive', false),
        ])->title('Grand Livre');
    }
}
