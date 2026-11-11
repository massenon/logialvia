<div data-onglet-actif="creances">
    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 xl:grid-cols-4">
        @include('livewire.rapports._carte', ['kpi' => 'creances-en-cours', 'icone' => 'request_quote', 'libelle' => 'Créances En Cours', 'valeur' => $f::montant($x['en_cours']), 'detail' => 'Toutes créances actives', 'accent' => 'border-error-deep'])
        @include('livewire.rapports._carte', ['kpi' => 'creances-en-retard', 'icone' => 'schedule', 'libelle' => 'Créances en Retard', 'valeur' => $f::montant($x['en_retard']), 'detail' => 'Échéance dépassée', 'accent' => 'border-error-deep'])
        @include('livewire.rapports._carte', ['kpi' => 'clients-debiteurs', 'icone' => 'group', 'libelle' => 'Clients Débiteurs', 'valeur' => (string) $x['clients'], 'detail' => 'Sur la clientèle active', 'accent' => 'border-brand-gold'])
        @include('livewire.rapports._carte', ['kpi' => 'taux-recouvrement', 'icone' => 'percent', 'libelle' => 'Taux de Recouvrement', 'valeur' => $x['taux'] === null ? '—' : $f::pourcentage($x['taux']), 'detail' => 'Acomptes / Montant Initial', 'accent' => 'border-info-blue'])
    </div>

    <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md">
        <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
            <h2 class="text-section-title font-bold">Créances client</h2>
            @include('livewire.rapports._filtre', ['modele' => 'filtreStatutCreance', 'tous' => 'Tous les statuts', 'options' => array_combine(\App\Livewire\Rapports::STATUTS_CREANCE, \App\Livewire\Rapports::STATUTS_CREANCE), 'courant' => $x['statut']])
        </div>
        @if (count($x['lignes']) === 0)
            <p class="text-xs text-outline" data-vide="creances">
                {{ $x['toutes'] === 0 ? 'Aucune créance en cours : toutes les ventes sont intégralement réglées.' : 'Aucune créance ne correspond à ce statut.' }}</p>
        @else
            <div class="hidden overflow-x-auto sm:block">
                <table class="w-full text-left text-xs" data-table="creances">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-sm py-sm">Code</th><th class="px-sm py-sm">Client</th><th class="px-sm py-sm">N° Facture</th>
                            <th class="px-sm py-sm">Date Vente</th><th class="px-sm py-sm">Échéance</th>
                            <th class="px-sm py-sm text-right">Montant Initial</th><th class="px-sm py-sm text-right">Acomptes</th>
                            <th class="px-sm py-sm text-right">Solde Dû</th><th class="px-sm py-sm text-center">Retard</th>
                            <th class="px-sm py-sm text-center">Statut</th><th class="px-sm py-sm text-right">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($x['lignes'] as $l)
                            <tr class="border-b border-outline-variant {{ $loop->odd ? 'bg-surface-zebra' : '' }}" data-facture="{{ $l['facture'] }}">
                                <td class="px-sm py-sm font-mono" data-code>{{ $l['code'] }}</td>
                                <td class="px-sm py-sm font-bold">{{ $l['client'] }}</td>
                                <td class="px-sm py-sm font-mono">{{ $l['facture'] }}</td>
                                <td class="px-sm py-sm">{{ $d($l['date_vente']) }}</td>
                                <td class="px-sm py-sm" data-echeance>{{ $d($l['echeance']) }}</td>
                                <td class="px-sm py-sm text-right" data-initial>{{ $m($l['initial']) }}</td>
                                <td class="px-sm py-sm text-right" data-acomptes>{{ $m($l['acomptes']) }}</td>
                                <td class="px-sm py-sm text-right font-bold text-error-deep" data-solde>{{ $m($l['solde']) }}</td>
                                <td class="px-sm py-sm text-center {{ $l['en_retard'] ? 'font-bold text-error-deep' : 'text-outline' }}" data-retard>{{ $l['en_retard'] ? $l['retard'].'j' : '—' }}</td>
                                <td class="px-sm py-sm text-center"><span class="rounded-full px-sm py-xs text-caption font-bold {{ $l['en_retard'] ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-brand-navy' }}" data-statut>{{ $l['statut'] }}</span></td>
                                <td class="px-sm py-sm text-right">
                                    @if ($peutVoirClients)
                                        <a wire:navigate.hover href="/clients" class="text-info-blue hover:underline" data-action="encaissement">Saisir l'encaissement</a>
                                    @endif
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($x['lignes'] as $l)
                    <article class="rounded-lg border border-outline-variant p-md text-xs" data-carte-facture="{{ $l['facture'] }}">
                        <p class="font-bold text-brand-navy">{{ $l['client'] }} <span class="font-mono font-normal text-outline">{{ $l['code'] }}</span></p>
                        <p class="text-outline">{{ $l['facture'] }} · vente du {{ $d($l['date_vente']) }} · échéance {{ $d($l['echeance']) }}</p>
                        <p>Initial {{ $m($l['initial']) }} · Acomptes {{ $m($l['acomptes']) }}</p>
                        <p class="font-bold text-error-deep">Solde dû : {{ $m($l['solde']) }}</p>
                        <p><span class="rounded-full px-sm py-xs text-caption font-bold {{ $l['en_retard'] ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-brand-navy' }}">{{ $l['statut'] }}</span>
                            @if ($l['en_retard']) <span class="font-bold text-error-deep">{{ $l['retard'] }}j de retard</span> @endif</p>
                        @if ($peutVoirClients)
                            <a wire:navigate.hover href="/clients" class="text-info-blue hover:underline">Saisir l'encaissement</a>
                        @endif
                    </article>
                @endforeach
            </div>
            <p class="mt-sm border-t border-outline-variant pt-sm text-caption text-outline" data-note="echeance">
                « Sans échéance » : aucun délai de paiement n'a été convenu sur cette vente ; elle n'est jamais déclarée en retard. Le retard se compte en jours
                civils entre l'échéance convenue et aujourd'hui.</p>
        @endif
    </section>
</div>
