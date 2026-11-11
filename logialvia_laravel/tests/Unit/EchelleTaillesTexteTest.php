<?php

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Tailles de texte uniformes partout (demande du client) : les vues n'utilisent que les jetons du Dart
 * (`caption` 12, `xs` 13,6, `section-title` 16, `modal-title` 18, `page-title` 22, `kpi-value` 24, `invalid` 11).
 * Les tailles arbitraires en pixels ne servent qu'aux ICONES (15 a 38 px).
 */
class EchelleTaillesTexteTest extends TestCase
{
    public function test_les_vues_n_utilisent_que_les_jetons_de_taille_de_texte(): void
    {
        $interdits = '/(?<![:\w-])text-(sm|base|lg|xl|2xl|3xl|body)\b|text-\[(9|10|11|12|13|14)px\]/';
        $fautes = [];
        $iterateur = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator(__DIR__.'/../../resources/views'));
        foreach ($iterateur as $fichier) {
            if (! $fichier->isFile() || str_ends_with($fichier->getFilename(), 'welcome.blade.php') || ! str_ends_with($fichier->getFilename(), '.php')) {
                continue;
            }
            if (preg_match_all($interdits, (string) file_get_contents($fichier->getPathname()), $m)) {
                $fautes[] = $fichier->getFilename().' : '.implode(', ', array_unique($m[0]));
            }
        }

        $this->assertSame([], $fautes, "Tailles de texte hors echelle :\n".implode("\n", $fautes));
    }
}
