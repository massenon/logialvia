<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>{{ $facture->type === 'FA' ? "Facture d'avoir" : 'Facture de vente' }} {{ $facture->reference }}</title>
    <style>
        :root { color-scheme: light; }
        * { box-sizing: border-box; }
        body { margin: 0; background: #f3f4f6; color: #111827; font: 13px/1.45 Roboto, "Segoe UI", Arial, sans-serif; }
        .barre { position: sticky; top: 0; display: flex; gap: 8px; align-items: center; justify-content: space-between;
                 padding: 10px 16px; background: #1f3a5f; color: #fff; }
        .barre a, .barre button { border: 1px solid #fff; background: transparent; color: #fff; padding: 6px 12px; border-radius: 6px;
                                  font: inherit; font-weight: 600; text-decoration: none; cursor: pointer; }
        .page { max-width: 820px; margin: 16px auto; padding: 28px 32px; background: #fff; border: 1px solid #d1d5db; }
        h1 { font-size: 20px; margin: 0 0 2px; }
        .entete { display: flex; justify-content: space-between; gap: 16px; border-bottom: 2px solid #1f3a5f; padding-bottom: 10px; margin-bottom: 14px; }
        .entreprise strong { font-size: 15px; }
        .petit { color: #4b5563; font-size: 12px; }
        .indicateurs { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin: 12px 0; }
        .indicateurs div { border: 1px solid #d1d5db; border-radius: 6px; padding: 6px 8px; }
        .indicateurs span { display: block; font-size: 10px; text-transform: uppercase; color: #6b7280; }
        .indicateurs b { font-size: 13px; }
        p { margin: 4px 0; }
        .mention { margin: 10px 0; padding: 8px 10px; border: 2px solid; font-weight: 700; }
        .mention.non { border-color: #b45309; color: #92400e; background: #fffbeb; }
        .mention.ok { border-color: #047857; color: #065f46; background: #ecfdf5; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { padding: 5px 6px; border-bottom: 1px solid #e5e7eb; text-align: left; }
        th { background: #f3f4f6; font-size: 11px; text-transform: uppercase; color: #374151; }
        .d { text-align: right; } .c { text-align: center; }
        tr.total td { font-weight: 700; border-top: 2px solid #1f3a5f; }
        .pied { margin-top: 18px; font-size: 11px; color: #6b7280; }
        @media (max-width: 640px) { .page { margin: 0; border: 0; padding: 16px; } .indicateurs { grid-template-columns: repeat(2, 1fr); } }
        @media print {
            body { background: #fff; }
            .barre { display: none; }
            .page { max-width: none; margin: 0; border: 0; padding: 0; }
            tr, .mention, .indicateurs div { break-inside: avoid; }
            a { color: inherit; text-decoration: none; }
            @page { margin: 14mm; }
        }
    </style>
</head>
<body>
    <div class="barre">
        <a href="/factures-mecef">← Retour aux factures</a>
        <button type="button" onclick="window.print()" data-action="imprimer-pdf">Imprimer / PDF</button>
    </div>

    <main class="page" data-facture="{{ $facture->reference }}">
        <header class="entete">
            <div class="entreprise">
                <strong>{{ $entreprise->raison_sociale }}</strong>
                @if ($entreprise->adresse_siege)<div class="petit">{{ $entreprise->adresse_siege }}</div>@endif
                @if ($entreprise->telephone || $entreprise->email)<div class="petit">{{ $entreprise->telephone }}{{ $entreprise->telephone && $entreprise->email ? ' · ' : '' }}{{ $entreprise->email }}</div>@endif
                @if ($entreprise->ifu || $entreprise->rccm)<div class="petit">@if ($entreprise->ifu)IFU : {{ $entreprise->ifu }}@endif{{ $entreprise->ifu && $entreprise->rccm ? ' · ' : '' }}@if ($entreprise->rccm)RCCM : {{ $entreprise->rccm }}@endif</div>@endif
            </div>
            <div style="text-align:right">
                <h1>{{ $facture->type === 'FA' ? "Facture d'avoir" : 'Facture de vente' }} — {{ $facture->reference }}</h1>
                <div class="petit">{{ $facture->date_facture->timezone($fuseau)->format('d/m/Y') }}</div>
            </div>
        </header>

        <section class="indicateurs">
            <div><span>Référence</span><b>{{ $facture->reference }}</b></div>
            <div><span>Type</span><b>{{ $facture->type }} — {{ $facture->type === 'FA' ? "Facture d'avoir" : 'Facture de vente' }}</b></div>
            <div><span>Total TTC</span><b data-total="ttc">{{ number_format($signe * $facture->total_ttc, 0, ',', ' ') }} FCFA</b></div>
            <div><span>Statut</span><b>{{ ['a_transmettre' => 'À transmettre', 'normalisee' => 'Normalisée', 'rejetee' => 'Rejetée'][$facture->statut] }}</b></div>
        </section>

        <p>Client : <strong>{{ $facture->client }}</strong></p>
        @if ($facture->client_ifu)<p>IFU du client : {{ $facture->client_ifu }}</p>@endif
        @if ($facture->client_adresse)<p>Adresse : {{ $facture->client_adresse }}</p>@endif
        @if ($facture->type === 'FA' && $facture->origine_ref)
            <p><strong>Avoir sur la facture {{ $facture->origine_ref }} — {{ $facture->motif ?: 'motif non précisé' }}.</strong></p>
        @endif
        @if ($facture->vente_ref)<p>Vente d'origine : {{ $facture->vente_ref }}</p>@endif

        @if ($normalisee)
            <div class="mention ok" data-mention="normalisee">
                <div>Code MeCeF/DGI : {{ $facture->code_mecef }}</div>
                <div style="font-weight:400">NIM : {{ $facture->nim }}@if ($facture->compteur)   ·   Compteur : {{ $facture->compteur }}@endif @if ($facture->date_normalisation)   ·   Normalisée le {{ $facture->date_normalisation->timezone($fuseau)->format('d/m/Y') }}@endif</div>
                @if ($facture->lien_verification)<div style="font-weight:400">Vérification : {{ $facture->lien_verification }}</div>@endif
            </div>
        @else
            <div class="mention non" data-mention="non-normalisee">
                FACTURE NON NORMALISÉE — en attente de transmission e-MECeF. Ce document ne vaut pas facture normalisée au sens de la réglementation fiscale.
                @if ($facture->erreur_transmission)<div style="font-weight:400">Dernier refus : {{ $facture->erreur_transmission }}</div>@endif
            </div>
        @endif

        <table data-table="lignes">
            <thead><tr><th>Désignation</th><th class="c">Qté</th><th class="d">P.U. HT</th><th class="c">Gr.</th><th class="d">Montant HT</th></tr></thead>
            <tbody>
                @forelse ($facture->lignes as $l)
                    <tr>
                        <td>{{ $l->designation }}</td>
                        <td class="c">{{ rtrim(rtrim(number_format($l->quantite, 2, ',', ' '), '0'), ',') }}{{ $l->unite ? ' '.$l->unite : '' }}</td>
                        <td class="d">{{ number_format($l->prix_unitaire_ht, 0, ',', ' ') }} FCFA</td>
                        <td class="c">{{ $l->groupe_taxe }}</td>
                        <td class="d">{{ number_format($signe * $l->montant_ht, 0, ',', ' ') }} FCFA</td>
                    </tr>
                @empty
                    <tr><td colspan="5">Cette facture ne comporte aucune ligne.</td></tr>
                @endforelse
            </tbody>
        </table>

        <table data-table="groupes">
            <thead><tr><th>Groupe de taxe</th><th class="c">Taux</th><th class="d">Base HT</th><th class="d">Taxe</th></tr></thead>
            <tbody>
                @foreach ($groupes as $g)
                    <tr data-groupe="{{ $g['groupe'] }}">
                        <td>{{ $g['groupe'] }}</td>
                        <td class="c">{{ $g['taux'] == 0 ? 'Exonéré' : rtrim(rtrim(number_format($g['taux'], 2, ',', ' '), '0'), ',').' %' }}</td>
                        <td class="d">{{ number_format($signe * $g['base'], 0, ',', ' ') }} FCFA</td>
                        <td class="d">{{ number_format($signe * $g['taxe'], 0, ',', ' ') }} FCFA</td>
                    </tr>
                @endforeach
                <tr class="total"><td>TOTAL</td><td></td><td class="d" data-total="ht">{{ number_format($signe * $facture->total_ht, 0, ',', ' ') }} FCFA</td><td class="d" data-total="taxe">{{ number_format($signe * $facture->total_taxe, 0, ',', ' ') }} FCFA</td></tr>
                <tr class="total"><td>NET À PAYER TTC</td><td></td><td></td><td class="d" data-total="net">{{ number_format($signe * $facture->total_ttc, 0, ',', ' ') }} FCFA</td></tr>
            </tbody>
        </table>

        <p class="pied">Émise {{ $emetteur === 'Web' ? 'depuis le web' : ($emetteur ? "depuis le poste $emetteur" : 'depuis un poste') }}. Une facture émise ne se modifie pas : pour la corriger, émettez un avoir.</p>
    </main>
</body>
</html>
