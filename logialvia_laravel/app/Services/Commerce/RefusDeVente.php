<?php

namespace App\Services\Commerce;

use RuntimeException;

/** Motif de refus d'une operation de commerce : il annule la transaction en cours et remonte tel quel a l'ecran. */
final class RefusDeVente extends RuntimeException {}
