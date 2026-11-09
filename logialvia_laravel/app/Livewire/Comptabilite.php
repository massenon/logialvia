<?php

namespace App\Livewire;

use App\Livewire\Concerns\LitLeLivre;
use App\Models\ParametresEntreprise;
use App\Services\Comptabilite\MoteurComptable;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Hub Comptabilite (Dart : `ComptabiliteHubScreen`, `comptabilite_hub_screen.dart`).
 *
 * LECTURE seule. Les 4 KPI sont calcules par le serveur depuis les ecritures recues de TOUS
 * les postes ; le Resultat Cumule est le meme nombre, au franc pres, que celui du Bilan et du
 * Compte de Resultat (BR-CPT-005).
 *
 * Ecarts avec le Dart : pas d'export PDF (aucun ecran web de la tranche n'en a) ; le bandeau
 * MeCeF lit les parametres du serveur.
 */
#[Layout('components.layouts.app')]
class Comptabilite extends Component
{
    use LitLeLivre;

    /** Les tuiles de `comptabilite-hub.html`, dans l'ordre du Dart. */
    public const TUILES = [
        ['Plan Comptable', 'Structure SYSCOHADA', '/comptabilite/plan'],
        ['Journal Comptable', 'Écritures chronologiques', '/comptabilite/journal'],
        ['Grand Livre', 'Écritures par compte, solde progressif', '/comptabilite/grand-livre'],
        ['Balance Générale', 'Soldes de tous les comptes', '/comptabilite/balance'],
        ['États Financiers', 'Bilan, Résultat, Flux, Notes Annexes', '/comptabilite/etats-financiers'],
        ['Bilan de l\'Entreprise', 'Ce que je possède, ce que je dois', '/comptabilite/bilan'],
        ['Clôture d\'Exercice', 'Périodique et annuelle, report à nouveau', '/comptabilite/cloture'],
        ['Comptabilité Analytique', 'Marges réelles par filière', '/comptabilite/analytique'],
        ['Modules Actifs & IFU/RCCM', 'Configurer la conformité MeCeF', '/parametres/generaux'],
    ];

    public function render()
    {
        $annee = $this->annee();
        [$ecritures] = $this->ecritures($annee);
        $soldes = $this->soldes($ecritures);

        $produits = MoteurComptable::produits($soldes);
        $resultat = MoteurComptable::resultatNet($soldes);
        $parametres = ParametresEntreprise::courant();

        return view('livewire.comptabilite.hub', $this->communes($annee) + [
            'titre' => 'Comptabilité',
            'description' => 'Comptabilité complète SYSCOHADA — Plan Comptable, Journal, Grand Livre, Balance, États Financiers et Clôture d\'Exercice.',
            'totalActif' => MoteurComptable::bilan($soldes)['total_actif'],
            'tresorerie' => $soldes->debiteursParClasse('5'),
            'resultat' => $resultat,
            // Marge Nette = Resultat Net / Produits ; indefinie sans produit.
            'margeNette' => abs($produits) < 0.01 ? null : $resultat / $produits * 100,
            'ifu' => trim((string) $parametres->ifu),
            'rccm' => trim((string) $parametres->rccm),
            'tuiles' => self::TUILES,
        ])->title('Comptabilité');
    }
}
