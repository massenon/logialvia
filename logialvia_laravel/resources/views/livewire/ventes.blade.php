<div>
    <h1 class="sr-only">Ventes</h1>

    {{-- Onglets (maquette ventes.html) : icône + libellé --}}
    <div class="mb-md flex items-center gap-xs overflow-x-auto border-b border-outline-variant" role="tablist">
        @foreach ($onglets as $cle => $libelle)
            <button type="button" role="tab" wire:click="choisirOnglet('{{ $cle }}')" data-onglet="{{ $cle }}" aria-selected="{{ $onglet === $cle ? 'true' : 'false' }}"
                    class="flex items-center gap-xs whitespace-nowrap border-b-2 px-md py-3 text-xs font-bold {{ $onglet === $cle ? 'border-brand-navy text-brand-navy' : 'border-transparent text-outline' }}">
                <x-icone :nom="['caisse' => 'point_of_sale', 'historique' => 'receipt_long', 'retours' => 'assignment_return'][$cle] ?? 'receipt_long'" class="text-[18px]" />{{ $libelle }}</button>
        @endforeach
    </div>

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">CA du Jour</span><x-icone nom="trending_up" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="ca">{{ number_format($chiffreAffaires, 0, ',', ' ') }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-info-blue bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Panier Moyen</span><x-icone nom="calculate" class="text-[18px] text-info-blue" /></div>
            {{-- « — » et non « 0 » : une moyenne sur zéro vente n'existe pas (Dart). --}}
            <p class="mt-xs text-kpi-value font-extrabold"><span data-kpi="panier">{{ $panierMoyen === null ? '—' : number_format($panierMoyen, 0, ',', ' ') }}</span> <span class="text-xs font-normal">{{ $panierMoyen === null ? '' : 'FCFA' }}</span></p>
            <p class="text-caption text-outline">{{ $panierMoyen === null ? 'Aucune vente aujourd\'hui' : '' }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Ventes en Attente (Avance)</span><x-icone nom="pending" class="text-[18px] text-brand-gold" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="attente">{{ $enAttente }}</p>
        </div>
    </div>

    <details class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="ventes">
        <summary class="cursor-pointer font-semibold text-brand-navy">Comment le stock et la comptabilité suivent une vente faite au web</summary>
        <p class="mt-xs">Stock propre à chaque poste : le web n'a pas de stock, la vente désigne donc un <strong>poste de stock</strong> qui décrémente SON stock
        (une seule fois, à sa prochaine synchronisation ; le stock manquant est ramené à 0 avec un avertissement visible ici et au poste ; une annulation
        réintègre au même poste). Elle produit aussi ses écritures comptables et alimente le compteur de ventes du jour de la fiche d'élevage. Les devis de prestations se
        traitent dans leur propre écran ; l'export de l'historique se fait au format XLSX, la facture s'imprime depuis le détail d'une vente.</p>
    </details>

    <div class="mb-md">@include('partiels.lien-devis')</div>

    @php
        $badge = fn (string $s) => match ($s) {
            'Payée' => 'bg-success-container text-success-deep',
            'Avance' => 'bg-brand-gold/20 text-brand-navy',
            default => 'bg-error-container text-error-deep',
        };
        $fcfa = fn ($n) => number_format($n, 0, ',', ' ');
    @endphp

    {{-- ============================================================ Enregistrer Vente --}}
    @if ($onglet === 'caisse')
        @if ($message)
            <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep" data-message="caisse">
                {{ $message }}
                @if ($derniere)
                    <a href="{{ route('ventes.facture', $derniere->id) }}" target="_blank" class="ml-sm font-bold underline" data-lien="facture">Imprimer la facture</a>
                @endif
            </p>
        @endif

        @if (! $peutGerer)
            <p class="rounded-lg bg-surface-zebra p-md text-xs text-outline" data-lecture-seule>Votre rôle consulte les ventes : l'encaissement exige le droit de gérer les ventes.</p>
        @else
            <div class="grid grid-cols-1 gap-md lg:grid-cols-3">
                <section class="lg:col-span-2" data-section="produits">
                    <div class="mb-sm flex flex-wrap items-center gap-xs">
                        <label class="relative w-full sm:w-56">
                            <x-icone nom="search" class="absolute left-sm top-1/2 -translate-y-1/2 text-[18px] text-outline" />
                            <input type="search" wire:model.live.debounce.300ms="rechercheProduit" placeholder="Rechercher un produit..." aria-label="Rechercher un produit"
                                   class="w-full rounded-full border border-outline-variant bg-surface-zebra py-2 pl-9 pr-md text-xs outline-none focus:ring-2 focus:ring-brand-navy"></label>
                    </div>
                    <div class="mb-sm flex flex-wrap gap-xs" role="group" aria-label="Catégorie" data-categories>
                        <button type="button" wire:click="$set('categorie', '')" class="whitespace-nowrap rounded-full px-md py-1.5 text-xs font-bold {{ $categorie === '' ? 'bg-brand-navy text-white' : 'border border-outline-variant text-outline' }}">Tous</button>
                        @foreach ($categories as $c)
                            <button type="button" wire:click="$set('categorie', '{{ $c }}')" class="whitespace-nowrap rounded-full px-md py-1.5 text-xs font-bold {{ $categorie === $c ? 'bg-brand-navy text-white' : 'border border-outline-variant text-outline' }}">{{ $c }}</button>
                        @endforeach
                    </div>
                    <div class="grid grid-cols-2 content-start gap-sm sm:grid-cols-3 xl:grid-cols-4">
                        @forelse ($produits as $p)
                            <button type="button" wire:click="choisirProduit('{{ $p->id }}')" data-produit="{{ $p->name }}"
                                    class="flex flex-col gap-xs rounded-lg border border-outline-variant bg-white p-sm text-left text-xs transition-all hover:border-brand-navy hover:shadow-md">
                                <x-icone :nom="str_contains(mb_strtolower($p->cat), 'avicole') ? 'egg' : 'inventory_2'" class="mt-sm text-[28px] text-brand-navy" />
                                <p class="font-semibold leading-tight">{{ $p->name }}</p>
                                <p class="text-caption text-outline">{{ $p->cat }} · {{ $p->unit }}</p>
                                {{-- Fourchette de prix : une reference de negociation, jamais multipliee. --}}
                                <p class="font-bold text-brand-navy" data-fourchette>{{ $p->price_max !== null ? $fcfa($p->price).' – '.$fcfa($p->price_max) : $fcfa($p->price) }} F</p>
                            </button>
                        @empty
                            <p class="col-span-full rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun produit ne correspond à ce filtre.</p>
                        @endforelse
                    </div>
                </section>

                <section class="rounded-lg border border-outline-variant bg-white p-md" data-section="panier">
                    <div class="mb-sm flex items-center justify-between border-b border-outline-variant pb-sm">
                        <h2 class="text-xs font-bold text-brand-navy">Panier de Vente</h2>
                        <span class="flex h-6 w-6 items-center justify-center rounded-full bg-brand-navy text-xs font-bold text-white" data-compteur-panier>{{ count($panier) }}</span>
                    </div>
                    @forelse ($panier as $i => $l)
                        <div class="mb-xs flex items-center justify-between gap-sm text-xs" data-ligne-panier="{{ $l['nom'] }}">
                            <span>{{ $l['nom'] }} × {{ $l['qte'] }}</span>
                            <span class="font-bold">{{ $fcfa($l['montant']) }}</span>
                            <span>
                                <button type="button" wire:click="modifierLigne({{ $i }})" class="font-semibold text-brand-navy">Modifier</button>
                                <button type="button" wire:click="retirerLigne({{ $i }})" class="font-semibold text-error-deep">Retirer</button>
                            </span>
                        </div>
                    @empty
                        <div class="mb-sm flex flex-col items-center py-md text-center">
                            <x-icone nom="shopping_cart" class="text-[38px] text-outline-variant" />
                            <p class="mt-sm text-xs text-outline">Panier vide. Cliquez sur un produit pour l'ajouter.</p>
                        </div>
                    @endforelse

                    <label class="mb-sm mt-sm block text-caption font-bold uppercase text-brand-navy">Client
                        <select wire:change="choisirClientListe($event.target.value)" aria-label="Choisir un client" data-champ="client-liste" class="mt-xs w-full rounded-lg border border-outline-variant bg-white px-sm py-sm text-xs font-normal normal-case text-black">
                            <option value="">Client Comptant</option>
                            @foreach ($clientsListe as $cl)<option value="{{ $cl->id }}" @selected($clientId === $cl->id)>{{ $cl->nom }}</option>@endforeach
                        </select>
                        <input type="text" wire:model.live.debounce.300ms="client" placeholder="Client Comptant" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    @foreach ($suggestions as $c)
                        <button type="button" wire:click="choisirClient('{{ $c->id }}')" class="mb-xs block w-full rounded-lg border border-outline-variant px-sm py-xs text-left text-xs" data-suggestion="{{ $c->nom }}">{{ $c->nom }} <span class="text-outline">{{ $c->telephone ?: 'Sans téléphone' }}</span></button>
                    @endforeach
                    @if ($homonymes)
                        <p class="mb-sm text-caption text-error-deep" data-homonymes>Plusieurs clients portent ce nom : choisissez-en un dans la liste, sinon la vente ne sera rattachée à aucun.</p>
                    @endif

                    <label class="mb-sm block text-xs">Poste de stock
                        <select wire:model="posteCible" data-champ="poste-stock" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            <option value="">Aucun (journal seul : aucun stock ne bouge)</option>
                            @foreach ($postesStock as $p)<option value="{{ $p->device_id }}">{{ $p->code }}</option>@endforeach
                        </select>
                        @if ($postesStock->isEmpty())
                            <span class="text-caption text-outline" data-aucun-poste>Aucun poste appairé, actif et déjà synchronisé : la vente n'aura aucun effet de stock.</span>
                        @else
                            <span class="text-caption text-outline">Le poste dont le stock est décrémenté ; il ne change plus après la vente.</span>
                        @endif
                    </label>
                    <label class="mb-sm block text-xs">Mode de règlement
                        <select wire:model.live="mode" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            @foreach ($modes as $m)<option value="{{ $m }}">{{ $m }}</option>@endforeach
                        </select></label>
                    @if ($mode === 'Mobile Money')
                        <p class="mb-sm text-caption text-outline" data-ligne-momo>{{ $ligneMobileMoney ? 'Ligne créditée : '.$ligneMobileMoney : 'Aucun numéro Mobile Money enregistré — renseignez le Téléphone Principal dans Paramètres Généraux.' }}</p>
                    @endif
                    <label class="mb-sm block text-xs">Condition de paiement
                        <select wire:model.live="condition" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            @foreach ($conditions as $c)<option value="{{ $c }}">{{ $c }}</option>@endforeach
                        </select></label>
                    <label class="mb-sm block text-xs">{{ $condition === \App\Services\Commerce\VentesWeb::AVANCE ? 'Montant reçu (avance) *' : 'Montant reçu' }}
                        <input type="text" inputmode="numeric" wire:model.live.debounce.300ms="montantRecu" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    @if ($condition === \App\Services\Commerce\VentesWeb::AVANCE)
                        <label class="mb-sm block text-xs">Payable le
                            <input type="date" wire:model="echeance" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                        @if ($echeance === '')
                            <p class="mb-sm text-caption text-outline" data-sans-echeance>Sans échéance, cette créance ne sera jamais signalée en retard.{{ $delaiDefaut === null ? ' Un délai par défaut se règle dans Paramètres Généraux.' : '' }}</p>
                        @endif
                    @endif

                    <label class="mb-sm flex items-center gap-sm text-xs"><input type="checkbox" wire:model.live="livraisonActive"> Livraison concernée (cages, sujets volumineux)</label>
                    @if ($livraisonActive)
                        <div class="mb-sm rounded-lg bg-surface-zebra p-sm text-xs" data-livraison>
                            <select wire:model.live="livraisonMode" class="mb-xs w-full rounded-lg border border-outline-variant px-sm py-xs">
                                @foreach ($livraisons as $code => $libelle)<option value="{{ $code }}">{{ $libelle }}</option>@endforeach
                            </select>
                            @if ($livraisonMode === 'facturee')
                                <input type="text" inputmode="numeric" wire:model.live.debounce.300ms="livraisonFrais" placeholder="Frais de livraison (FCFA)" class="mb-xs w-full rounded-lg border border-outline-variant px-sm py-xs">
                            @endif
                            <input type="text" wire:model="livraisonAdresse" placeholder="Adresse de livraison" class="mb-xs w-full rounded-lg border border-outline-variant px-sm py-xs">
                            <input type="text" wire:model="livraisonContact" placeholder="Contact du transporteur" class="w-full rounded-lg border border-outline-variant px-sm py-xs">
                        </div>
                    @endif

                    @if ($supplement > 0)
                        <p class="flex justify-between text-xs text-outline"><span>Sous-total</span><span data-sous-total>{{ $fcfa($totalLignes) }}</span></p>
                        <p class="flex justify-between text-xs text-outline"><span>Livraison facturée</span><span data-supplement>+ {{ $fcfa($supplement) }}</span></p>
                    @endif
                    <p class="mb-sm flex items-center justify-between"><span class="text-caption font-bold uppercase text-outline">Total</span>
                        <span class="text-section-title font-bold text-success-deep" data-total>{{ $fcfa($totalPanier) }} FCFA</span></p>
                    @php $recu = (float) str_replace([' ', ','], ['', '.'], $montantRecu); @endphp
                    @if ($condition === \App\Services\Commerce\VentesWeb::COMPTANT && $recu > $totalPanier && $totalPanier > 0)
                        <p class="mb-sm text-xs text-outline" data-monnaie>Monnaie à rendre : {{ $fcfa($recu - $totalPanier) }} FCFA</p>
                    @endif

                    @if ($erreur)<p role="alert" class="mb-sm text-xs text-error-deep" data-erreur="caisse">{{ $erreur }}</p>@endif
                    <button type="button" wire:click="encaisser" {{ $panier === [] ? "disabled" : "" }}
                            class="flex w-full items-center justify-center gap-xs rounded-lg bg-brand-navy px-md py-sm text-xs font-bold text-white hover:bg-brand-navy-dark disabled:opacity-50"><x-icone nom="point_of_sale" class="text-[18px]" />Valider la Vente</button>
                </section>
            </div>

            @if ($produitAjout)
                <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-ajout">
                    <form wire:submit="validerAjout" class="w-full max-w-sm rounded-lg bg-surface-card p-lg shadow-xl" data-modale="vente-a-la-piece">
                        <h2 id="titre-ajout" class="mb-xs text-modal-title font-bold">Vente à la Pièce</h2>
                        <p class="mb-md text-xs text-outline">{{ $produitAjout->name }} — {{ $ajoutIndex !== null ? 'modification' : 'prix indicatif '.($produitAjout->price_max !== null ? $fcfa($produitAjout->price).' à '.$fcfa($produitAjout->price_max) : $fcfa($produitAjout->price)).' FCFA' }}</p>
                        <label class="mb-sm block text-xs font-bold uppercase text-outline">Quantité ({{ $produitAjout->unit }})
                            <input type="text" inputmode="numeric" wire:model="ajoutQte" placeholder="ex : 2" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm font-normal normal-case text-black"></label>
                        <label class="mb-sm block text-xs font-bold uppercase text-outline">Montant global de la vente (FCFA)
                            <input type="text" inputmode="numeric" wire:model="ajoutMontant" placeholder="ex : 4500" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm font-bold normal-case text-black"></label>
                        <p class="mb-sm text-caption text-outline">Vente à la pièce : saisissez directement le montant total convenu — jamais un prix unitaire multiplié automatiquement. Le prix indicatif n'est qu'une fourchette de référence.</p>
                        @if ($erreurAjout)<p role="alert" class="mb-sm text-xs text-error-deep">{{ $erreurAjout }}</p>@endif
                        <div class="flex justify-end gap-sm">
                            <button type="button" wire:click="annulerAjout" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                            <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">{{ $ajoutIndex !== null ? 'Enregistrer' : 'Ajouter au panier' }}</button>
                        </div>
                    </form>
                </div>
            @endif
        @endif
    @endif

    {{-- ====================================================== Historique des Ventes --}}
    @if ($onglet === 'historique')
        @if ($messageHistorique)
            <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep" data-message="historique">{{ $messageHistorique }}</p>
        @endif
        <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
            <div>
                <h2 class="flex items-center gap-xs text-page-title font-bold text-brand-navy"><x-icone nom="receipt_long" class="text-[24px]" />Historique des Ventes</h2>
                <p class="mt-xs text-xs text-outline">Toutes les transactions enregistrées via le Point de Vente.</p>
            </div>
        </div>
        <div class="mb-sm flex flex-wrap items-center gap-sm">
            <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Référence ou client…" aria-label="Rechercher une vente"
                   class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-xs">
            <select wire:model.live="statut" aria-label="Filtrer par statut" class="rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs">
                <option value="">Statut : Tous</option>
                @foreach ($statuts as $s)<option value="{{ $s }}">{{ $s }}</option>@endforeach
            </select>
            <select wire:model.live="modeFiltre" aria-label="Filtrer par mode" data-filtre="mode" class="rounded-lg border border-outline-variant bg-white px-sm py-sm text-xs">
                <option value="">Mode : Tous</option>
                @foreach ($modes as $m)<option value="{{ $m }}">{{ $m }}</option>@endforeach
            </select>
            <select wire:model.live="clientFiltre" aria-label="Filtrer par client" data-filtre="client" class="rounded-lg border border-outline-variant bg-white px-sm py-sm text-xs">
                <option value="">Client : Tous</option>
                @foreach ($clientsDesVentes as $c)<option value="{{ $c }}">{{ $c }}</option>@endforeach
            </select>
            @if ($peutExporter)
                <button type="button" wire:click="exporterHistorique" data-action="exporter-historique" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Exporter (XLSX)</button>
                <a href="{{ route('ventes.historique.imprimer', ['recherche' => $recherche, 'statut' => $statut, 'mode' => $modeFiltre, 'client' => $clientFiltre]) }}" target="_blank" data-lien="imprimer-historique" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Imprimer / PDF</a>
            @endif
        </div>

        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs" data-table="historique">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-sm py-sm">Référence</th><th class="px-sm py-sm">Client</th><th class="px-sm py-sm">Date</th>
                        <th class="px-sm py-sm text-right">Total</th><th class="px-sm py-sm text-right">Payé</th><th class="px-sm py-sm text-right">Reste</th>
                        <th class="px-sm py-sm">Mode</th><th class="px-sm py-sm text-center">Statut</th>
                        <th class="px-sm py-sm">Poste de stock</th>
                        @if ($peutGerer)<th class="px-sm py-sm text-right">Actions</th>@endif
                    </tr>
                </thead>
                <tbody>
                    @forelse ($ventes as $v)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-vente="{{ $v->reference }}">
                            <td class="cursor-pointer px-sm py-sm font-bold text-brand-navy" wire:click="ouvrir('{{ $v->id }}')">{{ $v->reference }}</td>
                            <td class="px-sm py-sm">{{ $v->client }}</td>
                            <td class="px-sm py-sm">{{ $v->date_vente->timezone($fuseau)->format('d/m/Y') }}</td>
                            <td class="px-sm py-sm text-right font-bold">{{ $fcfa($v->total) }}</td>
                            <td class="px-sm py-sm text-right">{{ $fcfa($v->paye) }}</td>
                            @php $reste = $v->status === 'Annulée' ? 0 : max(0, $v->total - $v->paye); @endphp
                            <td class="px-sm py-sm text-right {{ $reste > 0 ? 'font-bold text-error-deep' : '' }}">{{ $fcfa($reste) }}</td>
                            <td class="px-sm py-sm">{{ $v->mode }}</td>
                            <td class="px-sm py-sm text-center"><span class="rounded-full px-sm py-xs font-bold {{ $badge($v->status) }}">{{ $v->status }}</span></td>
                            @php $sv = $suiviStock[$v->id] ?? ['etat' => 'aucun', 'libelle' => '—', 'avertissement' => null]; @endphp
                            <td class="px-sm py-sm" data-poste-stock="{{ $sv['etat'] }}">
                                <span class="rounded-full px-sm py-xs font-semibold {{ $sv['etat'] === 'applique' ? 'bg-success-container text-success-deep' : (in_array($sv['etat'], ['avertissement', 'ignore', 'revoque'], true) ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-outline') }}">{{ $sv['libelle'] }}</span>
                                @if ($sv['avertissement'])<br><span class="text-caption text-error-deep" data-avertissement-stock>{{ $sv['avertissement'] }}</span>@endif
                            </td>
                            @if ($peutGerer)
                                <td class="px-sm py-sm text-right">
                                    @if ($v->status === 'Annulée')
                                        —
                                    @else
                                        <button type="button" wire:click="demanderModification('{{ $v->id }}')" data-action="modifier-vente" class="font-semibold text-brand-navy">Modifier</button>
                                        <button type="button" wire:click="demanderAnnulation('{{ $v->id }}')" data-action="annuler-vente" class="font-semibold text-error-deep">Annuler</button>
                                    @endif
                                </td>
                            @endif
                        </tr>
                    @empty
                        <tr><td colspan="10" class="px-md py-lg text-center text-outline">Aucune vente ne correspond. Les ventes encaissées apparaissent ici.</td></tr>
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
                    <p class="font-bold">{{ $fcfa($v->total) }} F</p>
                    <p class="text-caption text-outline" data-carte-poste-stock="{{ ($suiviStock[$v->id] ?? ['etat' => 'aucun'])['etat'] }}">Poste de stock : {{ ($suiviStock[$v->id] ?? ['libelle' => '—'])['libelle'] }}</p>
                </article>
            @empty
                <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucune vente ne correspond.</p>
            @endforelse
        </div>
    @endif

    {{-- ============================================================ Retours et Avoirs --}}
    @if ($onglet === 'retours')
        <p class="mb-sm text-xs text-outline" data-note="retours">Vue de consultation : elle se remplit depuis les annulations de l'Historique. Les factures d'avoir normalisées (e-MECeF) se gèrent dans Factures e-MECeF.</p>
        <div class="overflow-x-auto rounded-lg border border-outline-variant bg-surface-card">
            <table class="w-full text-left text-xs" data-table="retours">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr><th class="px-md py-sm">Référence</th><th class="px-md py-sm">Date</th><th class="px-md py-sm">Client</th><th class="px-md py-sm text-right">Montant</th><th class="px-md py-sm">Motif d'Annulation</th></tr>
                </thead>
                <tbody>
                    @forelse ($retours as $v)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-retour="{{ $v->reference }}">
                            <td class="px-md py-sm font-bold text-brand-navy">{{ $v->reference }}</td>
                            <td class="px-md py-sm">{{ $v->date_vente->timezone($fuseau)->format('d/m/Y') }}</td>
                            <td class="px-md py-sm">{{ $v->client }}</td>
                            <td class="px-md py-sm text-right">{{ $fcfa($v->total) }}</td>
                            <td class="px-md py-sm">{{ $v->motif_annulation ?? '—' }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucune vente annulée. Cette vue se remplit automatiquement depuis les annulations faites dans l'onglet Historique — aucune saisie directe n'est possible ici.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    @endif

    {{-- ===================================================================== Detail --}}
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
                    if ($ouverte->status === 'Avance') { $details['Reste dû'] = $fcfa(max(0, $ouverte->total - $ouverte->paye)).' FCFA'; }
                    if ($ouverte->echeance !== null) { $details['Payable le'] = $ouverte->echeance->timezone($fuseau)->format('d/m/Y'); }
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
                        <li class="mb-xs flex justify-between gap-sm"><span>{{ $l->name }} × {{ (int) $l->qte }}</span><span>{{ $fcfa($l->qte * $l->pu) }}</span></li>
                    @endforeach
                </ul>
                <hr class="my-sm border-outline-variant">
                <div class="flex items-center justify-between">
                    <span class="text-caption font-bold uppercase text-outline">Total</span>
                    <span class="text-section-title font-bold text-brand-navy">{{ $fcfa($ouverte->total) }} FCFA</span>
                </div>
                <div class="mt-md flex justify-end gap-sm">
                    <a href="{{ route('ventes.facture', $ouverte->id) }}" target="_blank" data-lien="facture" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Imprimer la Facture</a>
                    <button type="button" wire:click="fermer" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Fermer</button>
                </div>
            </div>
        </div>
    @endif

    {{-- ================================================================= Annulation --}}
    @if ($aAnnuler)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-annulation">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl" data-modale="annulation">
                <h2 id="titre-annulation" class="mb-sm text-modal-title font-bold">Annuler la vente {{ $aAnnuler->reference }} ?</h2>
                <p class="mb-md text-xs text-outline">L'écriture comptable de la vente est contrepassée (une écriture ne se supprime jamais). Aucun stock n'est restitué : il se tient au poste. La vente reste consultable dans « Retours et Avoirs ».</p>
                <label class="mb-sm block text-xs font-bold uppercase text-outline">Motif d'annulation *
                    <select wire:model="motifAnnulation" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm font-normal normal-case text-black">
                        <option value="">-- Sélectionner --</option>
                        @foreach ($motifs as $m)<option value="{{ $m }}">{{ $m }}</option>@endforeach
                    </select></label>
                @if ($erreurHistorique)<p role="alert" class="mb-sm text-xs text-error-deep" data-erreur="historique">{{ $erreurHistorique }}</p>@endif
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="fermerAnnulation" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Retour</button>
                    <button type="button" wire:click="confirmerAnnulation" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Confirmer l'Annulation</button>
                </div>
            </div>
        </div>
    @endif

    {{-- =============================================================== Modification --}}
    @if ($aModifier)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-modification">
            <form wire:submit="enregistrerModification" class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl" data-modale="modification">
                <h2 id="titre-modification" class="mb-sm text-modal-title font-bold">Modifier la vente {{ $aModifier->reference }}</h2>
                <p class="mb-md text-xs text-outline">Seuls le client, l'échéance et la livraison se modifient. Le montant, les lignes et le règlement ont un effet comptable : annulez la vente ou enregistrez un recouvrement.</p>
                <label class="mb-sm block text-xs">Client
                    <input type="text" wire:model.live.debounce.300ms="modClient" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @foreach ($clientsModification as $c)
                    <button type="button" wire:click="choisirClientModification('{{ $c->id }}')" class="mb-xs block w-full rounded-lg border border-outline-variant px-sm py-xs text-left text-xs">{{ $c->nom }}</button>
                @endforeach
                @if ($aModifier->status === 'Avance')
                    <label class="mb-sm block text-xs">Payable le
                        <input type="date" wire:model="modEcheance" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @endif
                @if ($aModifier->livraison_mode !== null)
                    <label class="mb-sm block text-xs">Adresse de livraison
                        <input type="text" wire:model="modAdresse" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="mb-sm block text-xs">Contact du transporteur
                        <input type="text" wire:model="modContact" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @endif
                @if ($erreurHistorique)<p role="alert" class="mb-sm text-xs text-error-deep" data-erreur="historique">{{ $erreurHistorique }}</p>@endif
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="fermerModification" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Enregistrer</button>
                </div>
            </form>
        </div>
    @endif
</div>
