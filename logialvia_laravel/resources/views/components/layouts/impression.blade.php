@props(['titre', 'entreprise', 'paysage' => false])
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $titre }} — {{ $entreprise->raison_sociale }}</title>
    {{-- Page autonome : aucun asset, elle s'imprime telle quelle (`@media print`). --}}
    <style>
        body { font-family: Roboto, Arial, sans-serif; color: #1a1a1a; margin: 0; padding: 24px; font-size: 13px; }
        h1 { font-size: 20px; margin: 0 0 4px; }
        .entete { border-bottom: 2px solid #1b2a4a; margin-bottom: 16px; padding-bottom: 8px; }
        .entete p { margin: 0; color: #555; }
        .indicateurs { display: flex; flex-wrap: wrap; gap: 24px; margin: 12px 0; }
        .indicateurs div { min-width: 120px; }
        .indicateurs span { display: block; font-size: 11px; text-transform: uppercase; color: #666; }
        .indicateurs strong { font-size: 15px; }
        table { width: 100%; border-collapse: collapse; margin: 12px 0; }
        th, td { border-bottom: 1px solid #ddd; padding: 6px 8px; text-align: left; }
        th { background: #f1f1f1; font-size: 11px; text-transform: uppercase; }
        .droite { text-align: right; } .centre { text-align: center; }
        tfoot td { font-weight: bold; border-top: 2px solid #1b2a4a; }
        .note { color: #555; font-size: 12px; }
        .alerte { font-weight: bold; color: #a00; }
        .signatures { display: flex; justify-content: space-between; margin-top: 64px; }
        .signatures div { width: 40%; border-top: 1px solid #333; padding-top: 4px; text-align: center; }
        .barre { margin-bottom: 16px; }
        .barre button { background: #1b2a4a; color: #fff; border: 0; border-radius: 6px; padding: 8px 16px; cursor: pointer; }
        @page { size: {{ $paysage ? 'A4 landscape' : 'A4' }}; margin: 14mm; }
        @media print { .barre { display: none; } body { padding: 0; } }
    </style>
</head>
<body>
    <div class="barre"><button type="button" onclick="window.print()" data-action="imprimer">Imprimer / PDF</button></div>
    <div class="entete">
        <h1>{{ $entreprise->raison_sociale }}</h1>
        <p>{{ collect([$entreprise->adresse_siege, $entreprise->telephone, $entreprise->email])->filter()->implode(' · ') }}</p>
        <p>{{ collect([$entreprise->ifu ? 'IFU '.$entreprise->ifu : null, $entreprise->rccm ? 'RCCM '.$entreprise->rccm : null])->filter()->implode(' · ') }}</p>
    </div>
    <h2 style="margin:0 0 8px;font-size:17px">{{ $titre }}</h2>
    {{ $slot }}
</body>
</html>
