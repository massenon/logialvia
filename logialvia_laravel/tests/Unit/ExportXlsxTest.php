<?php

namespace Tests\Unit;

use App\Support\ExportXlsx;
use PHPUnit\Framework\TestCase;
use Tests\Concerns\LitXlsx;
use ZipArchive;

/** Le generateur xlsx : archive valide, nombres numeriques, texte jamais evalue, XML echappe. */
class ExportXlsxTest extends TestCase
{
    use LitXlsx;

    public function test_le_classeur_est_une_archive_xlsx_complete(): void
    {
        $octets = ExportXlsx::contenu([['Titre'], ['a', 1]], 'Recettes');
        $chemin = tempnam(sys_get_temp_dir(), 'z');
        file_put_contents($chemin, $octets);
        $zip = new ZipArchive;
        $this->assertTrue($zip->open($chemin) === true);

        foreach (['[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/styles.xml', 'xl/worksheets/sheet1.xml'] as $partie) {
            $this->assertNotFalse($zip->getFromName($partie), "Partie manquante : $partie");
            $this->assertNotFalse(simplexml_load_string($zip->getFromName($partie)), "XML invalide : $partie");
        }
        $this->assertStringContainsString('name="Recettes"', $zip->getFromName('xl/workbook.xml'));
        $zip->close();
        @unlink($chemin);
        $this->assertStringStartsWith('PK', $octets, 'Signature zip');
    }

    public function test_les_nombres_sont_numeriques_et_le_texte_reste_du_texte(): void
    {
        $octets = ExportXlsx::contenu([['Total', 1000, -400, 12.5, '001', '60,0 %']]);

        $this->assertSame([['Total', '1000', '-400', '12.5', '001', '60,0 %']], $this->lignesXlsx($octets));
        $this->assertSame('inlineStr', $this->natureCellule($octets, 'A1'));
        $this->assertSame('n', $this->natureCellule($octets, 'B1'));
        $this->assertSame('n', $this->natureCellule($octets, 'C1'));
        $this->assertSame('n', $this->natureCellule($octets, 'D1'));
        $this->assertSame('inlineStr', $this->natureCellule($octets, 'E1'), 'un code a zeros initiaux reste du texte');
        $this->assertSame('inlineStr', $this->natureCellule($octets, 'F1'));
    }

    public function test_typer_ne_convertit_que_les_entiers_sans_zero_initial(): void
    {
        $this->assertSame(1000, ExportXlsx::typer('1000'));
        $this->assertSame(-400, ExportXlsx::typer('-400'));
        $this->assertSame(0, ExportXlsx::typer('0'));
        $this->assertSame('007', ExportXlsx::typer('007'));
        $this->assertSame('1,5', ExportXlsx::typer('1,5'));
        $this->assertSame('CLI-001', ExportXlsx::typer('CLI-001'));
        $this->assertSame('97000000000000000000', ExportXlsx::typer('97000000000000000000'), 'trop long pour un entier fiable');
        $this->assertSame('', ExportXlsx::typer(''));
    }

    public function test_un_texte_qui_ressemble_a_une_formule_n_est_jamais_une_formule(): void
    {
        $octets = ExportXlsx::contenu([['=HYPERLINK("http://x")', '+1+1', '-2+3', '@SUM(A1)']]);

        $this->assertSame([['=HYPERLINK("http://x")', '+1+1', '-2+3', '@SUM(A1)']], $this->lignesXlsx($octets), 'texte intact, sans apostrophe');
        $chemin = tempnam(sys_get_temp_dir(), 'f');
        file_put_contents($chemin, $octets);
        $zip = new ZipArchive;
        $zip->open($chemin);
        $this->assertStringNotContainsString('<f>', (string) $zip->getFromName('xl/worksheets/sheet1.xml'), 'aucun element formule');
        $zip->close();
        @unlink($chemin);
    }

    public function test_les_caracteres_xml_sont_echappes_et_les_controles_retires(): void
    {
        $octets = ExportXlsx::contenu([['A & B <x> "q" \'s\'', "ligne\x01\x08propre"]]);

        $this->assertSame([['A & B <x> "q" \'s\'', 'lignepropre']], $this->lignesXlsx($octets));
    }

    public function test_les_lignes_vides_gardent_leur_place_et_les_colonnes_au_dela_de_z_sont_nommees(): void
    {
        $ligne = array_fill(0, 28, '');
        $ligne[27] = 'fin'; // colonne AB
        $octets = ExportXlsx::contenu([['Titre'], [], $ligne, ['dernier']]);

        $lignes = $this->lignesXlsx($octets);
        $this->assertSame(['Titre'], $lignes[0]);
        $this->assertSame([], $lignes[1]);
        $this->assertCount(28, $lignes[2]);
        $this->assertSame('fin', $lignes[2][27]);
        $this->assertSame(['dernier'], $lignes[3]);
        $this->assertSame('inlineStr', $this->natureCellule($octets, 'AB3'));
    }

    public function test_le_nom_de_feuille_est_valide_pour_excel(): void
    {
        $octets = ExportXlsx::contenu([['x']], 'Recettes/Dépenses: [2026] '.str_repeat('z', 40));
        $chemin = tempnam(sys_get_temp_dir(), 'n');
        file_put_contents($chemin, $octets);
        $zip = new ZipArchive;
        $zip->open($chemin);
        preg_match('/<sheet name="([^"]*)"/', (string) $zip->getFromName('xl/workbook.xml'), $m);
        $zip->close();
        @unlink($chemin);

        $this->assertLessThanOrEqual(31, mb_strlen(html_entity_decode($m[1])));
        $this->assertDoesNotMatchRegularExpression('#[\[\]:*?/\\\\]#', html_entity_decode($m[1]));
    }

    public function test_un_tableau_vide_donne_quand_meme_un_classeur_valide(): void
    {
        $this->assertSame([], $this->lignesXlsx(ExportXlsx::contenu([])));
    }

    public function test_les_titres_sont_en_gras_et_les_colonnes_s_ajustent(): void
    {
        $octets = ExportXlsx::contenu([['Un titre assez long pour elargir la colonne'], ['x']]);
        $chemin = tempnam(sys_get_temp_dir(), 'g');
        file_put_contents($chemin, $octets);
        $zip = new ZipArchive;
        $zip->open($chemin);
        $feuille = (string) $zip->getFromName('xl/worksheets/sheet1.xml');
        $zip->close();
        @unlink($chemin);

        $this->assertStringContainsString('r="A1" s="1"', $feuille, 'premiere ligne en gras');
        $this->assertStringContainsString('r="A2" s="0"', $feuille);
        preg_match('/width="([0-9.]+)"/', $feuille, $m);
        $this->assertGreaterThan(30, (float) $m[1]);
    }
}
