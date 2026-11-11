<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <div><h1 class="flex items-center gap-xs text-page-title font-bold text-brand-navy"><x-icone nom="category" class="text-[24px]" />Catalogue &amp; Seuils</h1><p class="mt-xs text-xs text-outline">Fiche produit maître (SKU, tarification) — distincte du suivi de quantités de Gestion Stocks.</p></div>
        @if ($peutGerer)
            <button type="button" wire:click="nouveau"
                    class="rounded-full bg-brand-navy px-md py-sm text-xs font-bold text-white shadow-sm hover:bg-brand-navy-dark">
                Ajouter un Produit
            </button>
        @endif
    </div>

    <p class="mb-md text-xs text-outline">
        Le catalogue est partagé par tous les postes. Le <strong>stock</strong> reste propre à chaque poste : il se lit sur le poste.
        Une correction saisie ici <strong>désigne le poste de stock</strong> qui l'applique à son propre stock, une seule fois, à sa
        prochaine synchronisation.
    </p>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Produits au catalogue</span><x-icone nom="inventory_2" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="produits">{{ $nombre }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Catégories</span><x-icone nom="category" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="categories">{{ $nombreCategories }}</p>
        </div>
    </div>

    <div class="mb-md flex flex-col gap-sm sm:flex-row">
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Désignation ou code…"
               aria-label="Rechercher un produit"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">
        <select wire:model.live="categorie" aria-label="Catégorie"
                class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
            <option value="">Toutes les catégories</option>
            @foreach ($categories as $c)
                <option value="{{ $c }}">{{ $c }}</option>
            @endforeach
        </select>
    </div>

    <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Désignation</th>
                    <th class="px-md py-sm">Catégorie</th>
                    <th class="px-md py-sm">Unité</th>
                    <th class="px-md py-sm text-right">Tarif</th>
                    <th class="px-md py-sm text-right">Coût de revient</th>
                    <th class="px-md py-sm text-right">Seuil d'alerte</th>
                    @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                </tr>
            </thead>
            <tbody>
                @forelse ($produits as $p)
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-produit="{{ $p->sku }}">
                        <td class="px-md py-sm"><span class="font-bold">{{ $p->name }}</span><br><span class="text-caption text-outline">{{ $p->sku }}</span></td>
                        <td class="px-md py-sm">{{ $p->cat }}</td>
                        <td class="px-md py-sm">{{ $p->unit }}</td>
                        <td class="px-md py-sm text-right font-bold text-brand-navy">
                            {{ number_format($p->price, 0, ',', ' ') }}@if ($p->price_max) – {{ number_format($p->price_max, 0, ',', ' ') }}@endif F
                        </td>
                        <td class="px-md py-sm text-right">{{ $p->cout_revient === null ? '—' : number_format($p->cout_revient, 0, ',', ' ').' F' }}</td>
                        <td class="px-md py-sm text-right">{{ $p->threshold }}</td>
                        @if ($peutGerer)
                            <td class="px-md py-sm text-right">
                                <button type="button" wire:click="ouvrirCorrection('{{ $p->id }}')" data-action="corriger-stock" class="rounded-lg border border-brand-navy px-sm py-xs font-semibold text-brand-navy hover:bg-surface-zebra">Corriger le stock</button>
                                <button type="button" wire:click="modifier('{{ $p->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier</button>
                                <button type="button" wire:click="demanderSuppression('{{ $p->id }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer</button>
                            </td>
                        @endif
                    </tr>
                @empty
                    <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucun produit ne correspond.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($produits as $p)
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-produit="{{ $p->sku }}">
                <p class="font-bold">{{ $p->name }}</p>
                <p class="mb-xs text-caption text-outline">{{ $p->cat }} · {{ $p->unit }} · {{ $p->sku }}</p>
                <p class="font-bold text-brand-navy">{{ number_format($p->price, 0, ',', ' ') }}@if ($p->price_max) – {{ number_format($p->price_max, 0, ',', ' ') }}@endif F</p>
                @if ($peutGerer)
                    <div class="mt-sm flex gap-sm">
                        <button type="button" wire:click="modifier('{{ $p->id }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Modifier</button>
                        <button type="button" wire:click="demanderSuppression('{{ $p->id }}')" class="flex-1 rounded-lg border border-error-deep px-sm py-sm text-xs font-semibold text-error-deep">Supprimer</button>
                    </div>
                @endif
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun produit ne correspond.</p>
        @endforelse
    </div>

    @if ($corrections->isNotEmpty())
        <h2 class="mb-sm mt-lg text-section-title font-bold">Dernières corrections de stock saisies ici</h2>
        <div class="overflow-x-auto rounded-lg border border-outline-variant bg-surface-card" data-table="corrections-stock">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr><th class="px-md py-sm">Produit</th><th class="px-md py-sm text-right">Variation</th><th class="px-md py-sm">Motif</th><th class="px-md py-sm">Poste de stock</th></tr>
                </thead>
                <tbody>
                    @foreach ($corrections as $c)
                        @php $s = $suiviCorrections[$c->id]; @endphp
                        <tr data-correction="{{ $c->id }}">
                            <td class="px-md py-sm font-bold">{{ $c->article }}</td>
                            <td class="px-md py-sm text-right font-bold {{ $c->quantite >= 0 ? 'text-success-deep' : 'text-error-deep' }}">{{ $c->quantite > 0 ? '+' : '' }}{{ (int) $c->quantite }}</td>
                            <td class="px-md py-sm">{{ $c->motif }}</td>
                            <td class="px-md py-sm" data-suivi="{{ $s['etat'] }}">{{ $s['libelle'] }}@if ($s['avertissement'])<br><span class="text-caption text-error-deep">{{ $s['avertissement'] }}</span>@endif</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </div>
    @endif

    @if ($produitCorrige)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-correction" data-modale="correction-stock">
            <form wire:submit="enregistrerCorrection" class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-correction" class="mb-sm text-modal-title font-bold">Corriger le stock de {{ $produitCorrige->name }}</h2>
                <p class="mb-md text-xs text-outline">Le web n'a pas de stock : la correction est inscrite au journal partagé et <strong>appliquée par le poste désigné</strong>
                    à son propre stock (une fois, à sa prochaine synchronisation). Les autres postes la lisent comme de l'historique.</p>
                <label class="mb-sm block text-xs">Poste de stock *
                    <select wire:model="correctionPoste" data-champ="poste-stock" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                        <option value="">-- Choisir un poste --</option>
                        @foreach ($postesCorrection as $p)<option value="{{ $p->device_id }}">{{ $p->code }}</option>@endforeach
                    </select>
                    @if ($postesCorrection->isEmpty())<span class="text-caption text-error-deep">Aucun poste appairé, actif et déjà synchronisé n'est disponible.</span>@endif
                </label>
                <label class="mb-sm block text-xs">Variation (négative pour retirer) *
                    <input type="text" inputmode="numeric" wire:model="correctionVariation" data-champ="variation" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Motif *
                    <input type="text" wire:model="correctionMotif" maxlength="255" data-champ="motif" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @if ($erreurCorrection)
                    <p role="alert" class="mb-sm text-xs font-bold text-error-deep" data-erreur-correction>{{ $erreurCorrection }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="fermerCorrection" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" data-action="valider-correction" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Inscrire la correction</button>
                </div>
            </form>
        </div>
    @endif

    @if ($formulaire)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-produit">
            <form wire:submit="enregistrer" class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-produit" class="mb-md text-modal-title font-bold">{{ $produitId ? 'Modifier le produit' : 'Ajouter un Produit' }}</h2>
                <div class="grid grid-cols-1 gap-sm sm:grid-cols-2">
                    <label class="text-xs sm:col-span-2">Désignation
                        <input type="text" wire:model="nom" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="text-xs sm:col-span-2">Catégorie (filière : Avicole, Cuniculture, Héliciculture, Élevage ovin, Pisciculture…)
                        <select wire:model="cat" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            @foreach ($categories as $c)<option value="{{ $c }}">{{ $c }}</option>@endforeach
                        </select></label>
                    <label class="text-xs">Tarif indicatif (F)
                        <input type="text" inputmode="decimal" wire:model="prix" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="text-xs">Prix haut de fourchette (F)
                        <input type="text" inputmode="decimal" wire:model="prixMax" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="text-xs">Coût de revient (F)
                        <input type="text" inputmode="decimal" wire:model="coutRevient" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="text-xs">Unité
                        <input type="text" wire:model="unite" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="text-xs">Seuil d'alerte
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

    @if ($aConfirmer)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-suppression">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-suppression" class="mb-sm text-modal-title font-bold">Supprimer ce produit ?</h2>
                <p class="mb-md text-xs">
                    <strong>{{ $aConfirmer->name }}</strong> quittera le catalogue de tous les postes. Un poste qui l'a déjà vendu
                    le garde pour son historique.
                </p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerSuppression" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Supprimer</button>
                </div>
            </div>
        </div>
    @endif
</div>
