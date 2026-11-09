<?php

namespace App\Livewire;

use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Contactez l'Editeur (Dart : `contact_editeur_screen.dart`, Doc F9). Page STATIQUE : les
 * coordonnees de l'editeur (`Editeur` du poste), sans formulaire.
 *
 * ECART DECLARE : le poste enregistre les messages dans `MESSAGES_EDITEUR` ; le serveur n'a pas cette
 * table et n'envoie aucun e-mail. Rien n'est donc « envoye » depuis le web : on ne promet pas
 * un envoi qui n'aurait pas lieu (meme principe que le poste, Master Prompt §2.3).
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

    public function render()
    {
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
        ])->title('Contactez l\'Éditeur');
    }
}
