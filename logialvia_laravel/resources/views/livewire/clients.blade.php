<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <div><h1 class="flex items-center gap-xs text-page-title font-bold text-brand-navy"><x-icone nom="payments" class="text-[24px]" />Clients et Créances</h1><p class="mt-xs text-xs text-outline">Fiches clients, suivi des soldes restant dus, relances commerciales et fidélisation.</p></div>
        @if ($peutGerer)
            <button type="button" wire:click="nouveau"
                    class="rounded-full bg-brand-navy px-md py-sm text-xs font-bold text-white shadow-sm hover:bg-brand-navy-dark">
                Ajouter un Client
            </button>
        @endif
    </div>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Clients Enregistrés</span><x-icone nom="group" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="clients">{{ $nombre }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-error-deep bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Solde Total Restant Dû</span><x-icone nom="request_quote" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="solde">{{ number_format($soldeTotal, 0, ',', ' ') }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Soldes Anciens (&gt;10j)</span><x-icone nom="schedule" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="anciens">{{ $anciens }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-info-blue bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Événements CRM (7j)</span><x-icone nom="celebration" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="crm">{{ $evenements->count() }}</p>
        </div>
    </div>

    <div x-data="{ o: 'liste' }">
    <div class="mb-md flex items-center gap-xs overflow-x-auto border-b border-outline-variant" role="tablist">
        @foreach (['liste' => ['Liste des Clients', null], 'dettes' => ['Suivi des Soldes', null], 'crm' => ['Gestion des Relances CRM', 'celebration']] as $cle => [$lib, $ico])
            <button type="button" role="tab" data-onglet-client="{{ $cle }}" x-on:click="o = '{{ $cle }}'" x-bind:aria-selected="o === '{{ $cle }}' ? 'true' : 'false'"
                    x-bind:class="o === '{{ $cle }}' ? 'border-brand-navy text-brand-navy' : 'border-transparent text-outline'"
                    class="flex items-center gap-1 whitespace-nowrap border-b-2 px-md py-2.5 text-xs font-bold">@if ($ico)<x-icone :nom="$ico" class="text-[16px]" />@endif{{ $lib }}</button>
        @endforeach
    </div>
    <div x-show="o === 'liste'" data-panneau-client="liste">
    <h2 class="sr-only">Clients</h2>
    <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Nom ou téléphone…" aria-label="Rechercher un client"
           class="mb-sm w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">

    <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Nom</th>
                    <th class="px-md py-sm">Téléphone</th>
                    <th class="px-md py-sm">Date de Naissance</th>
                    <th class="px-md py-sm text-right">Total Achats</th>
                    <th class="px-md py-sm text-right">Solde Actuel</th>
                    @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                </tr>
            </thead>
            <tbody>
                @forelse ($clients as $c)
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-client="{{ $c->nom }}">
                        <td class="px-md py-sm font-bold">{{ $c->nom }}</td>
                        <td class="px-md py-sm">{{ $c->telephone ?: '—' }}</td>
                        <td class="px-md py-sm">{{ $c->date_naissance?->format('d/m/Y') ?? '—' }}</td>
                        <td class="px-md py-sm text-right">{{ number_format($totauxAchats[$c->id] ?? 0, 0, ',', ' ') }}</td>
                        <td class="px-md py-sm text-right {{ $c->solde_creance > 0 ? 'font-bold text-error-deep' : 'font-bold text-success-deep' }}">
                            {{ number_format($c->solde_creance, 0, ',', ' ') }} F</td>
                        @if ($peutGerer)
                            <td class="px-md py-sm text-right">
                                <button type="button" wire:click="modifier('{{ $c->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier</button>
                                <button type="button" wire:click="demanderSuppression('{{ $c->id }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer</button>
                            </td>
                        @endif
                    </tr>
                @empty
                    <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun client ne correspond.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>
    <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($clients as $c)
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-client="{{ $c->nom }}">
                <p class="font-bold">{{ $c->nom }}</p>
                <p class="text-caption text-outline">{{ $c->telephone ?: '—' }} · {{ $c->date_naissance?->format('d/m/Y') ?? '—' }}</p>
                <p class="font-bold {{ $c->solde_creance > 0 ? 'text-error-deep' : '' }}">{{ number_format($c->solde_creance, 0, ',', ' ') }} F</p>
                @if ($peutGerer)
                    <div class="mt-sm flex gap-sm">
                        <button type="button" wire:click="modifier('{{ $c->id }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Modifier</button>
                        <button type="button" wire:click="demanderSuppression('{{ $c->id }}')" class="flex-1 rounded-lg border border-error-deep px-sm py-sm text-xs font-semibold text-error-deep">Supprimer</button>
                    </div>
                @endif
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun client ne correspond.</p>
        @endforelse
    </div>

    </div>
    <div x-show="o === 'dettes'" x-cloak data-panneau-client="dettes">
    <h2 class="sr-only">Créances Ouvertes</h2>
    <div class="mb-sm flex flex-wrap items-center gap-sm">
        <p class="text-xs text-outline">Le recouvrement (total ou partiel) passe l'écriture Trésorerie / Clients et recalcule le solde du client.</p>
        @if ($peutExporter)
            <button type="button" wire:click="exporterCreances" data-action="exporter-creances" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Exporter (XLSX)</button>
            <a href="{{ route('clients.creances.imprimer') }}" target="_blank" data-lien="imprimer-creances" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Imprimer / PDF</a>
        @endif
    </div>
    <div class="mb-lg overflow-x-auto rounded-lg border border-outline-variant bg-surface-card">
        <table class="w-full text-left text-xs" data-table="creances">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Client</th>
                    <th class="px-md py-sm">Référence Vente</th>
                    <th class="px-md py-sm text-right">Montant Total</th>
                    <th class="px-md py-sm text-right">Déjà Réglé</th>
                    <th class="px-md py-sm text-right">Solde Restant Dû</th>
                    <th class="px-md py-sm text-center">Ancienneté</th>
                    <th class="px-md py-sm text-right">Actions</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($creances as $v)
                    @php($jours = (int) $v->date_vente->diffInDays($maintenant, true))
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-creance="{{ $v->reference }}">
                        <td class="px-md py-sm font-bold">{{ $v->client }}</td>
                        <td class="px-md py-sm font-mono">{{ $v->reference }}</td>
                        <td class="px-md py-sm text-right">{{ number_format($v->total, 0, ',', ' ') }} F</td>
                        <td class="px-md py-sm text-right">{{ number_format($v->paye, 0, ',', ' ') }} F</td>
                        <td class="px-md py-sm text-right font-bold text-error-deep">{{ number_format($v->total - $v->paye, 0, ',', ' ') }} F</td>
                        <td class="px-md py-sm text-center">
                            <span class="rounded-full px-sm py-xs font-semibold {{ $jours > 10 ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-outline' }}">{{ $jours }} j</span>
                        </td>
                        <td class="px-md py-sm text-right">
                            @if ($peutGerer)
                                <button type="button" wire:click="demanderRecouvrement('{{ $v->id }}')" data-action="recouvrer" class="font-semibold text-brand-navy">Enregistrer un Paiement</button>
                            @endif
                            <a href="{{ route('clients.relance', $v->id) }}" target="_blank" data-lien="relance" class="font-semibold text-outline underline">{{ $v->echeance === null ? 'Rappel de solde' : 'Lettre de relance' }}</a>
                        </td>
                    </tr>
                @empty
                    <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucune créance ouverte.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    </div>
    <div x-show="o === 'crm'" x-cloak data-panneau-client="crm">
    <h2 class="sr-only">Événements CRM à Venir</h2>
    <div class="overflow-x-auto rounded-lg border border-outline-variant bg-surface-card">
        <table class="w-full text-left text-xs" data-table="crm">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Client</th>
                    <th class="px-md py-sm">Type d'Événement</th>
                    <th class="px-md py-sm">Date</th>
                    <th class="px-md py-sm text-center">Jours Restants</th>
                    <th class="px-md py-sm">Dernier Contact</th>
                    <th class="px-md py-sm text-right">Action</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($evenements as $e)
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}">
                        <td class="px-md py-sm font-bold">{{ $e['client']->nom }}</td>
                        <td class="px-md py-sm"><span class="inline-flex items-center gap-xs rounded-full bg-brand-gold/20 px-sm py-0.5 text-caption font-bold text-brand-navy"><x-icone nom="cake" class="text-[15px]" />Anniversaire</span></td>
                        <td class="px-md py-sm">{{ $e['date']->format('d/m/Y') }}</td>
                        @php($restants = (int) $maintenant->startOfDay()->diffInDays($e['date'], true))
                        <td class="px-md py-sm text-center font-bold {{ $restants <= 1 ? 'text-error-deep' : 'text-brand-navy' }}">{{ $restants }} jour{{ $restants > 1 ? 's' : '' }}</td>
                        <td class="px-md py-sm">{{ $e['client']->dernier_contact?->timezone(config('logialvia.fuseau'))->format('d/m/Y') ?? 'Jamais contacté' }}</td>
                        @php($chiffres = preg_replace('/\D+/', '', (string) $e['client']->telephone))
                        <td class="px-md py-sm text-right">
                            @if ($chiffres !== '')
                                <a href="https://wa.me/{{ $chiffres }}?text={{ rawurlencode('Joyeux anniversaire '.$e['client']->nom.' !') }}" target="_blank" rel="noopener" data-lien="voeux"
                                   class="inline-flex items-center gap-xs rounded-full bg-success-deep px-sm py-1.5 text-caption font-bold text-white"><x-icone nom="chat" class="text-[15px]" />Envoyer les Vœux</a>
                            @else
                                <span class="text-outline">Sans téléphone</span>
                            @endif
                        </td>
                    </tr>
                @empty
                    <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun événement dans les 7 prochains jours.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    </div>
    </div>

    @if ($formulaire)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-client">
            <form wire:submit="enregistrer" class="w-full max-w-sm rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-client" class="mb-md text-modal-title font-bold">{{ $clientId ? 'Modifier le client' : 'Ajouter un Client' }}</h2>
                <label class="mb-sm block text-xs">Nom
                    <input type="text" wire:model="nom" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Téléphone
                    <input type="text" wire:model="telephone" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="block text-xs">Date de naissance
                    <input type="date" wire:model="dateNaissance" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Enregistrer</button>
                </div>
            </form>
        </div>
    @endif

    @if ($aConfirmer)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-suppression">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-suppression" class="mb-sm text-modal-title font-bold">Supprimer ce client ?</h2>
                <p class="mb-md text-xs"><strong>{{ $aConfirmer->nom }}</strong> disparaît de la liste de tous les postes. Ses ventes gardent son nom.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerSuppression" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Supprimer</button>
                </div>
            </div>
        </div>
    @endif

    @if ($aRecouvrer)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-recouvrement">
            <form wire:submit="enregistrerRecouvrement" class="w-full max-w-sm rounded-lg bg-surface-card p-lg shadow-xl" data-modale="recouvrement">
                <h2 id="titre-recouvrement" class="mb-sm text-modal-title font-bold">Enregistrer un Paiement</h2>
                <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs"><strong>{{ $aRecouvrer->client }} · {{ $aRecouvrer->reference }}</strong><br>
                    <span class="text-error-deep">Solde restant dû : {{ number_format($aRecouvrer->total - $aRecouvrer->paye, 0, ',', ' ') }} FCFA</span></p>
                <label class="mb-sm block text-xs font-bold uppercase text-outline">Montant recouvré (FCFA) *
                    <input type="text" inputmode="numeric" wire:model="recMontant" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm font-normal normal-case text-black"></label>
                <label class="mb-sm block text-xs font-bold uppercase text-outline">Mode de règlement
                    <select wire:model="recMode" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm font-normal normal-case text-black">
                        @foreach ($modes as $m)<option value="{{ $m }}">{{ $m }}</option>@endforeach
                    </select></label>
                <p class="mb-sm text-caption text-outline">Un versement supérieur au reste dû est refusé. La vente passe en « Payée » une fois soldée.</p>
                @if ($erreurRecouvrement)<p role="alert" class="mb-sm text-xs text-error-deep" data-erreur="recouvrement">{{ $erreurRecouvrement }}</p>@endif
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="fermerRecouvrement" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Enregistrer</button>
                </div>
            </form>
        </div>
    @endif
</div>
