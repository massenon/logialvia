<div data-onglet-actif="tresorerie">
    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 xl:grid-cols-4">
        @foreach ($x['libelles'] as $lib)
            @include('livewire.rapports._carte', [
                'kpi' => 'compte-'.\Illuminate\Support\Str::slug($lib), 'libelle' => $lib === 'Caisse' ? 'Caisse Espèces' : $lib,
                'valeur' => $f::montant($x['clotures'][$lib]), 'detail' => 'Solde au '.$d($finPeriode),
                'accent' => $lib === 'Caisse' ? 'border-brand-navy' : 'border-brand-gold', 'icone' => $lib === 'Caisse' ? 'payments' : 'smartphone',
            ])
        @endforeach
        @include('livewire.rapports._carte', ['kpi' => 'tresorerie-nette', 'icone' => 'account_balance_wallet', 'libelle' => 'Trésorerie Nette Globale', 'valeur' => $f::montant($x['nette']), 'detail' => 'Cumul de tous les comptes de classe 5', 'accent' => 'border-success-deep'])
    </div>

    <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md">
        <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
            <h2 class="text-section-title font-bold">Mouvements de trésorerie</h2>
            @include('livewire.rapports._filtre', [
                'modele' => 'filtreCompte', 'tous' => 'Tous les comptes', 'courant' => $x['compte'],
                'options' => collect($x['libelles'])->mapWithKeys(fn ($l) => [$l => $l === 'Caisse' ? 'Caisse Espèces' : $l])->all(),
            ])
        </div>
        <div class="hidden overflow-x-auto sm:block">
            <table class="w-full text-left text-xs" data-table="tresorerie">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-sm py-sm">Date</th><th class="px-sm py-sm">Compte</th><th class="px-sm py-sm">Type d'opération</th>
                        <th class="px-sm py-sm">Libellé</th><th class="px-sm py-sm text-right">Entrée</th>
                        <th class="px-sm py-sm text-right">Sortie</th><th class="px-sm py-sm text-right">Solde progressif</th>
                    </tr>
                </thead>
                <tbody>
                    {{-- Soldes d'ouverture : sans eux, la première valeur du solde progressif sortirait de nulle part. --}}
                    @foreach ($x['ouvertures'] as $o)
                        <tr class="border-b border-outline-variant bg-surface-zebra" data-ouverture="{{ $o['court'] }}">
                            <td class="px-sm py-sm">{{ $d($debutPeriode) }}</td>
                            <td class="px-sm py-sm">{{ $o['court'] }}</td>
                            <td class="px-sm py-sm font-bold text-outline" colspan="4">Solde d'Ouverture</td>
                            <td class="px-sm py-sm text-right font-mono" data-solde>{{ $f::nombre($o['ouverture']) }}</td>
                        </tr>
                    @endforeach
                    @foreach ($x['mouvements'] as $mv)
                        <tr class="border-b border-outline-variant {{ $loop->even ? 'bg-surface-zebra' : '' }}" data-mouvement>
                            <td class="px-sm py-sm">{{ $d($mv['date']) }}</td>
                            <td class="px-sm py-sm" data-compte>{{ $mv['compte'] }}</td>
                            <td class="px-sm py-sm" data-type>{{ $mv['type'] }}</td>
                            <td class="px-sm py-sm">{{ $mv['libelle'] }}</td>
                            <td class="px-sm py-sm text-right font-bold text-success-deep" data-entree>{{ $m($mv['entree']) }}</td>
                            <td class="px-sm py-sm text-right font-bold text-error-deep" data-sortie>{{ $m($mv['sortie']) }}</td>
                            <td class="px-sm py-sm text-right font-mono" data-solde>{{ $f::nombre($mv['solde']) }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </div>
        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @foreach ($x['ouvertures'] as $o)
                <article class="rounded-lg bg-surface-zebra p-md text-xs" data-carte-ouverture="{{ $o['court'] }}">
                    <p class="font-bold text-outline">Solde d'Ouverture — {{ $o['court'] }} ({{ $d($debutPeriode) }})</p>
                    <p class="font-mono">{{ $f::nombre($o['ouverture']) }}</p>
                </article>
            @endforeach
            @foreach ($x['mouvements'] as $mv)
                <article class="rounded-lg border border-outline-variant p-md text-xs" data-carte-mouvement>
                    <p class="font-bold text-brand-navy">{{ $d($mv['date']) }} · {{ $mv['compte'] }} · {{ $mv['type'] }}</p>
                    <p class="text-outline">{{ $mv['libelle'] }}</p>
                    <p>Entrée : <span class="text-success-deep">{{ $m($mv['entree']) }}</span> · Sortie : <span class="text-error-deep">{{ $m($mv['sortie']) }}</span></p>
                    <p class="font-bold">Solde progressif : {{ $f::nombre($mv['solde']) }}</p>
                </article>
            @endforeach
        </div>
        @if (count($x['mouvements']) === 0)
            <p class="mt-sm text-xs text-outline" data-vide="tresorerie">Aucun mouvement de trésorerie sur la période. Les encaissements de vente et les décaissements d'achat apparaissent ici automatiquement.</p>
        @endif
    </section>
</div>
