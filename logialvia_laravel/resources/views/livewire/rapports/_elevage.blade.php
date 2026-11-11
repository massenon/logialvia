<div data-onglet-actif="elevage">
    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 xl:grid-cols-4">
        @include('livewire.rapports._carte', ['kpi' => 'effectif-total', 'icone' => 'pets', 'libelle' => 'Effectif Total', 'valeur' => (string) $x['effectif_total'], 'detail' => 'Toutes filières suivies', 'accent' => 'border-brand-navy'])
        @include('livewire.rapports._carte', ['kpi' => 'sujets-malades', 'icone' => 'coronavirus', 'libelle' => 'Sujets Malades', 'valeur' => (string) $x['malades'], 'detail' => 'Infirmerie active', 'accent' => $x['malades'] > 0 ? 'border-error-deep' : 'border-success-deep'])
        @include('livewire.rapports._carte', ['kpi' => 'taux-eclosion', 'icone' => 'egg', 'libelle' => 'Taux Éclosion Moyen', 'valeur' => $x['taux_eclosion'] === null ? '—' : $f::pourcentage($x['taux_eclosion']), 'detail' => $x['taux_eclosion'] === null ? 'Aucun cycle éclos à ce jour' : 'Sur les cycles éclos', 'accent' => 'border-brand-gold'])
        @include('livewire.rapports._carte', ['kpi' => 'cycles-en-cours', 'icone' => 'event_repeat', 'libelle' => 'Cycles en Cours', 'valeur' => (string) $x['cycles_en_cours'], 'detail' => 'Couveuse active', 'accent' => 'border-info-blue'])
    </div>

    {{-- Tableau 1 --}}
    <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md" data-bloc="recensement">
        <h2 class="mb-sm text-section-title font-bold">Tableau 1 — Recensement &amp; Structure du Cheptel</h2>
        @if (count($x['recensement']) === 0)
            <p class="text-xs text-outline" data-vide="recensement">Aucune journée d'élevage saisie sur la période. Le recensement se construit à partir des fiches journalières.</p>
        @else
            <div class="hidden overflow-x-auto sm:block">
                <table class="w-full text-left text-xs" data-table="recensement">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-sm py-sm">Lot / Souche</th><th class="px-sm py-sm text-right">Effectif Total</th>
                            <th class="px-sm py-sm text-right">Géniteurs / Matures</th><th class="px-sm py-sm text-right">Jeunes</th>
                            <th class="px-sm py-sm text-right">Morts (Période)</th><th class="px-sm py-sm text-right">Dons (Période)</th>
                            <th class="px-sm py-sm text-center">Effectif Malade</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($x['recensement'] as $r)
                            <tr class="border-b border-outline-variant {{ $loop->odd ? 'bg-surface-zebra' : '' }}" data-lot="{{ $r['lot'] }}">
                                <td class="px-sm py-sm font-bold">{{ $r['lot'] }}</td>
                                <td class="px-sm py-sm text-right font-mono" data-total>{{ $r['effectif_total'] }}</td>
                                <td class="px-sm py-sm text-right font-mono text-success-deep" data-matures>{{ $r['matures'] }}</td>
                                <td class="px-sm py-sm text-right font-mono" data-jeunes>{{ $r['jeunes'] }}</td>
                                <td class="px-sm py-sm text-right font-mono {{ $r['morts'] > 0 ? 'text-error-deep' : '' }}" data-morts>{{ $r['morts'] }}</td>
                                <td class="px-sm py-sm text-right font-mono" data-dons>{{ $r['dons'] }}</td>
                                <td class="px-sm py-sm text-center font-mono {{ $r['malades'] > 0 ? 'text-brand-gold' : '' }}" data-malades>{{ $r['malades'] }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($x['recensement'] as $r)
                    <article class="rounded-lg border border-outline-variant p-md text-xs" data-carte-lot="{{ $r['lot'] }}">
                        <p class="font-bold text-brand-navy">{{ $r['lot'] }} — {{ $r['effectif_total'] }} sujets</p>
                        <p>Matures {{ $r['matures'] }} · Jeunes {{ $r['jeunes'] }}</p>
                        <p>Morts {{ $r['morts'] }} · Dons {{ $r['dons'] }} · Malades {{ $r['malades'] }}</p>
                    </article>
                @endforeach
            </div>
        @endif
    </section>

    {{-- Tableau 2 --}}
    <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md" data-bloc="mouvements">
        <h2 class="mb-sm text-section-title font-bold">Tableau 2 — Mouvements, Traitements &amp; Ventes</h2>
        @if (count($x['mouvements']) === 0)
            <p class="text-xs text-outline" data-vide="mouvements">Aucun mouvement d'élevage sur la période sélectionnée.</p>
        @else
            <div class="hidden overflow-x-auto sm:block">
                <table class="w-full text-left text-xs" data-table="mouvements">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-sm py-sm">Lot</th><th class="px-sm py-sm text-right">Qté Vendue</th>
                            <th class="px-sm py-sm text-right">Montant Vente</th><th class="px-sm py-sm text-right">Effectif Final</th>
                            <th class="px-sm py-sm">Traitement Administré</th><th class="px-sm py-sm">Signes Observés</th>
                            <th class="px-sm py-sm text-right">Provende Servie (g/j)</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($x['mouvements'] as $mv)
                            <tr class="border-b border-outline-variant {{ $loop->odd ? 'bg-surface-zebra' : '' }}" data-lot="{{ $mv['lot'] }}">
                                <td class="px-sm py-sm font-bold">{{ $mv['lot'] }}</td>
                                <td class="px-sm py-sm text-right font-mono" data-vendus>{{ $mv['vendus'] }}</td>
                                <td class="px-sm py-sm text-right text-success-deep" data-montant>{{ $m($mv['montant']) }}</td>
                                <td class="px-sm py-sm text-right font-mono" data-effectif-final>{{ $mv['effectif_final'] }}</td>
                                <td class="px-sm py-sm" data-traitement>{{ $mv['traitement'] }}</td>
                                <td class="px-sm py-sm text-outline" data-signes>{{ $mv['signes'] }}</td>
                                <td class="px-sm py-sm text-right font-mono" data-provende>{{ $f::nombre($mv['provende']) }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($x['mouvements'] as $mv)
                    <article class="rounded-lg border border-outline-variant p-md text-xs" data-carte-mouvement="{{ $mv['lot'] }}">
                        <p class="font-bold text-brand-navy">{{ $mv['lot'] }} — effectif final {{ $mv['effectif_final'] }}</p>
                        <p>Vendus {{ $mv['vendus'] }} · {{ $m($mv['montant']) }} FCFA</p>
                        <p>{{ $mv['traitement'] }}</p>
                        <p class="text-outline">{{ $mv['signes'] }}</p>
                        <p>Provende : {{ $f::nombre($mv['provende']) }} g/j</p>
                    </article>
                @endforeach
            </div>
        @endif
    </section>

    {{-- Tableau 3 --}}
    <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md" data-bloc="couvoir">
        <h2 class="mb-sm text-section-title font-bold">Tableau 3 — Couvoir &amp; Suivi d'Incubation</h2>
        @if (count($x['couvoir']) === 0)
            <p class="text-xs text-outline" data-vide="couvoir">Aucun cycle d'incubation enregistré. Ils se créent depuis l'écran Cycle Couveuse.</p>
        @else
            <div class="hidden overflow-x-auto sm:block">
                <table class="w-full text-left text-xs" data-table="couvoir">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-sm py-sm">Code Lot</th><th class="px-sm py-sm">Mise en Couvoir</th>
                            <th class="px-sm py-sm">Éclosion Attendue</th><th class="px-sm py-sm text-right">Œufs Couvés</th>
                            <th class="px-sm py-sm text-right">Nés</th><th class="px-sm py-sm text-right">Taux d'Éclosion</th>
                            <th class="px-sm py-sm text-right">Morts au Démarrage</th><th class="px-sm py-sm text-center">Statut</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($x['couvoir'] as $c)
                            <tr class="border-b border-outline-variant {{ $loop->odd ? 'bg-surface-zebra' : '' }}" data-cycle="{{ $c['code'] }}">
                                <td class="px-sm py-sm font-mono">{{ $c['code'] }}</td>
                                <td class="px-sm py-sm">{{ $d($c['mise']) }}</td>
                                <td class="px-sm py-sm" data-eclosion>{{ $d($c['eclosion']) }}</td>
                                <td class="px-sm py-sm text-right font-mono" data-couves>{{ $c['couves'] }}</td>
                                <td class="px-sm py-sm text-right font-mono" data-nes>{{ $c['nes'] ?? '—' }}</td>
                                <td class="px-sm py-sm text-right font-mono {{ $c['taux'] === null ? 'text-outline' : 'text-success-deep' }}" data-taux>{{ $c['taux'] === null ? '—' : $f::pourcentage($c['taux']) }}</td>
                                <td class="px-sm py-sm text-right font-mono {{ ($c['morts'] ?? 0) > 0 ? 'text-error-deep' : '' }}" data-morts>{{ $c['morts'] ?? '—' }}</td>
                                <td class="px-sm py-sm text-center"><span class="rounded-full px-sm py-xs text-caption font-bold {{ $c['eclos'] ? 'bg-success-container text-success-deep' : 'bg-surface-zebra text-brand-navy' }}" data-statut>{{ $c['statut'] }}</span></td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($x['couvoir'] as $c)
                    <article class="rounded-lg border border-outline-variant p-md text-xs" data-carte-cycle="{{ $c['code'] }}">
                        <p class="font-bold text-brand-navy">{{ $c['code'] }} — {{ $c['statut'] }}</p>
                        <p>Mise en couvoir {{ $d($c['mise']) }} · éclosion attendue {{ $d($c['eclosion']) }}</p>
                        <p>Œufs {{ $c['couves'] }} · Nés {{ $c['nes'] ?? '—' }} · Taux {{ $c['taux'] === null ? '—' : $f::pourcentage($c['taux']) }}</p>
                    </article>
                @endforeach
            </div>
        @endif
    </section>
</div>
