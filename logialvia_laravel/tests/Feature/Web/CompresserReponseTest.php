<?php

namespace Tests\Feature\Web;

use App\Http\Middleware\CompresserReponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Tests\TestCase;

/** Middleware CompresserReponse (47x_) : Brotli si disponible, sinon gzip ; jamais de double compression. */
class CompresserReponseTest extends TestCase
{
    private function passer(Response|JsonResponse|BinaryFileResponse $reponse, ?string $accept): \Symfony\Component\HttpFoundation\Response
    {
        $requete = Request::create('/x');
        if ($accept !== null) {
            $requete->headers->set('Accept-Encoding', $accept);
        }

        return (new CompresserReponse)->handle($requete, fn () => $reponse);
    }

    private function html(int $octets = 5000): Response
    {
        return new Response(str_repeat('<p>LogiALVIA</p>', (int) ceil($octets / 16)), 200, ['Content-Type' => 'text/html; charset=UTF-8']);
    }

    public function test_gzip_quand_brotli_n_est_pas_disponible_ou_pas_accepte(): void
    {
        $original = $this->html()->getContent();
        $r = $this->passer($this->html(), 'gzip, deflate');

        $this->assertSame('gzip', $r->headers->get('Content-Encoding'));
        $this->assertSame($original, gzdecode($r->getContent()));
        $this->assertSame((string) strlen($r->getContent()), $r->headers->get('Content-Length'));
        $this->assertStringContainsString('Accept-Encoding', (string) $r->headers->get('Vary'));
        $this->assertLessThan(strlen($original) / 5, strlen($r->getContent()));
    }

    public function test_brotli_est_prefere_s_il_est_installe_et_accepte(): void
    {
        $r = $this->passer($this->html(), 'br, gzip');

        if (function_exists('brotli_compress')) {
            $this->assertSame('br', $r->headers->get('Content-Encoding'));
            $this->assertSame($this->html()->getContent(), brotli_uncompress($r->getContent()));
        } else {
            $this->assertSame('gzip', $r->headers->get('Content-Encoding'), 'repli gzip quand l\'extension brotli manque');
        }
    }

    public function test_rien_sans_accept_encoding_ni_si_q_zero(): void
    {
        $this->assertNull($this->passer($this->html(), null)->headers->get('Content-Encoding'));
        $this->assertNull($this->passer($this->html(), 'gzip;q=0')->headers->get('Content-Encoding'));
        $this->assertNull($this->passer($this->html(), 'identity')->headers->get('Content-Encoding'));
    }

    public function test_petites_reponses_deja_encodees_et_binaires_sont_laissees(): void
    {
        $this->assertNull($this->passer($this->html(200), 'gzip')->headers->get('Content-Encoding'), 'sous 1 Ko');

        $deja = $this->html();
        $deja->headers->set('Content-Encoding', 'br');
        $contenu = $deja->getContent();
        $r = $this->passer($deja, 'gzip');
        $this->assertSame('br', $r->headers->get('Content-Encoding'));
        $this->assertSame($contenu, $r->getContent());

        $xlsx = new Response(str_repeat('x', 5000), 200, ['Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
        $this->assertNull($this->passer($xlsx, 'gzip')->headers->get('Content-Encoding'));

        $fichier = new BinaryFileResponse(public_path('manifest.webmanifest'));
        $this->assertNull($this->passer($fichier, 'gzip')->headers->get('Content-Encoding'));
    }

    public function test_le_json_de_livewire_est_compresse(): void
    {
        $r = $this->passer(new JsonResponse(['lignes' => array_fill(0, 200, 'LogiALVIA')]), 'gzip');

        $this->assertSame('gzip', $r->headers->get('Content-Encoding'));
        $this->assertCount(200, json_decode(gzdecode($r->getContent()), true)['lignes']);
    }

    public function test_une_vraie_page_est_compressee_de_bout_en_bout(): void
    {
        $brut = $this->get('/hors-ligne')->assertOk();
        $this->assertNull($brut->headers->get('Content-Encoding'));

        $reponse = $this->withHeaders(['Accept-Encoding' => 'gzip'])->get('/hors-ligne')->assertOk();
        $this->assertSame('gzip', $reponse->headers->get('Content-Encoding'));
        $this->assertSame($brut->getContent(), gzdecode($reponse->getContent()));
    }
}
