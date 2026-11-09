<?php

namespace App\Livewire;

use App\Models\AuditLog;
use App\Models\User;
use App\Support\LibellesAudit;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Journal d'audit du serveur (`audit_logs`), en LECTURE SEULE : filtres par date, action et
 * utilisateur, pagination. Droit `manage-users` (le journal porte les identifiants, les adresses
 * IP et les gestes de tous les comptes). Le Dart n'a pas d'ecran equivalent : le poste ne montre
 * que le journal PERSONNEL (Mon Profil) ; c'est l'ajout web voulu par le client (doc 47u §2).
 *
 * Les dates se lisent au fuseau metier (Natitingou, Benin) ; la base garde l'UTC.
 */
#[Layout('components.layouts.app')]
class JournalAudit extends Component
{
    public const PAR_PAGE = 25;

    public string $dateDebut = '';

    public string $dateFin = '';

    public string $action = '';

    public string $utilisateur = '';

    public int $page = 1;

    public ?string $erreur = null;

    private function verifierDroit(): void
    {
        abort_unless(Auth::user()?->can('manage-users'), 403);
    }

    public function mount(): void
    {
        $this->verifierDroit();
    }

    public function updated(string $propriete): void
    {
        if (in_array($propriete, ['dateDebut', 'dateFin', 'action', 'utilisateur'], true)) {
            $this->page = 1;
        }
    }

    public function reinitialiser(): void
    {
        $this->verifierDroit();
        $this->dateDebut = $this->dateFin = $this->action = $this->utilisateur = '';
        $this->page = 1;
    }

    public function precedente(): void
    {
        $this->verifierDroit();
        $this->page = max(1, $this->page - 1);
    }

    public function suivante(): void
    {
        $this->verifierDroit();
        $this->page++;
    }

    private function jour(string $valeur): ?CarbonImmutable
    {
        $valeur = trim($valeur);
        if ($valeur === '' || ! preg_match('/^\d{4}-\d{2}-\d{2}$/', $valeur)) {
            return null;
        }
        try {
            $jour = CarbonImmutable::createFromFormat('!Y-m-d', $valeur, config('logialvia.fuseau'));
        } catch (\Throwable) {
            return null;
        }

        return $jour !== false && $jour->format('Y-m-d') === $valeur ? $jour : null;
    }

    private function requete(): Builder
    {
        $this->erreur = null;
        $requete = AuditLog::query();

        $debut = $this->jour($this->dateDebut);
        $fin = $this->jour($this->dateFin);
        if (trim($this->dateDebut) !== '' && $debut === null) {
            $this->erreur = 'La date de début est invalide.';
        } elseif (trim($this->dateFin) !== '' && $fin === null) {
            $this->erreur = 'La date de fin est invalide.';
        } elseif ($debut !== null && $fin !== null && $debut->greaterThan($fin)) {
            $this->erreur = 'La date de début ne peut pas dépasser la date de fin.';
        }

        if ($this->erreur === null) {
            if ($debut !== null) {
                $requete->where('created_at', '>=', $debut->utc()->format('Y-m-d H:i:s'));
            }
            if ($fin !== null) {
                // Fin INCLUSE : jusqu'a la fin du jour choisi.
                $requete->where('created_at', '<', $fin->addDay()->utc()->format('Y-m-d H:i:s'));
            }
        }
        if ($this->action !== '') {
            $requete->where('action', $this->action);
        }
        if ($this->utilisateur !== '') {
            $requete->where('utilisateur_id', $this->utilisateur);
        }

        return $requete;
    }

    /** Export XLSX : memes filtres que l'ecran, TOUTES les pages (5 000 lignes au plus), secrets masques. */
    public function exporter(): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        $this->verifierDroit();
        $fuseau = config('logialvia.fuseau');
        $lignes = [['Date', 'Utilisateur', 'Identifiant', 'Action', 'Code action', 'Détail', 'Adresse IP']];
        $requete = $this->requete();
        $auteurs = User::withTrashed()->pluck('name', 'id');
        if ($this->erreur === null) {
            foreach ($requete->orderByDesc('created_at')->orderByDesc('id')->limit(5000)->get() as $l) {
                $lignes[] = [
                    $l->created_at->timezone($fuseau)->format('d/m/Y H:i:s'), $auteurs[$l->utilisateur_id] ?? '', (string) $l->identifiant,
                    LibellesAudit::action($l->action), $l->action, implode(' ; ', LibellesAudit::detail($l->detail)), (string) $l->ip,
                ];
            }
        }

        return \App\Support\ExportXlsx::telecharger($lignes, 'journal-audit.xlsx', 'Journal d\'audit');
    }

    public function render()
    {
        $this->verifierDroit();

        $requete = $this->requete();
        $total = (clone $requete)->count();
        $pages = max(1, (int) ceil($total / self::PAR_PAGE));
        $this->page = min(max(1, $this->page), $pages);

        $lignes = $requete->orderByDesc('created_at')->orderByDesc('id')
            ->forPage($this->page, self::PAR_PAGE)->get();

        return view('livewire.journal-audit', [
            'lignes' => $lignes,
            'total' => $total,
            'pages' => $pages,
            'actions' => AuditLog::query()->select('action')->distinct()->orderBy('action')->pluck('action')
                ->mapWithKeys(fn ($a) => [$a => LibellesAudit::action($a)])->all(),
            'comptes' => User::withTrashed()->orderBy('name')->get(['id', 'name', 'username']),
            'auteurs' => User::withTrashed()->whereIn('id', $lignes->pluck('utilisateur_id')->filter()->unique())->pluck('name', 'id'),
            'fuseau' => config('logialvia.fuseau'),
        ])->title('Journal d\'Audit');
    }
}
