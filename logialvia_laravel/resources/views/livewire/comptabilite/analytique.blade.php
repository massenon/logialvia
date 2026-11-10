<div>
    @php($f = \App\Support\FormatComptable::class)
    @include('livewire.comptabilite._entete')

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="lecture-seule">
        Lecture seule : somme des écritures de tous les postes. Export : XLSX (bouton « Exporter ») et vue imprimable (« Imprimer / PDF ») ; le PDF généré du poste n'est pas reproduit.
    </p>

    <h2 class="mb-sm text-section-title font-bold">Marges par centre de profit</h2>
    @if (count($centres) === 0)
        <p class="mb-lg rounded-lg bg-surface-card p-lg text-center text-xs text-outline" data-vide>
            Aucun produit ni charge d'exploitation sur l'exercice {{ $annee }}. Les marges apparaîtront dès la première vente enregistrée.</p>
    @else
        <div class="mb-sm hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs" data-table="analytique">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Centre de coût / profit</th>
                        <th class="px-md py-sm text-right">Revenus</th>
                        <th class="px-md py-sm text-right">Coûts directs</th>
                        <th class="px-md py-sm text-right">Marge</th>
                        <th class="px-md py-sm text-right">Taux de marge</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach ($centres as $c)
                        @php($m = $c['revenus'] - $c['couts'])
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-centre="{{ $c['nom'] }}">
                            <td class="px-md py-sm"><span class="font-bold text-brand-navy">{{ $c['nom'] }}</span><br><span class="text-caption text-outline">{{ $c['detail'] }}</span></td>
                            <td class="px-md py-sm text-right">{{ $f::ouTiret($c['revenus']) }}</td>
                            <td class="px-md py-sm text-right">{{ $f::ouTiret($c['couts']) }}</td>
                            <td class="px-md py-sm text-right font-bold {{ $m < 0 ? 'text-error-deep' : '' }}" data-marge>{{ $f::ouTiret($m) }}</td>
                            <td class="px-md py-sm text-right" data-taux>{{ abs($c['revenus']) < 0.01 ? '—' : $f::pourcentage($m / $c['revenus'] * 100) }}</td>
                        </tr>
                    @endforeach
                </tbody>
                <tfoot class="bg-brand-gold/10">
                    <tr data-total>
                        <td class="px-md py-sm font-bold">TOTAL</td>
                        <td class="px-md py-sm text-right font-bold">{{ $f::ouTiret($totalRevenus) }}</td>
                        <td class="px-md py-sm text-right font-bold">{{ $f::ouTiret($totalCouts) }}</td>
                        <td class="px-md py-sm text-right font-bold" data-total-marge>{{ $f::ouTiret($totalMarge) }}</td>
                        <td class="px-md py-sm text-right font-bold">{{ $tauxTotal === null ? '—' : $f::pourcentage($tauxTotal) }}</td>
                    </tr>
                </tfoot>
            </table>
        </div>

        <div class="mb-sm flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @foreach ($centres as $c)
                @php($m = $c['revenus'] - $c['couts'])
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-centre="{{ $c['nom'] }}">
                    <p class="font-bold text-brand-navy">{{ $c['nom'] }}</p>
                    <p class="text-caption text-outline">{{ $c['detail'] }}</p>
                    <p class="text-xs">Revenus {{ $f::ouTiret($c['revenus']) }} · Coûts {{ $f::ouTiret($c['couts']) }}</p>
                    <p class="text-xs font-bold">Marge {{ $f::ouTiret($m) }}</p>
                </article>
            @endforeach
        </div>

        @if (abs($chargesNonAffectees) >= 0.01)
            <p class="mb-lg text-xs text-outline" data-charges-non-affectees>
                Charges de structure non affectées à un centre : {{ $f::montant($chargesNonAffectees) }} (locations, assurances, transports,
                charges diverses). Elles pèsent sur le résultat net mais ne sont pas réparties arbitrairement entre les activités.</p>
        @endif
    @endif

    <h2 class="mb-sm mt-lg text-section-title font-bold">Comparaison Visuelle des Marges</h2>
    @if (abs($totalRevenus) < 0.01)
        <p class="rounded-lg bg-surface-card p-lg text-center text-xs text-outline" data-vide="graphique">Le graphique apparaîtra dès qu'un revenu sera enregistré.</p>
    @else
        <div class="rounded-lg border border-outline-variant bg-surface-card p-md" data-graphique>
            @foreach ($centres as $c)
                @php($m = $c['revenus'] - $c['couts'])
                @php($ratio = $revenuMaximum < 0.01 ? 0.0 : max(0.0, min(1.0, $c['revenus'] / $revenuMaximum)))
                @php($ratioMarge = abs($c['revenus']) < 0.01 ? 0.0 : max(0.0, min(1.0, $m / $c['revenus'])) * $ratio)
                <div class="mb-md" data-barre="{{ $c['nom'] }}">
                    <div class="flex flex-wrap justify-between gap-sm text-xs">
                        <span class="font-bold">{{ $c['nom'] }}</span>
                        <span class="text-outline">{{ $f::montant($m) }} de marge sur {{ $f::montant($c['revenus']) }}</span>
                    </div>
                    <div class="mt-xs h-3 overflow-hidden rounded-full bg-surface-zebra">
                        <div class="relative h-3">
                            <div class="absolute inset-y-0 left-0 bg-brand-gold-light" style="width: {{ round($ratio * 100, 1) }}%"></div>
                            <div class="absolute inset-y-0 left-0 bg-brand-navy" style="width: {{ round($ratioMarge * 100, 1) }}%"></div>
                        </div>
                    </div>
                </div>
            @endforeach
        </div>
    @endif
</div>
