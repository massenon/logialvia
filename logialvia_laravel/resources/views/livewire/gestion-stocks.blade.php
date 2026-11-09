<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <h1 class="text-page-title font-bold">Gestion des Stocks</h1>
        @if ($peutGerer)
            <button type="button" wire:click="nouveau"
                    class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">
                Ajouter un Intrant
            </button>
        @endif
    </div>

    <p class="mb-md text-xs text-outline">
        Les intrants et le journal sont partagés par tous les postes. Le <strong>stock</strong>, le prix unitaire (PMP),
        la valeur du stock et les intrants sous seuil restent <strong>propres à chaque poste</strong> : ils se lisent et se
        corrigent sur le poste, jamais ici. Les ajustements d'inventaire et la fabrication de provende se font donc au poste,
        et la suppression d'un intrant n'existe pas côté serveur.
    </p>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2">
        <div class="rounded-lg border-l-4 border-info-blue bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Articles Suivis</p>
            <p class="text-page-title font-bold" data-kpi="articles">{{ $articlesSuivis }}</p>
        </div>
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Mouvements (7j)</p>
            <p class="text-page-title font-bold" data-kpi="mouvements">{{ $mouvements7Jours }}</p>
        </div>
    </div>

    <h2 class="mb-sm text-modal-title font-bold">Intrants</h2>

    <div class="mb-md flex flex-col gap-sm sm:flex-row">
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Désignation ou code…"
               aria-label="Rechercher un intrant"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">
        <select wire:model.live="categorie" aria-label="Catégorie"
                class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
            <option value="">Toutes</option>
            @foreach ($categories as $c)
                <option value="{{ $c }}">{{ $c }}</option>
            @endforeach
        </select>
    </div>

    <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Désignation</th>
                    <th class="px-md py-sm">Catégorie</th>
                    <th class="px-md py-sm">Unité</th>
                    <th class="px-md py-sm text-right">Seuil Alerte</th>
                    @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                </tr>
            </thead>
            <tbody>
                @forelse ($intrants as $i)
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-intrant="{{ $i->code }}">
                        <td class="px-md py-sm"><span class="font-bold">{{ $i->name }}</span><br><span class="text-caption text-outline">{{ $i->code }}</span></td>
                        <td class="px-md py-sm">{{ $i->cat }}</td>
                        <td class="px-md py-sm">{{ $i->unit }}</td>
                        <td class="px-md py-sm text-right">{{ $i->threshold }}</td>
                        @if ($peutGerer)
                            <td class="px-md py-sm text-right">
                                <button type="button" wire:click="modifier('{{ $i->code }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier</button>
                            </td>
                        @endif
                    </tr>
                @empty
                    <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun intrant ne correspond.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($intrants as $i)
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-intrant="{{ $i->code }}">
                <p class="font-bold">{{ $i->name }}</p>
                <p class="text-caption text-outline">{{ $i->cat }} · {{ $i->unit }} · {{ $i->code }}</p>
                <p class="text-xs">Seuil d'alerte : <span class="font-bold">{{ $i->threshold }}</span></p>
                @if ($peutGerer)
                    <div class="mt-sm">
                        <button type="button" wire:click="modifier('{{ $i->code }}')" class="w-full rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Modifier</button>
                    </div>
                @endif
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun intrant ne correspond.</p>
        @endforelse
    </div>

    <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
        <h2 class="text-modal-title font-bold">Journal des Mouvements</h2>
        <div class="flex gap-sm">
            <a href="{{ url('/stocks/impression') }}" target="_blank" rel="noopener" data-action="imprimer-journal"
               class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Imprimer / PDF</a>
            <button type="button" wire:click="exporter" data-action="exporter"
                    class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Exporter (XLSX)</button>
        </div>
    </div>
    <p class="mb-sm text-xs text-outline">
        Historique de tous les postes (les {{ \App\Livewire\GestionStocks::LIMITE_JOURNAL }} derniers), en lecture seule :
        un mouvement d'un autre poste ne change jamais le stock d'un poste. Heures en UTC.
    </p>

    <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Date / Heure</th>
                    <th class="px-md py-sm">Référence</th>
                    <th class="px-md py-sm">Article</th>
                    <th class="px-md py-sm">Type</th>
                    <th class="px-md py-sm">Motif</th>
                    <th class="px-md py-sm">Poste</th>
                    <th class="px-md py-sm text-right">Quantité</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($journal as $ligne)
                    @php($m = $ligne['mouvement'])
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-mouvement="{{ $m->id }}">
                        <td class="px-md py-sm">{{ $m->horodatage->format('d/m/Y H:i') }}</td>
                        <td class="px-md py-sm text-outline">{{ $m->reference ?? '—' }}</td>
                        <td class="px-md py-sm font-bold">{{ $m->article }}</td>
                        <td class="px-md py-sm">{{ $m->type }}</td>
                        <td class="px-md py-sm">{{ $m->motif }}</td>
                        <td class="px-md py-sm" data-poste>{{ $ligne['poste'] }}</td>
                        <td class="px-md py-sm text-right font-bold {{ $m->quantite >= 0 ? 'text-success-deep' : 'text-error-deep' }}">{{ ($m->quantite > 0 ? '+' : '').rtrim(rtrim(number_format($m->quantite, 3, ',', ' '), '0'), ',') }}</td>
                    </tr>
                @empty
                    <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucun mouvement enregistré. Les réceptions de commandes et les ajustements d'inventaire apparaissent ici automatiquement.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes-journal">
        @forelse ($journal as $ligne)
            @php($m = $ligne['mouvement'])
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-mouvement="{{ $m->id }}">
                <p class="font-bold">{{ $m->article }}</p>
                <p class="text-caption text-outline">{{ $m->horodatage->format('d/m/Y H:i') }} · {{ $m->type }} · {{ $ligne['poste'] }}@if ($m->reference) · {{ $m->reference }}@endif</p>
                <p class="text-xs">{{ $m->motif }}</p>
                <p class="font-bold {{ $m->quantite >= 0 ? 'text-success-deep' : 'text-error-deep' }}">{{ ($m->quantite > 0 ? '+' : '').rtrim(rtrim(number_format($m->quantite, 3, ',', ' '), '0'), ',') }}</p>
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun mouvement enregistré. Les réceptions de commandes et les ajustements d'inventaire apparaissent ici automatiquement.</p>
        @endforelse
    </div>

    @if ($formulaire)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-intrant">
            <form wire:submit="enregistrer" class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-intrant" class="mb-md text-modal-title font-bold">{{ $code ? 'Modifier '.$nom : 'Ajouter un Intrant' }}</h2>
                <div class="grid grid-cols-1 gap-sm sm:grid-cols-2">
                    <label class="text-xs sm:col-span-2">Désignation *
                        <input type="text" wire:model="nom" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="text-xs sm:col-span-2">Catégorie *
                        <select wire:model="cat" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            <option value="">-- Sélectionner --</option>
                            @foreach ($categories as $c)<option value="{{ $c }}">{{ $c }}</option>@endforeach
                        </select></label>
                    <label class="text-xs">Unité
                        <input type="text" wire:model="unite" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="text-xs">Seuil d'Alerte
                        <input type="text" inputmode="numeric" wire:model="seuil" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                </div>
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
</div>
