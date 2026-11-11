<?php

namespace App\Livewire;

use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Sync\DemandesReferentiel;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Parametres Generaux (Dart : `parametres_generaux_screen.dart`, Doc F8). REFERENTIEL : le serveur fait foi.
 *
 * Toute ecriture passe par `DemandesReferentiel::traiter` (types `parametres_entreprise` et
 * `module_actif`) : les MEMES regles que pour un poste (validation, droits `manage-parametres` /
 * `manage-modules`, dernier ecrivain gagne, audit, historique, poste « web » = UUID nul).
 *
 * Ce qui n'est PAS ici (ecarts declares a l'ecran et au doc 45 §7) : le jeton e-MECeF et le mot
 * de passe SMTP (secrets du poste, jamais affiches ni saisis), la creation/suppression de comptes,
 * les sauvegardes, la corbeille, les donnees de test, le logo : tout cela se gere sur le poste.
 * Seuls les champs de `DemandesReferentiel::CHAMPS_PARAMETRES` sont lus ou proposes.
 */
#[Layout('components.layouts.app')]
class ParametresGeneraux extends Component
{
    /** Onglets du Dart, dans l'ordre et avec les memes libelles. */
    public const ONGLETS = [
        'Modules Actifs',
        'Données de l\'Entreprise',
        'Gestion Utilisateurs',
        'Modes de Paiement',
        'Appairage',
        'Sauvegardes',
        'Corbeille',
        'Données de Test',
    ];

    /** Modules basculables : id serveur => [libelle, note] (lignes du Dart, `_OngletModulesActifs`). */
    public const MODULES = [
        'pisciculture' => ['Poissons-Chats (Pisciculture)', 'Fiche construite, paramètres non confirmés'],
        'aviculture_classique' => ['Poulets / Pondeuses', 'Filière dupliquée — désactivée par défaut'],
        'cuniculture' => ['Lapins (Cuniculture)', 'Copie fidèle — désactivée par défaut'],
        'heliciculture' => ['Escargots (Héliciculture)', 'Filière ajoutée — désactivée par défaut'],
        'ovins' => ['Ovins', 'Filière ajoutée — désactivée par défaut'],
    ];

    public const SECURITES_SMTP = ['TLS', 'SSL', 'Aucun'];

    public int $onglet = 0;

    public string $raisonSociale = '';

    public string $nomPromoteur = '';

    public string $adresseSiege = '';

    public string $telephone = '';

    public string $email = '';

    public string $delaiPaiement = '';

    public string $ifu = '';

    public string $rccm = '';

    public bool $mecefActif = false;

    public string $mecefUrl = '';

    public string $mecefNim = '';

    public string $smtpServeur = '';

    public string $smtpPort = '';

    public string $smtpSecurite = '';

    public ?string $erreur = null;

    public ?string $message = null;

    private function verifierDroitParametres(): void
    {
        abort_unless(Auth::user()?->can('manage-parametres'), 403);
    }

    private function verifierDroitModules(): void
    {
        abort_unless(Auth::user()?->can('manage-modules'), 403);
    }

    public function mount(): void
    {
        $this->charger();
    }

    private function charger(): void
    {
        $p = ParametresEntreprise::courant();
        $this->raisonSociale = (string) $p->raison_sociale;
        $this->nomPromoteur = (string) $p->nom_promoteur;
        $this->adresseSiege = (string) $p->adresse_siege;
        $this->telephone = (string) $p->telephone;
        $this->email = (string) $p->email;
        $this->delaiPaiement = $p->delai_paiement_jours === null ? '' : (string) $p->delai_paiement_jours;
        $this->ifu = (string) $p->ifu;
        $this->rccm = (string) $p->rccm;
        $this->mecefActif = (bool) $p->mecef_actif;
        $this->mecefUrl = (string) $p->mecef_url;
        $this->mecefNim = (string) $p->mecef_nim;
        $this->smtpServeur = (string) $p->smtp_serveur;
        $this->smtpPort = $p->smtp_port === null ? '' : (string) $p->smtp_port;
        $this->smtpSecurite = (string) $p->smtp_securite;
    }

    public function choisirOnglet(int $index): void
    {
        $this->onglet = array_key_exists($index, self::ONGLETS) ? $index : 0;
        $this->erreur = null;
        $this->message = null;
    }

    /** BR-ADM-004 : MeCeF n'est activable que si l'IFU ET le RCCM sont renseignes. */
    private function mecefActivable(): bool
    {
        return trim($this->ifu) !== '' && trim($this->rccm) !== '';
    }

    public function basculerMecef(): void
    {
        $this->verifierDroitParametres();
        $this->message = null;
        $this->erreur = null;

        if (! $this->mecefActif && ! $this->mecefActivable()) {
            $this->erreur = 'Renseignez l\'IFU et le RCCM avant d\'activer le module MeCeF.';

            return;
        }
        $this->mecefActif = ! $this->mecefActif;
    }

    public function basculerModule(string $moduleId, bool $actif): void
    {
        $this->verifierDroitModules();
        $this->message = null;
        $this->erreur = null;

        if (! array_key_exists($moduleId, self::MODULES)) {
            return;
        }

        $motif = $this->proposer(DemandesReferentiel::TYPE_MODULE, ['module_id' => $moduleId, 'is_actif' => $actif]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $libelle = self::MODULES[$moduleId][0];
        $this->message = $actif
            ? "$libelle activée — sa fiche apparaît dans le menu latéral."
            : "$libelle désactivée. Les données historiques sont conservées.";
    }

    public function enregistrer(): void
    {
        $this->verifierDroitParametres();
        $this->message = null;
        $this->erreur = null;

        // Champs requis de l'onglet (Dart : `enregistrerParametres`), memes messages.
        $ifu = trim($this->ifu);
        $email = trim($this->email);
        $erreur = match (true) {
            trim($this->raisonSociale) === '' => 'La raison sociale est obligatoire.',
            $ifu === '' => 'L\'Identifiant Fiscal Unique (IFU) est obligatoire.',
            ! ctype_digit($ifu) => 'L\'IFU ne doit contenir que des chiffres.',
            $email !== '' && ! preg_match('/^[^@\s]+@[^@\s]+\.[^@\s]+$/', $email) => 'Le format de l\'adresse e-mail est invalide.',
            $this->mecefActif && ! $this->mecefActivable() => 'Renseignez l\'IFU et le RCCM avant d\'activer le module MeCeF.',
            default => null,
        };
        if ($erreur !== null) {
            $this->erreur = $erreur;

            return;
        }

        // Dart : une valeur illisible ou negative vaut « non fixe ».
        $jours = ctype_digit(trim($this->delaiPaiement)) ? (int) trim($this->delaiPaiement) : 0;
        if ($jours > 3650) {
            $this->erreur = 'Le délai de paiement ne peut pas dépasser 3 650 jours.';

            return;
        }
        $port = trim($this->smtpPort);

        $donnees = [
            'raison_sociale' => trim($this->raisonSociale),
            'nom_promoteur' => trim($this->nomPromoteur),
            'adresse_siege' => trim($this->adresseSiege),
            'telephone' => trim($this->telephone),
            'email' => $email,
            'ifu' => $ifu,
            'rccm' => trim($this->rccm),
            'mecef_actif' => $this->mecefActif,
            'mecef_url' => trim($this->mecefUrl),
            'mecef_nim' => trim($this->mecefNim),
            'smtp_serveur' => trim($this->smtpServeur),
            // Un port illisible part tel quel : le serveur refuse avec SON message.
            'smtp_port' => $port === '' ? null : (ctype_digit($port) ? (int) $port : $port),
            'smtp_securite' => in_array($this->smtpSecurite, self::SECURITES_SMTP, true) ? $this->smtpSecurite : null,
            'delai_paiement_jours' => $jours > 0 ? $jours : null,
        ];

        $motif = $this->proposer(DemandesReferentiel::TYPE_PARAMETRES, $donnees);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->charger();
        $this->message = 'Paramètres enregistrés.';
    }

    private function proposer(string $type, array $donnees): ?string
    {
        $bilan = app(DemandesReferentiel::class)->traiter(Auth::user(), Catalogue::POSTE_WEB, [[
            'id' => (string) Str::uuid(),
            'type' => $type,
            'saisi_le' => now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
            'donnees' => $donnees,
        ]]);

        return $bilan['rejected'][0]['motif'] ?? null;
    }

    public function render()
    {
        $utilisateur = Auth::user();
        $modules = ModuleActif::query()->pluck('is_actif', 'module_id');
        $parametres = ParametresEntreprise::courant();

        return view('livewire.parametres-generaux', [
            'onglets' => self::ONGLETS,
            'modulesEtat' => collect(self::MODULES)->map(fn ($ligne, $id) => [
                'id' => $id, 'libelle' => $ligne[0], 'note' => $ligne[1], 'actif' => (bool) ($modules[$id] ?? false),
            ])->values(),
            'peutEcrire' => $utilisateur?->can('manage-parametres') ?? false,
            'peutModules' => $utilisateur?->can('manage-modules') ?? false,
            'peutVoirComptes' => $utilisateur?->can('manage-users') ?? false,
            'modeDonneesTest' => (bool) $parametres->mode_donnees_test,
            'mecefActivable' => $this->mecefActivable(),
            'securites' => self::SECURITES_SMTP,
        ])->title('Paramètres Généraux');
    }
}
