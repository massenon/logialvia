<div data-onglet-actif="dettes">
    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        @include('livewire.rapports._carte', ['kpi' => 'total-dettes', 'icone' => 'local_shipping', 'libelle' => 'Total Dettes Fournisseurs', 'valeur' => $f::montant($x['total']), 'detail' => 'Toutes dettes actives', 'accent' => 'border-error-deep'])
        @include('livewire.rapports._carte', ['kpi' => 'dettes-urgentes', 'icone' => 'priority_high', 'libelle' => 'Dettes Urgentes', 'valeur' => $f::montant($x['urgentes']), 'detail' => 'Échéance dépassée', 'accent' => 'border-brand-gold'])
        @include('livewire.rapports._carte', ['kpi' => 'fournisseurs-crediteurs', 'icone' => 'store', 'libelle' => 'Fournisseurs Créditeurs', 'valeur' => (string) $x['fournisseurs'], 'detail' => 'Sur la base fournisseurs', 'accent' => 'border-info-blue'])
    </div>

    <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md">
        <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
            <h2 class="text-section-title font-bold">Dettes fournisseurs</h2>
            @include('livewire.rapports._filtre', ['modele' => 'filtreStatutDette', 'tous' => 'Tous les statuts', 'options' => array_combine(\App\Livewire\Rapports::STATUTS_DETTE, \App\Livewire\Rapports::STATUTS_DETTE), 'courant' => $x['statut']])
        </div>
        @if (count($x['lignes']) === 0)
            <p class="text-xs text-outline" data-vide="dettes">
                {{ $x['toutes'] === 0 ? 'Aucune dette fournisseur : tous les achats sont intégralement réglés.' : 'Aucune dette ne correspond à ce statut.' }}</p>
        @else
            <div class="hidden overflow-x-auto sm:block">
                <table class="w-full text-left text-xs" data-table="dettes">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-sm py-sm">Code</th><th class="px-sm py-sm">Fournisseur</th><th class="px-sm py-sm">N° Bon/Facture</th>
                            <th class="px-sm py-sm">Date Achat</th><th class="px-sm py-sm">Échéance</th>
                            <th class="px-sm py-sm text-right">Montant Total</th><th class="px-sm py-sm text-right">Réglé</th>
                            <th class="px-sm py-sm text-right">Solde Restant</th><th class="px-sm py-sm text-center">Statut</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($x['lignes'] as $l)
                            <tr class="border-b border-outline-variant {{ $loop->odd ? 'bg-surface-zebra' : '' }}" data-reference="{{ $l['reference'] }}">
                                <td class="px-sm py-sm font-mono" data-code>{{ $l['code'] }}</td>
                                <td class="px-sm py-sm font-bold">{{ $l['fournisseur'] }}</td>
                                <td class="px-sm py-sm font-mono">{{ $l['reference'] }}</td>
                                <td class="px-sm py-sm">{{ $d($l['date_achat']) }}</td>
                                <td class="px-sm py-sm" data-echeance>{{ $d($l['echeance']) }}</td>
                                <td class="px-sm py-sm text-right" data-total>{{ $m($l['total']) }}</td>
                                <td class="px-sm py-sm text-right" data-regle>{{ $m($l['regle']) }}</td>
                                <td class="px-sm py-sm text-right font-bold text-error-deep" data-solde>{{ $m($l['solde']) }}</td>
                                <td class="px-sm py-sm text-center"><span class="rounded-full px-sm py-xs text-caption font-bold {{ $l['urgente'] ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-brand-navy' }}" data-statut>{{ $l['statut'] }}</span></td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($x['lignes'] as $l)
                    <article class="rounded-lg border border-outline-variant p-md text-xs" data-carte-reference="{{ $l['reference'] }}">
                        <p class="font-bold text-brand-navy">{{ $l['fournisseur'] }} <span class="font-mono font-normal text-outline">{{ $l['code'] }}</span></p>
                        <p class="text-outline">{{ $l['reference'] }} · achat du {{ $d($l['date_achat']) }} · échéance {{ $d($l['echeance']) }}</p>
                        <p>Total {{ $m($l['total']) }} · Réglé {{ $m($l['regle']) }}</p>
                        <p class="font-bold text-error-deep">Solde restant : {{ $m($l['solde']) }}</p>
                        <p><span class="rounded-full px-sm py-xs text-caption font-bold {{ $l['urgente'] ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-brand-navy' }}">{{ $l['statut'] }}</span></p>
                    </article>
                @endforeach
            </div>
            <p class="mt-sm border-t border-outline-variant pt-sm text-caption text-outline" data-note="echeance">
                « Sans échéance » : aucun délai n'a été convenu sur cet achat ; il n'est jamais déclaré urgent.</p>
        @endif
    </section>
</div>
