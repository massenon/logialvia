<?php

namespace App\Services\Achats;

/** Refus metier d'une operation d'achat : son message est affiche tel quel, la transaction est annulee. */
final class RefusAchat extends \RuntimeException {}
