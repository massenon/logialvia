<?php

namespace Tests\Concerns;

use ZipArchive;

/** Relit un classeur xlsx produit par `App\Support\ExportXlsx` : lignes de cellules, texte ou nombre en chaine. */
trait LitXlsx
{
    /** @return list<list<string>> Une ligne vide donne `[]`. */
    protected function lignesXlsx(string $octets): array
    {
        $chemin = tempnam(sys_get_temp_dir(), 'lecture');
        file_put_contents($chemin, $octets);
        $zip = new ZipArchive;
        $this->assertTrue($zip->open($chemin) === true, 'Le fichier est une archive xlsx valide.');
        $xml = $zip->getFromName('xl/worksheets/sheet1.xml');
        $zip->close();
        @unlink($chemin);
        $this->assertNotFalse($xml, 'La feuille 1 existe.');

        $feuille = simplexml_load_string($xml);
        $this->assertNotFalse($feuille, 'La feuille est du XML valide.');

        $lignes = [];
        foreach ($feuille->sheetData->row as $row) {
            $cellules = [];
            foreach ($row->c as $c) {
                preg_match('/^([A-Z]+)/', (string) $c['r'], $m);
                $col = 0;
                foreach (str_split($m[1]) as $lettre) {
                    $col = $col * 26 + (ord($lettre) - 64);
                }
                $cellules[$col - 1] = (string) ($c['t'] == 'inlineStr' ? $c->is->t : $c->v);
            }
            if ($cellules === []) {
                $lignes[] = [];

                continue;
            }
            $ligne = [];
            for ($i = 0; $i <= max(array_keys($cellules)); $i++) {
                $ligne[] = $cellules[$i] ?? '';
            }
            $lignes[] = $ligne;
        }

        return $lignes;
    }

    /** Nature d'une cellule : `n` (nombre) ou `inlineStr` (texte), par reference (`A1`). */
    protected function natureCellule(string $octets, string $ref): ?string
    {
        $chemin = tempnam(sys_get_temp_dir(), 'nature');
        file_put_contents($chemin, $octets);
        $zip = new ZipArchive;
        $zip->open($chemin);
        $xml = (string) $zip->getFromName('xl/worksheets/sheet1.xml');
        $zip->close();
        @unlink($chemin);
        $feuille = simplexml_load_string($xml);
        foreach ($feuille->sheetData->row as $row) {
            foreach ($row->c as $c) {
                if ((string) $c['r'] === $ref) {
                    return (string) ($c['t'] ?? 'n') ?: 'n';
                }
            }
        }

        return null;
    }
}
