<?php

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Conformité de design : Tailwind (web) = Dart (poste).
 *
 * La SOURCE est le code Dart du poste (`logialvia_app/lib/core/theme`). Ce test
 * lit les fichiers Dart et la configuration Tailwind réelle, et échoue au moindre
 * écart : couleur, espacement, rayon, taille de texte, point de rupture. Il ne
 * recopie aucune valeur, il les compare.
 *
 * Il ne remplace pas la comparaison écran par écran, qui viendra avec chaque
 * module : il garantit que le socle de jetons ne dérive pas.
 */
class ConformiteDartTest extends TestCase
{
    private const THEME_DART = __DIR__.'/../../../logialvia_app/lib/core/theme/';

    /** @var array<string, mixed> */
    private static array $tailwind;

    public static function setUpBeforeClass(): void
    {
        $racine = dirname(__DIR__, 2);
        $sortie = shell_exec(
            'cd '.escapeshellarg($racine).' && node --input-type=module -e '
            .escapeshellarg("import c from './tailwind.config.js'; console.log(JSON.stringify(c.theme));"),
        );

        if (! is_string($sortie) || trim($sortie) === '') {
            self::markTestSkipped('Node est requis pour lire tailwind.config.js.');
        }

        self::$tailwind = json_decode($sortie, true, 512, JSON_THROW_ON_ERROR);
    }

    private function dart(string $fichier): string
    {
        $contenu = file_get_contents(self::THEME_DART.$fichier);
        $this->assertNotFalse($contenu, "Fichier Dart introuvable : $fichier");

        return $contenu;
    }

    /** `brandNavyDark` -> `brand-navy-dark`. */
    private static function kebab(string $camel): string
    {
        return strtolower(preg_replace('/(?<!^)[A-Z]/', '-$0', $camel));
    }

    public function test_les_couleurs_sont_celles_du_dart(): void
    {
        preg_match_all(
            '/static const Color (\w+) = Color\(0xFF([0-9A-Fa-f]{6})\)/',
            $this->dart('app_colors.dart'),
            $trouvees,
            PREG_SET_ORDER,
        );

        $this->assertCount(15, $trouvees, 'Le Dart doit déclarer les 15 couleurs de la charte.');

        $couleurs = self::$tailwind['extend']['colors'];
        $this->assertCount(15, $couleurs, 'Tailwind ne doit déclarer ni plus ni moins de couleurs que le Dart.');

        foreach ($trouvees as [, $nom, $hex]) {
            $cle = self::kebab($nom);
            $this->assertArrayHasKey($cle, $couleurs, "Couleur absente de Tailwind : $cle");
            $this->assertSame(
                strtoupper('#'.$hex),
                strtoupper($couleurs[$cle]),
                "Couleur $cle différente du Dart.",
            );
        }
    }

    public function test_les_espacements_sont_ceux_du_dart(): void
    {
        preg_match_all(
            '/static const double (xs|sm|md|lg|xl) = ([0-9.]+);/',
            $this->dart('app_spacing.dart'),
            $trouvees,
            PREG_SET_ORDER,
        );

        $this->assertCount(5, $trouvees);
        foreach ($trouvees as [, $nom, $valeur]) {
            $this->assertSame(
                ((float) $valeur).'px',
                (float) self::$tailwind['extend']['spacing'][$nom].'px',
                "Espacement $nom différent du Dart.",
            );
        }
    }

    public function test_les_rayons_sont_ceux_du_dart(): void
    {
        $dart = $this->dart('app_radius.dart');
        preg_match('/static const double card = ([0-9.]+);/', $dart, $carte);
        preg_match('/static const double loginCard = ([0-9.]+);/', $dart, $connexion);

        $rayons = self::$tailwind['extend']['borderRadius'];
        $this->assertSame((float) $carte[1], (float) $rayons['lg'], 'rounded-lg doit valoir AppRadius.card.');
        $this->assertSame((float) $connexion[1], (float) $rayons['2xl'], 'rounded-2xl doit valoir AppRadius.loginCard.');
    }

    public function test_les_points_de_rupture_sont_ceux_du_dart(): void
    {
        preg_match_all(
            '/static const double (sm|md|lg|xl) = ([0-9.]+);/',
            $this->dart('app_breakpoints.dart'),
            $trouvees,
            PREG_SET_ORDER,
        );

        $this->assertCount(4, $trouvees);
        foreach ($trouvees as [, $nom, $valeur]) {
            $this->assertSame(
                (float) $valeur,
                (float) self::$tailwind['screens'][$nom],
                "Point de rupture $nom différent du Dart.",
            );
        }
    }

    public function test_la_police_et_les_tailles_de_texte_sont_celles_du_dart(): void
    {
        $dart = $this->dart('app_typography.dart');

        preg_match("/static const String fontFamily = '(\\w+)'/", $dart, $police);
        $this->assertSame($police[1], self::$tailwind['extend']['fontFamily']['sans'][0]);

        preg_match('/static const double textXs = ([0-9.]+);/', $dart, $xs);
        $this->assertSame((float) $xs[1], (float) self::$tailwind['extend']['fontSize']['xs'][0]);

        // Les styles nommes du Dart : taille de chaque TextStyle.
        $attendus = [
            'pageTitle' => 'page-title',
            'modalTitle' => 'modal-title',
            'sectionTitle' => 'section-title',
            'body' => 'body',
            'caption' => 'caption',
            'kpiValue' => 'kpi-value',
            'invalidFeedback' => 'invalid',
        ];

        foreach ($attendus as $styleDart => $classe) {
            $this->assertSame(
                1,
                preg_match(
                    '/static const TextStyle '.$styleDart.' = TextStyle\(\s*fontFamily: fontFamily,\s*fontSize: ([0-9.]+),/',
                    $dart,
                    $taille,
                ),
                "Style Dart introuvable : $styleDart",
            );
            $this->assertSame(
                (float) $taille[1],
                (float) self::$tailwind['extend']['fontSize'][$classe][0],
                "Taille de texte $classe différente du Dart ($styleDart).",
            );
        }
    }

    public function test_la_police_roboto_du_dart_est_servie_localement(): void
    {
        $this->assertFileExists(dirname(__DIR__, 2).'/public/fonts/Roboto-Variable.ttf');
        $this->assertFileEquals(
            dirname(__DIR__, 3).'/logialvia_app/assets/fonts/Roboto-Variable.ttf',
            dirname(__DIR__, 2).'/public/fonts/Roboto-Variable.ttf',
            'La police servie au web doit être le fichier même du poste.',
        );
    }
}
