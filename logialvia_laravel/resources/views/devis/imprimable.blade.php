<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>Devis {{ $devis->reference }}</title>
    <style>
        :root { color-scheme: light; }
        * { box-sizing: border-box; }
        body { margin: 0; background: #f3f4f6; color: #111827; font: 14px/1.5 Roboto, "Segoe UI", Arial, sans-serif; }
        .barre { position: sticky; top: 0; display: flex; gap: 8px; align-items: center; justify-content: space-between;
                 padding: 10px 16px; background: #1f3a5f; color: #fff; }
        .barre a, .barre button { border: 1px solid #fff; background: transparent; color: #fff; padding: 6px 12px; border-radius: 6px;
                                  font: inherit; font-weight: 600; text-decoration: none; cursor: pointer; }
        .page { max-width: 820px; margin: 16px auto; padding: 28px 32px; background: #fff; border: 1px solid #d1d5db; }
        h1 { font-size: 22px; margin: 0 0 2px; }
        .entete { display: flex; justify-content: space-between; gap: 16px; border-bottom: 2px solid #1f3a5f; padding-bottom: 10px; margin-bottom: 16px; }
        .petit { color: #4b5563; font-size: 12px; }
        table { width: 100%; border-collapse: collapse; margin: 14px 0; }
        th, td { padding: 8px 10px; border-bottom: 1px solid #e5e7eb; text-align: left; vertical-align: top; }
        th { width: 32%; background: #f3f4f6; font-size: 12px; text-transform: uppercase; color: #374151; }
        .montant { font-size: 20px; font-weight: 700; color: #1f3a5f; }
        .mention { margin: 14px 0; padding: 8px 10px; border: 2px solid #b45309; color: #92400e; background: #fffbeb; font-weight: 700; }
        .pied { margin-top: 20px; font-size: 11px; color: #6b7280; }
        @media (max-width: 640px) { .page { margin: 0; border: 0; padding: 16px; } }
        @media print {
            body { background: #fff; }
            .barre { display: none; }
            .page { max-width: none; margin: 0; border: 0; padding: 0; }
            tr, .mention { break-inside: avoid; }
            @page { margin: 14mm; }
        }
    </style>
</head>
<body>
    <div class="barre">
        <a href="/ventes/devis">← Retour aux devis</a>
        <button type="button" onclick="window.print()" data-action="imprimer-pdf">Imprimer / PDF</button>
    </div>

    <main class="page" data-devis="{{ $devis->reference }}">
        <header class="entete">
            <div>
                <strong>{{ $entreprise->raison_sociale }}</strong>
                @if ($entreprise->adresse_siege)<div class="petit">{{ $entreprise->adresse_siege }}</div>@endif
                @if ($entreprise->telephone || $entreprise->email)<div class="petit">{{ $entreprise->telephone }}{{ $entreprise->telephone && $entreprise->email ? ' · ' : '' }}{{ $entreprise->email }}</div>@endif
                @if ($entreprise->ifu || $entreprise->rccm)<div class="petit">@if ($entreprise->ifu)IFU : {{ $entreprise->ifu }}@endif{{ $entreprise->ifu && $entreprise->rccm ? ' · ' : '' }}@if ($entreprise->rccm)RCCM : {{ $entreprise->rccm }}@endif</div>@endif
            </div>
            <div style="text-align:right">
                <h1>Devis — {{ $devis->reference }}</h1>
                <div class="petit">Émis le {{ $devis->date_emission->timezone($fuseau)->format('d/m/Y') }}</div>
            </div>
        </header>

        <table>
            <tr><th>Client</th><td data-champ="client">{{ $devis->client }}</td></tr>
            <tr><th>Objet / Prestation</th><td data-champ="objet">{{ $devis->objet }}</td></tr>
            <tr><th>Montant estimé</th><td class="montant" data-champ="montant">{{ number_format($devis->montant_estime, 0, ',', ' ') }} FCFA</td></tr>
            <tr><th>Validité</th><td data-champ="validite">{{ $devis->validite_jours }} jour{{ $devis->validite_jours > 1 ? 's' : '' }}, jusqu'au {{ $devis->dateExpiration()->timezone($fuseau)->format('d/m/Y') }}</td></tr>
            <tr><th>Statut</th><td data-champ="statut">{{ $expire ? 'Expiré' : ['emis' => 'Émis', 'accepte' => 'Accepté', 'refuse' => 'Refusé'][$devis->statut] }}</td></tr>
        </table>

        @if ($expire)
            <div class="mention" data-mention="expire">Ce devis a expiré : son montant n'engage plus l'entreprise.</div>
        @endif
        <div class="mention" data-mention="sans-valeur-de-facture">Devis — sans valeur de facture. Le montant est une estimation ; la facture normalisée sera établie à la livraison de la prestation.</div>

        <p class="pied">Établi par {{ $entreprise->raison_sociale }}. Bon pour accord : date, nom et signature du client.</p>
    </main>
</body>
</html>
