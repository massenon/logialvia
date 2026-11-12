<?php

namespace App\Livewire;

use App\Mail\MessageEditeurMail;
use App\Models\MessageEditeur;
use App\Models\User;
use App\Support\Audit;
use App\Sync\Tables\MessagesEditeurTable;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Contactez l'Editeur (Dart : `contact_editeur_screen.dart`, Doc F9 ; doc 47u §4). Coordonnees de
 * l'editeur + formulaire (Question / Probleme technique) + registre des messages enregistres.
 *
 * Les messages sont des FAITS synchronises (`messages_editeur`, poste v45) : un message ecrit au web
 * apparait sur les postes, et inversement. Ecriture par `MessagesEditeurTable::absorber` (memes
 * validations que pour un poste), poste « web » = UUID nul.
 *
 * E-MAIL : si `SUPPORT_MAIL` est renseigne ET que le transport est reel (ni `log` ni `array` : avec `log`,
 * `Mail::send` « reussit » sans rien envoyer), chaque message ecrit AU WEB est envoye au support. Le message
 * est TOUJOURS enregistre d'abord ; un echec d'envoi ne le perd pas (l'ecran le dit, texte a copier). Sans
 * support configure : aucun e-mail, l'utilisateur transmet lui-meme le texte puis le marque « Transmis »
 * (le poste n'envoie jamais d'e-mail ; Master Prompt §2.3).
 * Ouvert a tout compte connecte, comme le poste ; la capture d'ecran de la maquette n'existe pas.
 */
#[Layout('components.layouts.app')]
class Contact extends Component
{
    public const SOCIETE = 'FAGUEZ SARL';

    public const ROLE_SOCIETE = 'Cabinet d\'accompagnement des PME dans le cadre du PAEB';

    public const CONTACT = 'Dr MASSENON Rhodes';

    public const QUALIFICATION = 'Docteur en Génie Logiciel et Intelligence Artificielle';

    public const ROLE = 'Ingénierie logicielle';

    public const TELEPHONES = ['+229 01 51 33 50 40', '+229 01 97 31 24 37'];

    public const EMAIL = 'rarhodes06@gmail.com';

    public const EMAIL_PROFESSIONNEL = 'contact@massenonrhodes.com';

    /** Identifiant du « poste » web dans l'historique (UUID nul), comme les autres ecrans. */
    public const POSTE_WEB = Catalogue::POSTE_WEB;

    /** Les 7 options du selecteur « Module concerne » du Dart. */
    public const MODULES = [
        'Élevage & Couveuse', 'Ventes & Clients', 'Achats & Fournisseurs', 'Stocks & Catalogue',
        'Santé Animale', 'Comptabilité', 'Autre',
    ];

    /** `question` ou `bug` : les deux onglets du formulaire. */
    public string $type = 'question';

    public string $objet = '';

    public string $module = '';

    public string $message = '';

    public string $etapes = '';

    public ?string $messageAConfirmer = null;

    public ?string $texteAffiche = null;

    public ?string $erreur = null;

    public ?string $information = null;

    private function acteur(): User
    {
        $u = Auth::user();
        abort_if($u === null, 403);

        return $u;
    }

    public function choisirType(string $type): void
    {
        $this->acteur();
        $this->type = $type === 'bug' ? 'bug' : 'question';
        $this->erreur = $this->information = null;
    }

    /** « Nom (identifiant) — Role » : la signature qui voyage avec le message. */
    private function signature(User $u): string
    {
        $role = config('logialvia.roles')[$u->roles->first()?->name] ?? '—';

        return "{$u->name} ({$u->username}) — $role";
    }

    private function ecrire(User $acteur, array $ligne): ?string
    {
        return (new MessagesEditeurTable)->absorber(self::POSTE_WEB, $ligne + [
            'updated_at' => now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
        ]);
    }

    public function enregistrer(): void
    {
        $acteur = $this->acteur();
        $this->erreur = $this->information = null;
        $this->texteAffiche = null;

        $estBug = $this->type === 'bug';
        $sujet = trim($estBug ? $this->module : $this->objet);
        $texte = trim($this->message);

        $erreur = match (true) {
            $sujet === '' => $estBug ? 'Le module concerné est obligatoire.' : 'L\'objet est obligatoire.',
            $estBug && ! in_array($sujet, self::MODULES, true) => 'Le module concerné est inconnu.',
            $texte === '' => 'Le message est obligatoire.',
            default => null,
        };
        if ($erreur !== null) {
            $this->erreur = $erreur;

            return;
        }

        $id = (string) Str::uuid();
        $etapes = $estBug ? trim($this->etapes) : '';
        $motif = $this->ecrire($acteur, [
            'id' => $id,
            'horodatage' => now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
            'type' => $this->type,
            'sujet' => $sujet,
            'message' => $texte,
            'etapes' => $etapes === '' ? null : $etapes,
            'auteur' => $this->signature($acteur),
            'statut' => 'En attente',
            'supprime_le' => null,
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        Audit::enregistrer('message_editeur.cree', $acteur, ['id' => $id, 'type' => $this->type]);
        $this->objet = $this->module = $this->message = $this->etapes = '';
        $this->texteAffiche = $id;
        $quoi = $estBug ? 'Rapport' : 'Message';
        $copie = 'copiez le texte ci-dessous et transmettez-le vous-même au '.self::TELEPHONES[0].'.';
        $this->information = match ($this->envoyerAuSupport($id, $acteur)) {
            true => "$quoi enregistré et envoyé au support de l'éditeur.",
            false => "$quoi enregistré, mais l'e-mail n'a pas pu partir : $copie",
            null => "$quoi enregistré. Aucun e-mail n'est envoyé : $copie",
        };
    }

    /** Le support recevra-t-il un e-mail ? Adresse renseignee ET transport reel (jamais `log`/`array`). */
    public static function envoiActif(): bool
    {
        $support = trim((string) config('logialvia.support_mail'));

        return $support !== '' && filter_var($support, FILTER_VALIDATE_EMAIL) !== false
            && ! in_array(config('mail.default'), ['log', 'array'], true);
    }

    /** @return bool|null true : envoye ; false : echec (journalise) ; null : envoi non configure. */
    private function envoyerAuSupport(string $id, User $acteur): ?bool
    {
        if (! self::envoiActif()) {
            return null;
        }
        $repondreA = filter_var((string) $acteur->email, FILTER_VALIDATE_EMAIL) ?: null;
        try {
            $message = MessageEditeur::query()->whereKey($id)->firstOrFail();
            Mail::to(trim((string) config('logialvia.support_mail')))->send(new MessageEditeurMail($message, $repondreA));
        } catch (\Throwable $e) {
            Log::warning('Message editeur : e-mail au support non envoye.', ['id' => $id, 'erreur' => $e->getMessage()]);
            Audit::enregistrer('message_editeur.email_echec', $acteur, ['id' => $id]);

            return false;
        }
        Audit::enregistrer('message_editeur.email_envoye', $acteur, ['id' => $id]);

        return true;
    }

    public function montrerTexte(string $id): void
    {
        $this->acteur();
        $this->erreur = $this->information = null;
        $this->texteAffiche = MessageEditeur::query()->whereKey($id)->whereNull('supprime_le')->exists() ? $id : null;
    }

    public function marquerTransmis(string $id): void
    {
        $acteur = $this->acteur();
        $this->erreur = $this->information = null;

        $m = MessageEditeur::query()->whereKey($id)->whereNull('supprime_le')->first();
        if ($m === null) {
            $this->erreur = 'Ce message n\'a pas pu être marqué comme transmis.';

            return;
        }
        $motif = $this->ecrire($acteur, $this->ligne($m, ['statut' => 'Transmis']));
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        Audit::enregistrer('message_editeur.transmis', $acteur, ['id' => $id]);
        $this->information = 'Message marqué comme transmis.';
    }

    public function demanderSuppression(string $id): void
    {
        $this->acteur();
        $this->erreur = $this->information = null;
        $this->messageAConfirmer = MessageEditeur::query()->whereKey($id)->whereNull('supprime_le')->exists() ? $id : null;
    }

    public function annuler(): void
    {
        $this->acteur();
        $this->messageAConfirmer = null;
    }

    public function confirmerSuppression(): void
    {
        $acteur = $this->acteur();
        $this->erreur = $this->information = null;

        $id = $this->messageAConfirmer;
        $this->messageAConfirmer = null;
        $m = $id === null ? null : MessageEditeur::query()->whereKey($id)->whereNull('supprime_le')->first();
        if ($m === null) {
            $this->erreur = 'Ce message n\'a pas pu être supprimé.';

            return;
        }
        // Pierre tombale : la suppression voyage vers les postes ; la Corbeille peut la lever.
        $motif = $this->ecrire($acteur, $this->ligne($m, ['supprime_le' => now('UTC')->format('Y-m-d\TH:i:s.u\Z')]));
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        Audit::enregistrer('message_editeur.supprime', $acteur, ['id' => $id, 'sujet' => $m->sujet]);
        if ($this->texteAffiche === $id) {
            $this->texteAffiche = null;
        }
        $this->information = 'Message supprimé (il reste restaurable depuis la Corbeille).';
    }

    /** @return array<string, mixed> La ligne complete d'un message, avec les changements demandes. */
    private function ligne(MessageEditeur $m, array $changements): array
    {
        return $changements + [
            'id' => $m->id,
            'horodatage' => $m->horodatage->utc()->format('Y-m-d\TH:i:s.u\Z'),
            'type' => $m->type,
            'sujet' => $m->sujet,
            'message' => $m->message,
            'etapes' => $m->etapes,
            'auteur' => $m->auteur,
            'statut' => $m->statut,
            'supprime_le' => null,
        ];
    }

    /** Texte pret a coller (Dart : `MessageEditeur.texteAEnvoyer`). */
    public static function texteAEnvoyer(MessageEditeur $m): string
    {
        $lignes = [
            $m->estBug() ? 'LogiALVIA '.Aide::VERSION.' — Signalement de problème' : 'LogiALVIA '.Aide::VERSION.' — Question',
            'De : '.($m->auteur ?: '—'),
            ($m->estBug() ? 'Module concerné : ' : 'Objet : ').$m->sujet,
            '',
            $m->message,
        ];
        if (trim((string) $m->etapes) !== '') {
            array_push($lignes, '', 'Étapes pour reproduire :', $m->etapes);
        }

        return implode("\n", $lignes)."\n";
    }

    public function render()
    {
        $this->acteur();
        $messages = MessageEditeur::query()->whereNull('supprime_le')->orderByDesc('horodatage')->orderByDesc('id')->limit(200)->get();

        return view('livewire.contact', [
            'societe' => self::SOCIETE,
            'roleSociete' => self::ROLE_SOCIETE,
            'contact' => self::CONTACT,
            'qualification' => self::QUALIFICATION,
            'role' => self::ROLE,
            'telephones' => self::TELEPHONES,
            'email' => self::EMAIL,
            'emailProfessionnel' => self::EMAIL_PROFESSIONNEL,
            'version' => Aide::VERSION,
            'modules' => self::MODULES,
            'messages' => $messages,
            'messageAffiche' => ($affiche = $this->texteAffiche ? $messages->firstWhere('id', $this->texteAffiche) : null),
            'texteACopier' => $affiche ? self::texteAEnvoyer($affiche) : null,
            'aConfirmer' => $this->messageAConfirmer ? $messages->firstWhere('id', $this->messageAConfirmer) : null,
            'envoiActif' => self::envoiActif(),
            'fuseau' => config('logialvia.fuseau'),
        ])->title('Contactez l\'Éditeur');
    }
}
