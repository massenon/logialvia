<?php

namespace App\Livewire;

use App\Models\Poste;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;

/**
 * Icône de synchronisation de la barre du haut (Dart : `IndicateurSynchro` de `app_top_bar.dart`) et son modal.
 *
 * Le web EST le serveur : il ne synchronise pas, il reçoit. L'icône dit donc où en sont les POSTES — état réel, jamais un
 * compteur décoratif : appairés, joints récemment, silencieux, révoqués. Réservée à qui gère les postes
 * (droit `manage-users`, comme l'écran « Postes & Appairage »).
 */
class IndicateurSynchro extends Component
{
    /** Un poste interroge le serveur toutes les 30 s (demande) : au-delà de 2 min sans contact, il n'est plus « en ligne ». */
    public const EN_LIGNE_SECONDES = 120;

    /** Au-delà de 15 min (3 routines de 5 min manquées), le silence mérite d'être signalé. */
    public const SILENCE_SECONDES = 900;

    /** @return list<array{code: string, etat: string, libelle: string, contact: ?string, utilisateur: ?string}> */
    private function postes(): array
    {
        $maintenant = CarbonImmutable::now();

        return Poste::query()->with('dernierUtilisateur')->orderBy('code')->get()->map(function (Poste $p) use ($maintenant) {
            $contact = $p->dernier_contact_le;
            $secondes = $contact === null ? null : (int) abs($maintenant->diffInSeconds($contact));

            $etat = match (true) {
                $p->revoque_le !== null => 'revoque',
                $contact === null => 'jamais',
                $secondes <= self::EN_LIGNE_SECONDES => 'en_ligne',
                $secondes <= self::SILENCE_SECONDES => 'recent',
                default => 'silencieux',
            };

            return [
                'code' => $p->code,
                'etat' => $etat,
                'libelle' => [
                    'revoque' => 'Révoqué',
                    'jamais' => 'Appairé, jamais joint',
                    'en_ligne' => 'En ligne',
                    'recent' => 'Joint récemment',
                    'silencieux' => 'Sans contact',
                ][$etat],
                'contact' => $contact?->setTimezone(config('logialvia.fuseau'))->diffForHumans(),
                'utilisateur' => $p->dernierUtilisateur?->name,
            ];
        })->all();
    }

    public function render()
    {
        abort_unless(Auth::user()?->can('manage-users'), 403);

        $postes = $this->postes();
        $actifs = array_values(array_filter($postes, fn ($p) => $p['etat'] !== 'revoque'));
        $enLigne = count(array_filter($actifs, fn ($p) => $p['etat'] === 'en_ligne'));
        $problemes = count(array_filter($actifs, fn ($p) => in_array($p['etat'], ['silencieux', 'jamais'], true)));

        [$icone, $couleur, $texte] = match (true) {
            count($actifs) === 0 => ['link_off', 'text-outline', 'Aucun poste appairé'],
            $problemes > 0 => ['sync_problem', 'text-error-deep', $problemes.' poste'.($problemes > 1 ? 's' : '').' sans contact'],
            default => ['cloud_done', 'text-success-deep', $enLigne.' poste'.($enLigne > 1 ? 's' : '').' en ligne'],
        };

        return view('livewire.indicateur-synchro', compact('postes', 'icone', 'couleur', 'texte', 'enLigne', 'actifs'));
    }
}
