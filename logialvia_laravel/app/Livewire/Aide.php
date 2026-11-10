<?php

namespace App\Livewire;

use App\Support\Droits;
use App\Support\Navigation;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Aide & A Propos (Dart : `aide_a_propos_screen.dart`, Doc F9). Page statique : la seule donnee
 * propre a l'ecran est la recherche dans la FAQ. Les textes sont ceux du poste, mot pour mot.
 *
 * Une vignette n'est proposee que si le compte peut ouvrir sa route ET que son module est actif :
 * jamais de lien qui mene a un 403 ou a un 404.
 */
#[Layout('components.layouts.app')]
class Aide extends Component
{
    public const VERSION = 'v1.0.0';

    public const DESCRIPTION = 'LogiALVIA — Application de Gestion et de Suivi Avicole d\'ALLMANY';

    public const MENTION_PROJET = 'Développé dans le cadre du PAEB par FAGUEZ SARL — Dr Rhodes MASSENON (ingénierie logicielle)';

    /** Les 8 vignettes du poste, dans l'ordre : [libelle, route]. */
    public const MODULES = [
        ['Élevage & Couveuse', '/elevage/dashboard'],
        ['Ventes & Clients', '/ventes'],
        ['Achats & Fournisseurs', '/achats'],
        ['Stocks & Catalogue', '/stocks'],
        ['Santé Animale', '/elevage/soins'],
        ['Clients & Relances', '/clients'],
        ['Comptabilité', '/comptabilite'],
        ['Rapports & États', '/rapports'],
    ];

    /** Les 5 questions du poste (`CompteViewModel.faq`) : [question, reponse, mots-cles]. */
    public const FAQ = [
        [
            'Comment enregistrer une nouvelle vente ?',
            'Rendez-vous dans Ventes & Clients > Point de Vente, ajoutez les produits au panier, choisissez un client (ou Client Comptant), puis validez le mode de règlement.',
            'comment enregistrer une nouvelle vente ?',
        ],
        [
            'Comment activer ou désactiver une filière (ex. Lapins) ?',
            'Rendez-vous dans Paramètres Généraux > Modules Actifs. L\'effet est immédiat sur le menu latéral et le Dashboard Élevage.',
            'comment activer ou desactiver un module ?',
        ],
        [
            'Comment fonctionne l\'alerte de stock critique ?',
            'Chaque produit a un seuil d\'alerte (réglable dans Catalogue Produits > Seuils d\'Alerte). Un badge rouge s\'affiche automatiquement dès que le stock repasse sous ce seuil.',
            'comment fonctionne l\'alerte de stock ?',
        ],
        [
            'Comment administrer une dose et décrémenter le stock ?',
            'Dans Soins & Calendrier > Administrer une Dose, sélectionnez le lot et le produit — le stock vétérinaire est décrémenté automatiquement, ou l\'action est bloquée si le stock est épuisé.',
            'comment administrer une dose de vaccin ?',
        ],
        [
            'Comment relancer un client avec un solde impayé ?',
            'Depuis Clients et Relances > Suivi des Soldes, utilisez le bouton de relance sur la ligne du client concerné.',
            'comment relancer un client avec un solde impaye ?',
        ],
    ];

    public string $recherche = '';

    public function render()
    {
        $utilisateur = Auth::user();
        $terme = mb_strtolower(trim($this->recherche));

        $vignettes = collect(self::MODULES)
            ->filter(fn (array $m) => $utilisateur !== null
                && Navigation::droitPour($utilisateur, $m[1]) && Navigation::moduleDeRouteActif($m[1]))
            ->map(fn (array $m) => ['libelle' => $m[0], 'route' => $m[1]])
            ->values();

        // Comme le poste : le terme est cherche dans les mots-cles ET dans le texte visible.
        $questions = collect(self::FAQ)
            ->filter(fn (array $q) => $terme === ''
                || str_contains($q[2], $terme)
                || str_contains(mb_strtolower($q[0]), $terme)
                || str_contains(mb_strtolower($q[1]), $terme))
            ->map(fn (array $q) => ['question' => $q[0], 'reponse' => $q[1]])
            ->values();

        return view('livewire.aide', [
            'vignettes' => $vignettes,
            'questions' => $questions,
            'version' => self::VERSION,
            'description' => self::DESCRIPTION,
            'mention' => self::MENTION_PROJET,
        ])->title('Aide & À Propos');
    }
}
