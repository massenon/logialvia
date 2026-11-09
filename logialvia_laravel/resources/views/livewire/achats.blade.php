<div>
    @php
        $nombre = fn ($v) => number_format($v, 0, ',', ' ');
        $quantite = fn ($v) => rtrim(rtrim(number_format($v, 2, ',', ' '), '0'), ',');
        $fuseau = config('logialvia.fuseau');
    @endphp

    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <h1 class="text-page-title font-bold">Achats &amp; Commandes</h1>
    </div>

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="lecture-seule">
        Consultation seule. La commande d'achat, la réception (entrée en stock, PMP) et le règlement d'une dette
        s'enregistrent sur le poste : le stock et le PMP lui sont propres.
    </p>

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Commandes en Cours</p>
            <p class="text-page-title font-bold" data-kpi="en-cours">{{ $enCours }}</p>
        </div>
        <div class="rounded-lg border-l-4 border-brand-navy bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Montant Total Engagé</p>
            <p class="text-page-title font-bold" data-kpi="engage">{{ $nombre($engage) }} <span class="text-xs font-normal">FCFA</span></p>
            <p class="text-caption text-outline">Commandes non encore réceptionnées</p>
        </div>
        <div class="rounded-lg border-l-4 border-success-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Achats Cumulés (Mois)</p>
            <p class="text-page-title font-bold" data-kpi="mois">{{ $nombre($achatsDuMois) }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
    </div>

    <h2 class="mb-sm text-section-title font-bold">Commandes</h2>
    <div class="mb-sm flex flex-wrap gap-sm">
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Référence ou fournisseur…" aria-label="Rechercher un achat"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">
        <select wire:model.live="statut" aria-label="Filtrer par statut"
                class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
            <option value="">Tous les statuts</option>
            @foreach ($statuts as $s)
                <option value="{{ $s }}">{{ $s }}</option>
            @endforeach
        </select>
    </div>

    <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs" data-table="achats">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Référence</th>
                    <th class="px-md py-sm">Date</th>
                    <th class="px-md py-sm">Fournisseur</th>
                    <th class="px-md py-sm">Mode</th>
                    <th class="px-md py-sm text-center">Statut</th>
                    <th class="px-md py-sm text-right">Montant</th>
                    <th class="px-md py-sm text-right">Payé</th>
                    <th class="px-md py-sm text-right">Solde Dû</th>
                    <th class="px-md py-sm text-center">Ancienneté</th>
                    <th class="px-md py-sm text-right">Détail</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($achats as $a)
                    @php
                        $solde = $a->statut === 'Annulé' ? 0 : max(0, $a->total - $a->paye);
                        $jours = max(0, (int) $a->date_achat->diffInDays($maintenant, true));
                    @endphp
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-achat="{{ $a->reference }}">
                        <td class="px-md py-sm font-bold font-mono text-brand-navy">{{ $a->reference }}</td>
                        <td class="px-md py-sm">{{ $a->date_achat->timezone($fuseau)->format('d/m/Y') }}</td>
                        <td class="px-md py-sm">{{ $noms[$a->fournisseur_id] ?? '—' }}</td>
                        <td class="px-md py-sm">{{ $a->mode ?: '—' }}</td>
                        <td class="px-md py-sm text-center">
                            <span class="rounded-full px-sm py-xs font-semibold {{ $a->statut === 'Livré' ? 'bg-success-container text-success-deep' : 'bg-brand-gold/20 text-brand-navy' }}" data-statut>{{ $a->statut }}</span>
                        </td>
                        <td class="px-md py-sm text-right">{{ $nombre($a->total) }}</td>
                        <td class="px-md py-sm text-right">{{ $nombre($a->paye) }}</td>
                        <td class="px-md py-sm text-right {{ $solde > 0 ? 'font-bold text-error-deep' : 'text-outline' }}" data-solde>
                            {{ $solde > 0 ? $nombre($solde).' F' : 'Soldée' }}</td>
                        <td class="px-md py-sm text-center">
                            @if ($solde > 0)
                                <span class="rounded-full px-sm py-xs font-semibold {{ $jours > 10 ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-outline' }}">{{ $jours }} j</span>
                            @else
                                <span class="text-outline">—</span>
                            @endif
                        </td>
                        <td class="px-md py-sm text-right">
                            <button type="button" wire:click="basculer('{{ $a->id }}')" aria-expanded="{{ $detail?->id === $a->id ? 'true' : 'false' }}"
                                    class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">
                                {{ $detail?->id === $a->id ? 'Masquer' : 'Lignes' }}</button>
                        </td>
                    </tr>
                    @if ($detail?->id === $a->id)
                        <tr data-lignes-de="{{ $a->reference }}">
                            <td colspan="10" class="bg-surface-zebra px-md py-sm">
                                <table class="w-full text-left text-xs">
                                    <thead class="text-caption uppercase text-outline">
                                        <tr>
                                            <th class="py-xs">Intrant</th>
                                            <th class="py-xs text-right">Quantité</th>
                                            <th class="py-xs text-right">Prix Unitaire</th>
                                            <th class="py-xs text-right">Total</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        @foreach ($detail->lignes as $l)
                                            <tr data-ligne="{{ $l->intrant_code }}">
                                                <td class="py-xs"><span class="font-bold">{{ $l->nom }}</span> <span class="font-mono text-caption text-outline">{{ $l->intrant_code }}</span></td>
                                                <td class="py-xs text-right">{{ $quantite($l->qte) }}</td>
                                                <td class="py-xs text-right">{{ $nombre($l->pu_achat) }} F</td>
                                                <td class="py-xs text-right font-bold">{{ $nombre($l->qte * $l->pu_achat) }} F</td>
                                            </tr>
                                        @endforeach
                                    </tbody>
                                </table>
                            </td>
                        </tr>
                    @endif
                @empty
                    <tr><td colspan="10" class="px-md py-lg text-center text-outline">
                        {{ $aucunAchat ? 'Aucune commande enregistrée. Les commandes se composent sur le poste.' : 'Aucun achat ne correspond.' }}</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($achats as $a)
            @php
                $solde = $a->statut === 'Annulé' ? 0 : max(0, $a->total - $a->paye);
                $jours = max(0, (int) $a->date_achat->diffInDays($maintenant, true));
            @endphp
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-achat="{{ $a->reference }}">
                <div class="flex items-center justify-between gap-sm">
                    <p class="font-mono font-bold text-brand-navy">{{ $a->reference }}</p>
                    <span class="rounded-full px-sm py-xs text-caption font-semibold {{ $a->statut === 'Livré' ? 'bg-success-container text-success-deep' : 'bg-brand-gold/20 text-brand-navy' }}">{{ $a->statut }}</span>
                </div>
                <p class="text-caption text-outline">{{ $a->date_achat->timezone($fuseau)->format('d/m/Y') }} · {{ $noms[$a->fournisseur_id] ?? '—' }} · {{ $a->mode ?: '—' }}</p>
                <p class="text-xs">Montant {{ $nombre($a->total) }} F · Payé {{ $nombre($a->paye) }} F</p>
                <p class="text-xs font-bold {{ $solde > 0 ? 'text-error-deep' : 'text-outline' }}">
                    {{ $solde > 0 ? 'Reste '.$nombre($solde).' F ('.$jours.' j)' : 'Soldée' }}</p>
                <button type="button" wire:click="basculer('{{ $a->id }}')"
                        class="mt-sm w-full rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">
                    {{ $detail?->id === $a->id ? 'Masquer les lignes' : 'Voir les lignes' }}</button>
                @if ($detail?->id === $a->id)
                    <ul class="mt-sm text-xs" data-lignes-carte="{{ $a->reference }}">
                        @foreach ($detail->lignes as $l)
                            <li class="flex justify-between gap-sm border-t border-outline-variant py-xs">
                                <span>{{ $l->nom }} · {{ $quantite($l->qte) }} × {{ $nombre($l->pu_achat) }} F</span>
                                <span class="font-bold">{{ $nombre($l->qte * $l->pu_achat) }} F</span>
                            </li>
                        @endforeach
                    </ul>
                @endif
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">
                {{ $aucunAchat ? 'Aucune commande enregistrée. Les commandes se composent sur le poste.' : 'Aucun achat ne correspond.' }}</p>
        @endforelse
    </div>
</div>
