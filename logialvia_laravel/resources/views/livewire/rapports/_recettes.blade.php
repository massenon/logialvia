<div data-onglet-actif="recettes">
    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 xl:grid-cols-4">
        @include('livewire.rapports._carte', ['kpi' => 'total-recettes', 'libelle' => 'Total Recettes', 'valeur' => $f::montant($x['total_recettes']), 'detail' => 'Avicole + Commerce Annexe', 'accent' => 'border-success-deep'])
        @include('livewire.rapports._carte', ['kpi' => 'total-depenses', 'libelle' => 'Total Dépenses', 'valeur' => $f::montant($x['total_depenses']), 'detail' => 'Intrants + Charges diverses', 'accent' => 'border-error-deep'])
        @include('livewire.rapports._carte', ['kpi' => 'resultat-net', 'libelle' => 'Résultat Net', 'valeur' => $f::montant($x['resultat_net']), 'detail' => 'Recettes − Dépenses', 'accent' => 'border-brand-gold', 'couleur' => $x['resultat_net'] < 0 ? 'text-error-deep' : 'text-brand-navy'])
        @include('livewire.rapports._carte', ['kpi' => 'taux-marge', 'libelle' => 'Taux de Marge Brute', 'valeur' => $x['taux_marge'] === null ? '—' : $f::pourcentage($x['taux_marge']), 'detail' => 'Résultat Net / Total Recettes', 'accent' => 'border-info-blue'])
    </div>

    <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md" data-bloc="comparatif">
        <h2 class="mb-sm text-section-title font-bold">Chiffre d'Affaires vs Charges</h2>
        @if ($x['maximum'] < 0.01)
            <p class="text-xs text-outline" data-vide="comparatif">Aucun produit ni charge sur la période sélectionnée.</p>
        @else
            @foreach ([['Recettes', $x['total_recettes'], 'bg-success-deep'], ['Dépenses', $x['total_depenses'], 'bg-error-deep']] as [$lib, $montant, $couleur])
                @php($ratio = max(0, min(1, $montant / $x['maximum'])))
                <div class="mb-xs flex items-center gap-sm text-caption">
                    <span class="w-20 text-outline">{{ $lib }}</span>
                    <div class="h-4 flex-1 overflow-hidden rounded-full bg-surface-zebra">
                        <div class="h-full {{ $couleur }}" style="width: {{ round($ratio * 100, 1) }}%" data-barre="{{ $lib }}"></div>
                    </div>
                    <span class="w-24 text-right font-bold">{{ $f::nombre($montant) }}</span>
                </div>
            @endforeach
        @endif
    </section>

    <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md">
        <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
            <h2 class="text-section-title font-bold">Détail par catégorie SYSCOHADA</h2>
            @include('livewire.rapports._filtre', ['modele' => 'filtreCentre', 'tous' => 'Tous les centres de profit', 'options' => \App\Livewire\Rapports::CENTRES, 'courant' => $x['centre']])
        </div>
        @if (count($x['lignes']) === 0)
            <p class="text-xs text-outline" data-vide="recettes">
                {{ $x['toutes'] === 0 ? 'Aucune écriture de gestion sur la période. Les ventes et les dépenses enregistrées apparaissent ici automatiquement.' : 'Aucune ligne ne correspond à ce centre de profit.' }}</p>
        @else
            <div class="hidden overflow-x-auto sm:block">
                <table class="w-full text-left text-xs" data-table="recettes">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-sm py-sm">Période</th><th class="px-sm py-sm">N° Pièce</th>
                            <th class="px-sm py-sm">Catégorie SYSCOHADA</th><th class="px-sm py-sm">Centre de Profit</th>
                            <th class="px-sm py-sm text-right">Encaissement</th><th class="px-sm py-sm text-right">Décaissement</th>
                            <th class="px-sm py-sm text-right">Solde Cumulé</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($x['lignes'] as $l)
                            <tr class="border-b border-outline-variant {{ $loop->odd ? 'bg-surface-zebra' : '' }}" data-compte="{{ $l['numero'] }}">
                                <td class="px-sm py-sm">{{ $l['periode'] }}</td>
                                <td class="px-sm py-sm font-mono" data-piece>{{ $l['numero_piece'] }}</td>
                                <td class="px-sm py-sm">{{ $l['categorie'] }}</td>
                                <td class="px-sm py-sm" data-centre>{{ $l['centre'] }}</td>
                                <td class="px-sm py-sm text-right text-success-deep" data-encaissement>{{ $m($l['encaissement']) }}</td>
                                <td class="px-sm py-sm text-right text-error-deep" data-decaissement>{{ $m($l['decaissement']) }}</td>
                                <td class="px-sm py-sm text-right font-mono {{ $l['cumul'] < 0 ? 'text-error-deep' : '' }}" data-cumul>{{ $f::nombre($l['cumul']) }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($x['lignes'] as $l)
                    <article class="rounded-lg border border-outline-variant p-md" data-carte-compte="{{ $l['numero'] }}">
                        <p class="font-bold text-brand-navy">{{ $l['categorie'] }}</p>
                        <p class="text-caption text-outline">{{ $l['centre'] }} · pièce {{ $l['numero_piece'] }}</p>
                        <p class="text-xs">Encaissement : <span class="text-success-deep">{{ $m($l['encaissement']) }}</span> · Décaissement : <span class="text-error-deep">{{ $m($l['decaissement']) }}</span></p>
                        <p class="text-xs font-bold">Solde cumulé : {{ $f::nombre($l['cumul']) }}</p>
                    </article>
                @endforeach
            </div>
        @endif
    </section>
</div>
