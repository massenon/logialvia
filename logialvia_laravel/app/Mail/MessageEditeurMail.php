<?php

namespace App\Mail;

use App\Livewire\Contact;
use App\Models\MessageEditeur;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Address;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

/**
 * Message a l'editeur envoye au support (`SUPPORT_MAIL`) : meme texte que celui qu'on copie a l'ecran
 * (`Contact::texteAEnvoyer`, Dart : `MessageEditeur.texteAEnvoyer`). Texte brut.
 */
class MessageEditeurMail extends Mailable
{
    public function __construct(public MessageEditeur $message, public ?string $repondreA = null) {}

    public function envelope(): Envelope
    {
        $bug = $this->message->estBug();
        $objet = ($bug ? 'Signalement de problème' : 'Question').' — '.$this->message->sujet;

        return new Envelope(
            subject: 'LogiALVIA : '.$objet,
            replyTo: $this->repondreA !== null ? [new Address($this->repondreA)] : [],
        );
    }

    public function content(): Content
    {
        return new Content(text: 'mail.message-editeur', with: ['texte' => Contact::texteAEnvoyer($this->message)]);
    }
}
