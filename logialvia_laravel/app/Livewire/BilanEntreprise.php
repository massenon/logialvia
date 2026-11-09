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

    public function render()
    {
        $annee = $this->annee();
        [$ecritures] = $this->ecritures($annee);
        $b = MoteurComptable::bilanEntreprise($this->soldes($ecritures));

        return view('livewire.comptabilite.bilan-entreprise', $this->communes($annee) + [
            'titre' => 'Bilan de l\'Entreprise',
            'description' => "Exercice $annee — au ".now(config('logialvia.fuseau'))->format('d/m/Y').'. Ce que possède l\'entreprise à gauche, d\'où provient cet argent à droite.',
            'bilan' => $b,
            // L'ecart n'est pas ajoute au total : il montre ce qui manque au passif.
            'ecartNonEnregistre' => $b['equilibre'] || $b['vide'] ? null : $b['ecart'],
        ])->title('Bilan de l\'Entreprise');
    }
}
