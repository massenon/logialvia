<?php

namespace App\Livewire;

use App\Livewire\Concerns\LitLeLivre;
use App\Services\Comptabilite\MoteurComptable;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Bilan de l'Entreprise (Dart : `BilanEntrepriseScreen`, `bilan_entreprise_screen.dart`) : la
 * version LISIBLE du bilan — « qu'est-ce que je possede, qu'est-ce que je dois ? » — en sept
 * lignes, une par poste reel.
 *
 * Le Capital Initial est LU au compte 101, jamais deduit : si aucun apport n'a ete saisi, l'actif
 * depasse le passif et l'ecart est affiche en clair sur sa propre ligne — le bandeau peut passer
 * au rouge. Meme source d'ecritures que les Etats Financiers : meme Resultat Net (BR-CPT-005).
 *
 * LECTURE seule. Ecart avec le Dart : pas d'export PDF.
 */
#[Layout('components.layouts.app')]
class BilanEntreprise extends Component
{
    use LitLeLivre;

    /** Donnees de l'ecran : la vue ET l'export XLSX lisent la meme source. */
    private function donnees(): array
    {
        $annee = $this->annee();
        $b = MoteurComptable::bilanEntreprise($this->soldesFin($annee));

        return $this->communes($annee) + [
            'titre' => 'Bilan de l\'Entreprise',
            'description' => "Exercice $annee — au ".now(config('logialvia.fuseau'))->format('d/m/Y').'. Ce que possède l\'entreprise à gauche, d\'où provient cet argent à droite.',
            'bilan' => $b,
            // L'ecart n'est pas ajoute au total : il montre ce qui manque au passif.
            'ecartNonEnregistre' => $b['equilibre'] || $b['vide'] ? null : $b['ecart'],
        ];
    }

    public function render()
    {
        return view('livewire.comptabilite.bilan-entreprise', $this->donnees())->title('Bilan de l\'Entreprise');
    }

    /** Export XLSX du bilan : `view-comptabilite`, verifie ici. */
    public function exporter(): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        abort_unless(\Illuminate\Support\Facades\Auth::user()?->can('view-comptabilite'), 403);
        $d = $this->donnees();
        $b = $d['bilan'];
        $lignes = [['Bilan de l\'Entreprise — exercice '.$d['annee']], ['ACTIF', 'Compte', 'Montant']];
        foreach ($b['actif'] as $p) {
            $lignes[] = [$p['libelle'], $p['compte'], (int) round($p['montant'])];
        }
        $lignes[] = ['TOTAL ACTIF', '', (int) round($b['total_actif'])];
        $lignes[] = ['PASSIF', 'Compte', 'Montant'];
        foreach ($b['passif'] as $p) {
            $lignes[] = [$p['libelle'], $p['compte'], (int) round($p['montant'])];
        }
        $lignes[] = ['TOTAL PASSIF', '', (int) round($b['total_passif'])];

        return \App\Support\ExportXlsx::telecharger($lignes, 'bilan-entreprise-'.$d['annee'].'.xlsx', 'Bilan de l\'Entreprise');
    }
}
