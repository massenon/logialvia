<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <h1 class="text-page-title font-bold">Fournisseurs</h1>
        @if ($peutGerer)
            <button type="button" wire:click="nouveau"
                    class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">
                Ajouter un Fournisseur
            </button>
        @endif
    </div>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-lg border-l-4 border-brand-navy bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Fournisseurs Actifs</p>
            <p class="text-page-title font-bold" data-kpi="actifs">{{ $nombre }}</p>
        </div>
        <div class="rounded-lg border-l-4 border-error-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Dette Totale</p>
            <p class="text-page-title font-bold" data-kpi="dette">{{ number_format($detteTotale, 0, ',', ' ') }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Achats Cumulés (Mois)</p>
            <p class="text-page-title font-bold" data-kpi="achats-mois">{{ number_format($achatsDuMois, 0, ',', ' ') }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border-l-4 border-success-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Dettes Soldées (Mois)</p>
            <p class="text-page-title font-bold" data-kpi="soldees-mois">{{ $dettesSoldeesMois }}</p>
        </div>
    </div>

    <h2 class="mb-sm text-section-title font-bold">Fournisseurs</h2>
    <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Nom, téléphone ou produits fournis…" aria-label="Rechercher un fournisseur"
           class="mb-sm w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">

    <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Nom</th>
                    <th class="px-md py-sm">Téléphone</th>
                    <th class="px-md py-sm">Fournit</th>
                    <th class="px-md py-sm text-center">Commandes</th>
                    <th class="px-md py-sm text-right">Total Achats</th>
                    <th class="px-md py-sm text-right">Solde Dû</th>
                    @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                </tr>
            </thead>
            <tbody>
                @forelse ($fournisseurs as $f)
                    @php($ag = $agregats[$f->id])
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-fournisseur="{{ $f->nom }}">
                        <td class="px-md py-sm font-bold">{{ $f->nom }}</td>
                        <td class="px-md py-sm">{{ $f->telephone ?: '—' }}</td>
                        <td class="px-md py-sm">{{ $f->fournit ?: '—' }}</td>
                        <td class="px-md py-sm text-center">{{ $ag['commandes'] }}</td>
                        <td class="px-md py-sm text-right">{{ number_format($ag['total'], 0, ',', ' ') }}</td>
                        <td class="px-md py-sm text-right font-bold {{ $ag['solde'] > 0 ? 'text-error-deep' : 'text-success-deep' }}">{{ number_format($ag['solde'], 0, ',', ' ') }}</td>
                        @if ($peutGerer)
                            <td class="px-md py-sm text-right">
                                <button type="button" wire:click="modifier('{{ $f->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier</button>
                                <button type="button" wire:click="demanderSuppression('{{ $f->id }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer</button>
                            </td>
                        @endif
                    </tr>
                @empty
                    <tr><td colspan="7" class="px-md py-lg text-center text-outline">
                        {{ $nombre === 0 ? 'Aucun fournisseur enregistré. Il en faut au moins un pour pouvoir passer une commande.' : 'Aucun fournisseur ne correspond.' }}</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>
    <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($fournisseurs as $f)
            @php($ag = $agregats[$f->id])
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-fournisseur="{{ $f->nom }}">
                <p class="font-bold">{{ $f->nom }}</p>
                <p class="text-caption text-outline">{{ $f->telephone ?: '—' }} · {{ $f->fournit ?: '—' }}</p>
                <p class="text-caption text-outline">{{ $ag['commandes'] }} commande(s) · {{ number_format($ag['total'], 0, ',', ' ') }} F</p>
                <p class="font-bold {{ $ag['solde'] > 0 ? 'text-error-deep' : 'text-success-deep' }}">Solde dû : {{ number_format($ag['solde'], 0, ',', ' ') }} F</p>
                @if ($peutGerer)
                    <div class="mt-sm flex gap-sm">
                        <button type="button" wire:click="modifier('{{ $f->id }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Modifier</button>
                        <button type="button" wire:click="demanderSuppression('{{ $f->id }}')" class="flex-1 rounded-lg border border-error-deep px-sm py-sm text-xs font-semibold text-error-deep">Supprimer</button>
                    </div>
                @endif
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">
                {{ $nombre === 0 ? 'Aucun fournisseur enregistré. Il en faut au moins un pour pouvoir passer une commande.' : 'Aucun fournisseur ne correspond.' }}</p>
        @endforelse
    </div>

    <h2 class="mb-xs text-section-title font-bold">Dettes Fournisseurs</h2>
    <p class="mb-sm text-xs text-outline">Le règlement d'une dette s'enregistre sur le poste, là où l'achat a été saisi.</p>
    <div class="overflow-x-auto rounded-lg border border-outline-variant bg-surface-card">
        <table class="w-full text-left text-xs" data-table="dettes">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Fournisseur</th>
                    <th class="px-md py-sm">Référence Achat</th>
                    <th class="px-md py-sm text-right">Montant Total</th>
                    <th class="px-md py-sm text-right">Déjà Réglé</th>
                    <th class="px-md py-sm text-right">Solde Dû</th>
                    <th class="px-md py-sm text-center">Ancienneté</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($dettes as $d)
                    @php($jours = max(0, (int) $d->date_achat->diffInDays($maintenant, true)))
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-dette="{{ $d->reference }}">
                        <td class="px-md py-sm font-bold">{{ $noms[$d->fournisseur_id] }}</td>
                        <td class="px-md py-sm font-mono">{{ $d->reference }}</td>
                        <td class="px-md py-sm text-right">{{ number_format($d->total, 0, ',', ' ') }}</td>
                        <td class="px-md py-sm text-right">{{ number_format($d->paye, 0, ',', ' ') }}</td>
                        <td class="px-md py-sm text-right font-bold text-error-deep">{{ number_format($d->total - $d->paye, 0, ',', ' ') }}</td>
                        <td class="px-md py-sm text-center">
                            <span class="rounded-full px-sm py-xs font-semibold {{ $jours > 10 ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-outline' }}">{{ $jours }} j</span>
                        </td>
                    </tr>
                @empty
                    <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucune dette ouverte. Les commandes non entièrement réglées apparaissent ici.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    @if ($formulaire)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-fournisseur">
            <form wire:submit="enregistrer" class="w-full max-w-sm rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-fournisseur" class="mb-md text-modal-title font-bold">{{ $fournisseurId ? 'Modifier le fournisseur' : 'Ajouter un Fournisseur' }}</h2>
                <label class="mb-sm block text-xs">Nom *
                    <input type="text" wire:model="nom" maxlength="255" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Téléphone
                    <input type="text" wire:model="telephone" maxlength="40" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Adresse
                    <input type="text" wire:model="adresse" maxlength="255" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="block text-xs">Fournit
                    <input type="text" wire:model="fournit" maxlength="255" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                    <span class="text-caption text-outline">Ex. « Maïs, Soja »</span></label>
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
                <h2 id="titre-suppression" class="mb-sm text-modal-title font-bold">Supprimer ce fournisseur ?</h2>
                <p class="mb-md text-xs"><strong>{{ $aConfirmer->nom }}</strong> disparaît de la liste de tous les postes. Ses achats passés gardent son nom.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerSuppression" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Supprimer</button>
                </div>
            </div>
        </div>
    @endif
</div>
