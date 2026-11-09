<div>
    <h1 class="mb-md text-page-title font-bold">Ventes</h1>

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        <div class="rounded-lg border-l-4 border-brand-navy bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">CA du Jour</p>
            <p class="text-page-title font-bold" data-kpi="ca">{{ number_format($chiffreAffaires, 0, ',', ' ') }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border-l-4 border-info-blue bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Panier Moyen</p>
            {{-- « — » et non « 0 » : une moyenne sur zéro vente n'existe pas (Dart). --}}
            <p class="text-page-title font-bold"><span data-kpi="panier">{{ $panierMoyen === null ? '—' : number_format($panierMoyen, 0, ',', ' ') }}</span> <span class="text-xs font-normal">{{ $panierMoyen === null ? '' : 'FCFA' }}</span></p>
            <p class="text-caption text-outline">{{ $panierMoyen === null ? 'Aucune vente aujourd\'hui' : '' }}</p>
        </div>
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Ventes en Attente (Avance)</p>
            <p class="text-page-title font-bold" data-kpi="attente">{{ $enAttente }}</p>
        </div>
    </div>

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="ventes">
        Sur le web, l'historique des ventes est en consultation. L'enregistrement d'une vente (caisse), les devis de prestations,
        l'annulation, les retours et avoirs, et l'export PDF restent sur le poste, là où le stock et la comptabilité sont tenus.
    </p>

    <div class="mb-md border-b border-outline-variant">
        <span class="inline-block border-b-2 border-brand-navy px-md py-sm text-xs font-bold text-brand-navy">Historique des Ventes</span>
    </div>

    <div class="mb-sm flex flex-wrap items-center gap-sm">
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Référence ou client…" aria-label="Rechercher une vente"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-xs">
        <select wire:model.live="statut" aria-label="Filtrer par statut"
                class="rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs">
            <option value="">Tous statuts</option>
            @foreach ($statuts as $s)
                <option value="{{ $s }}">{{ $s }}</option>
            @endforeach
        </select>
    </div>

    @php
        $badge = fn (string $s) => match ($s) {
            'Payée' => 'bg-success-container text-success-deep',
            'Avance' => 'bg-surface-zebra text-brand-navy',
            default => 'bg-error-container text-error-deep',
        };
    @endphp

    <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs" data-table="historique">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Référence</th>
                    <th class="px-md py-sm">Date</th>
                    <th class="px-md py-sm">Client</th>
                    <th class="px-md py-sm text-right">Montant</th>
                    <th class="px-md py-sm text-center">Statut</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($ventes as $v)
                    <tr class="cursor-pointer {{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-vente="{{ $v->reference }}" wire:click="ouvrir('{{ $v->id }}')">
                        <td class="px-md py-sm font-bold text-brand-navy">{{ $v->reference }}</td>
                        <td class="px-md py-sm">{{ $v->date_vente->timezone($fuseau)->format('d/m/Y') }}</td>
                        <td class="px-md py-sm">{{ $v->client }}</td>
                        <td class="px-md py-sm text-right">{{ number_format($v->total, 0, ',', ' ') }}</td>
                        <td class="px-md py-sm text-center"><span class="rounded-full px-sm py-xs font-bold {{ $badge($v->status) }}">{{ $v->status }}</span></td>
                    </tr>
                @empty
                    <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucune vente ne correspond. Les ventes encaissées depuis le poste apparaissent ici.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>
    <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($ventes as $v)
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-vente="{{ $v->reference }}" wire:click="ouvrir('{{ $v->id }}')">
                <div class="flex items-center justify-between gap-sm">
                    <p class="font-bold text-brand-navy">{{ $v->reference }}</p>
                    <span class="rounded-full px-sm py-xs text-caption font-bold {{ $badge($v->status) }}">{{ $v->status }}</span>
                </div>
                <p class="text-caption text-outline">{{ $v->date_vente->timezone($fuseau)->format('d/m/Y') }} · {{ $v->client }}</p>
                <p class="font-bold">{{ number_format($v->total, 0, ',', ' ') }} F</p>
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucune vente ne correspond.</p>
        @endforelse
    </div>

    @if ($ouverte)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-vente">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl" data-detail="{{ $ouverte->reference }}">
                <h2 id="titre-vente" class="mb-md text-modal-title font-bold">Vente {{ $ouverte->reference }}</h2>
                @php
                    $details = [
                        'Client' => $ouverte->client,
                        'Date' => $ouverte->date_vente->timezone($fuseau)->format('d/m/Y'),
                        'Mode de règlement' => $ouverte->mode,
                    ];
                    if ($ouverte->ligne_mobile_money !== null) { $details['Ligne créditée'] = $ouverte->ligne_mobile_money; }
                    $details['Condition de paiement'] = $ouverte->status === 'Avance' ? 'Avance (Solde Restant Dû)' : 'Comptant';
                    $details['Statut'] = $ouverte->status;
                    if ($ouverte->status === 'Avance') { $details['Reste dû'] = number_format(max(0, $ouverte->total - $ouverte->paye), 0, ',', ' ').' FCFA'; }
                    if ($ouverte->motif_annulation !== null) { $details['Motif d\'annulation'] = $ouverte->motif_annulation; }
                @endphp
                <dl class="mb-sm text-xs">
                    @foreach ($details as $libelle => $valeur)
                        <div class="mb-xs flex gap-sm"><dt class="w-40 shrink-0 text-outline">{{ $libelle }}</dt><dd class="font-semibold">{{ $valeur }}</dd></div>
                    @endforeach
                </dl>
                <hr class="my-sm border-outline-variant">
                <p class="mb-xs text-caption font-bold uppercase text-outline">Lignes</p>
                <ul class="mb-sm text-xs" data-lignes>
                    @foreach ($ouverte->lignes as $l)
                        <li class="mb-xs flex justify-between gap-sm"><span>{{ $l->name }} × {{ (int) $l->qte }}</span><span>{{ number_format($l->qte * $l->pu, 0, ',', ' ') }}</span></li>
                    @endforeach
                </ul>
                <hr class="my-sm border-outline-variant">
                <div class="flex items-center justify-between">
                    <span class="text-caption font-bold uppercase text-outline">Total</span>
                    <span class="text-section-title font-bold text-brand-navy">{{ number_format($ouverte->total, 0, ',', ' ') }} FCFA</span>
                </div>
                <p class="mt-sm text-caption text-outline">L'impression de la facture se fait sur le poste.</p>
                <div class="mt-md flex justify-end">
                    <button type="button" wire:click="fermer" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Fermer</button>
                </div>
            </div>
        </div>
    @endif
</div>
