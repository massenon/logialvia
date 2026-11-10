<?php

namespace App\Support;

use RuntimeException;

/** Interblocage persistant de la base : l'API repond 503 + `Retry-After`, le poste rejoue (`47r_`). */
class ServeurOccupe extends RuntimeException {}
