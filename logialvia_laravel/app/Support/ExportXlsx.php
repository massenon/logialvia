<?php

namespace App\Support;

use RuntimeException;
use Symfony\Component\HttpFoundation\StreamedResponse;
use ZipArchive;

/**
 * Export tabulaire au format **xlsx** (Office Open XML), sans dependance : un classeur d'une feuille,
 * ecrit avec `ZipArchive`. Format d'export du web (decision du client) pour tout tableau a exporter.
 *
 *  - un nombre (`int`/`float`) est une cellule NUMERIQUE (formatee `#,##0` / `#,##0.00`) ;
 *  - tout le reste est du TEXTE (`inlineStr`) : un texte saisi (client, libelle, motif) qui commence par
 *    `=`, `+`, `-` ou `@` n'est JAMAIS evalue comme une formule, il n'y a donc rien a neutraliser ;
 *  - la premiere ligne (titre) est en gras ; la largeur des colonnes suit leur contenu.
 */
final class ExportXlsx
{
    public const TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

    private const STYLE_NORMAL = 0;

    private const STYLE_GRAS = 1;

    private const STYLE_ENTIER = 2;

    private const STYLE_DECIMAL = 3;

    /**
     * @param  list<list<string|int|float|null>>  $lignes
     * @return string Le classeur (octets).
     */
    public static function contenu(array $lignes, string $feuille = 'Rapport'): string
    {
        $chemin = tempnam(sys_get_temp_dir(), 'xlsx');
        $zip = new ZipArchive;
        if ($chemin === false || $zip->open($chemin, ZipArchive::OVERWRITE) !== true) {
            throw new RuntimeException('Impossible de créer le classeur.');
        }

        $zip->addFromString('[Content_Types].xml', self::typesDeContenu());
        $zip->addFromString('_rels/.rels', self::relationsRacine());
        $zip->addFromString('xl/workbook.xml', self::classeur(self::nomDeFeuille($feuille)));
        $zip->addFromString('xl/_rels/workbook.xml.rels', self::relationsClasseur());
        $zip->addFromString('xl/styles.xml', self::styles());
        $zip->addFromString('xl/worksheets/sheet1.xml', self::feuille($lignes));
        $zip->close();

        $octets = (string) file_get_contents($chemin);
        @unlink($chemin);

        return $octets;
    }

    /** @param list<list<string|int|float|null>> $lignes */
    public static function telecharger(array $lignes, string $nom, string $feuille = 'Rapport'): StreamedResponse
    {
        $octets = self::contenu($lignes, $feuille);

        return response()->streamDownload(function () use ($octets) {
            echo $octets;
        }, $nom, ['Content-Type' => self::TYPE]);
    }

    /** Les entiers ecrits en texte (« 1000 », « -400 ») deviennent des nombres ; codes et libelles restent du texte. */
    public static function typer(string|int|float|null $cellule): string|int|float|null
    {
        if (is_string($cellule) && preg_match('/^-?(0|[1-9][0-9]{0,14})$/', $cellule) === 1) {
            return (int) $cellule;
        }

        return $cellule;
    }

    // ------------------------------------------------------------------ Feuille

    /** @param list<list<string|int|float|null>> $lignes */
    private static function feuille(array $lignes): string
    {
        $largeurs = [];
        $xml = '';

        foreach ($lignes as $i => $ligne) {
            $numero = $i + 1;
            $cellules = '';
            foreach (array_values($ligne) as $j => $valeur) {
                $ref = self::colonne($j).$numero;
                if ($valeur === null || $valeur === '') {
                    continue;
                }
                $texte = is_string($valeur) ? $valeur : (string) $valeur;
                $largeurs[$j] = max($largeurs[$j] ?? 0, mb_strlen($texte));

                if (is_int($valeur) || is_float($valeur)) {
                    $style = is_int($valeur) ? self::STYLE_ENTIER : self::STYLE_DECIMAL;
                    $cellules .= '<c r="'.$ref.'" s="'.$style.'"><v>'.self::nombre($valeur).'</v></c>';
                } else {
                    $style = $i === 0 ? self::STYLE_GRAS : self::STYLE_NORMAL;
                    $cellules .= '<c r="'.$ref.'" s="'.$style.'" t="inlineStr"><is><t xml:space="preserve">'.self::echapper($texte).'</t></is></c>';
                }
            }
            $xml .= '<row r="'.$numero.'">'.$cellules.'</row>';
        }

        $colonnes = '';
        ksort($largeurs);
        foreach ($largeurs as $j => $largeur) {
            $largeur = min(60, max(8, $largeur + 2));
            $colonnes .= '<col min="'.($j + 1).'" max="'.($j + 1).'" width="'.$largeur.'" customWidth="1"/>';
        }

        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            .($colonnes === '' ? '' : '<cols>'.$colonnes.'</cols>')
            .'<sheetData>'.$xml.'</sheetData></worksheet>';
    }

    private static function nombre(int|float $v): string
    {
        return is_int($v) ? (string) $v : rtrim(rtrim(number_format($v, 10, '.', ''), '0'), '.');
    }

    /** `0` → A, `25` → Z, `26` → AA. */
    private static function colonne(int $index): string
    {
        $lettres = '';
        for ($n = $index; $n >= 0; $n = intdiv($n, 26) - 1) {
            $lettres = chr(65 + $n % 26).$lettres;
        }

        return $lettres;
    }

    private static function echapper(string $texte): string
    {
        // Caracteres de controle interdits en XML 1.0, puis echappement.
        $texte = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F]/u', '', $texte) ?? '';

        return htmlspecialchars($texte, ENT_XML1 | ENT_QUOTES, 'UTF-8');
    }

    /** Nom de feuille Excel : 31 caracteres au plus, sans `[ ] : * ? / \`. */
    private static function nomDeFeuille(string $nom): string
    {
        $nom = trim(str_replace(['[', ']', ':', '*', '?', '/', '\\'], ' ', $nom));

        return htmlspecialchars(mb_substr($nom === '' ? 'Feuille' : $nom, 0, 31), ENT_XML1 | ENT_QUOTES, 'UTF-8');
    }

    // ---------------------------------------------------------- Parties fixes

    private static function typesDeContenu(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            .'<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            .'<Default Extension="xml" ContentType="application/xml"/>'
            .'<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            .'<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            .'<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            .'</Types>';
    }

    private static function relationsRacine(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            .'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            .'</Relationships>';
    }

    private static function classeur(string $feuille): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            .'<sheets><sheet name="'.$feuille.'" sheetId="1" r:id="rId1"/></sheets></workbook>';
    }

    private static function relationsClasseur(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            .'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            .'<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
            .'</Relationships>';
    }

    /** 0 normal, 1 gras, 2 entier `#,##0` (format 3), 3 decimal `#,##0.00` (format 4). */
    private static function styles(): string
    {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            .'<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
            .'<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
            .'<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
            .'<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
            .'<cellXfs count="4">'
            .'<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
            .'<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
            .'<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
            .'<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
            .'</cellXfs>'
            .'<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
            .'</styleSheet>';
    }
}
