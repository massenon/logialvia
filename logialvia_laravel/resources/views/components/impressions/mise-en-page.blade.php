@props(['titre', 'orientation' => 'portrait'])
{{-- Mise en page IMPRIMABLE (equivalent web des PDF du poste : `core/pdf/document_pdf.dart`).
     CSS `@media print` + bouton « Imprimer / PDF » (le navigateur offre « Enregistrer au format PDF »). --}}
@php($entreprise = \App\Models\ParametresEntreprise::courant())
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $titre }} — {{ $entreprise->raison_sociale }}</title>
    @vite(['resources/css/app.css'])
    <style>
        @page { size: A4 {{ $orientation }}; margin: 14mm; }
        body { background: #fff; color: #111; }
        .document { max-width: 210mm; margin: 0 auto; padding: 16px; }
        .document.paysage { max-width: 297mm; }
        .document table { width: 100%; border-collapse: collapse; font-size: 12px; }
        .document th, .document td { border-bottom: 1px solid #ccc; padding: 4px 6px; text-align: left; }
        .document th { background: #f2f2f2; text-transform: uppercase; font-size: 11px; }
        .document .droite { text-align: right; }
        .document .centre { text-align: center; }
        .document tfoot td { font-weight: 700; border-top: 2px solid #111; }
        .document tr { break-inside: avoid; }
        @media print {
            .no-print { display: none !important; }
            .document { padding: 0; max-width: none; }
            body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        }
    </style>
</head>
<body>
    <div class="document {{ $orientation === 'landscape' ? 'paysage' : '' }}">
        <div class="no-print" style="display:flex;gap:8px;justify-content:flex-end;margin-bottom:12px">
            <button type="button" onclick="window.print()" data-action="imprimer"
                    style="border:1px solid #003366;background:#003366;color:#fff;border-radius:8px;padding:8px 16px;font-weight:700;cursor:pointer">Imprimer / PDF</button>
            <button type="button" onclick="window.close()"
                    style="border:1px solid #999;border-radius:8px;padding:8px 16px;font-weight:700;cursor:pointer">Fermer</button>
        </div>

        <header style="display:flex;justify-content:space-between;gap:16px;border-bottom:2px solid #003366;padding-bottom:8px;margin-bottom:12px">
            <div>
                <p style="font-size:16px;font-weight:700" data-entreprise>{{ $entreprise->raison_sociale }}</p>
                <p style="font-size:11px">{{ $entreprise->adresse_siege }} @if ($entreprise->telephone) · {{ $entreprise->telephone }} @endif</p>
                <p style="font-size:11px">@if ($entreprise->ifu) IFU {{ $entreprise->ifu }} @endif @if ($entreprise->rccm) · RCCM {{ $entreprise->rccm }} @endif</p>
            </div>
            <div style="text-align:right">
                <p style="font-size:18px;font-weight:700" data-titre-document>{{ $titre }}</p>
                <p style="font-size:11px">Édité le {{ now(config('logialvia.fuseau'))->format('d/m/Y à H:i') }}</p>
            </div>
        </header>

        {{ $slot }}

        <p style="margin-top:16px;font-size:10px;color:#555">Document généré par LogiALVIA (web). Le stock et le PMP, propres à chaque poste, n'y figurent pas.</p>
    </div>
</body>
</html>
