<div>
    @php
        $nombre = fn ($v) => number_format($v, 0, ',', ' ');
        $quantite = fn ($v) => rtrim(rtrim(number_format($v, 2, ',', ' '), '0'), ',');
        $fuseau = config('logialvia.fuseau');
    @endphp

    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <div><h1 class="flex items-center gap-xs text-page-title font-bold text-brand-navy"><x-icone nom="local_shipping" class="text-[24px]" />Achats &amp; Commandes</h1><p class="mt-xs text-xs text-outline">Enregistrement des achats d'intrants de provende, produits vétérinaires et marchandises.</p></div>
        <div class="flex flex-wrap gap-sm">
            <a href="{{ url('/achats/impression') }}?statut={{ urlencode($statut) }}&amp;recherche={{ urlencode($recherche) }}" target="_blank" rel="noopener" data-action="imprimer-liste"
               class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Imprimer / PDF</a>
            <button type="button" wire:click="exporter" data-action="exporter"
                    class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Exporter (XLSX)</button>
            @if ($peutGerer)
                <button type="button" wire:click="nouveau" data-action="nouvelle-commande"
                        class="rounded-full bg-brand-navy px-md py-sm text-xs font-bold text-white shadow-sm hover:bg-brand-navy-dark">Nouvelle commande</button>
            @endif
        </div>
    </div>

    @if ($peutGerer)
        <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="stock-poste">
            Le stock et le PMP sont propres à chaque poste, et le web n'en a pas. Une commande désigne donc un <strong>poste de stock</strong> :
            à la réception, les entrées sont inscrites au <strong>journal partagé</strong> et <strong>ce poste, et lui seul</strong>, ajoute les quantités à son
            stock et recalcule son PMP, une seule fois, à sa prochaine synchronisation (hors ligne : l'opération l'attend). Les autres postes la lisent comme
            de l'historique. Le poste d'une commande ne change plus une fois choisi ; l'annulation d'une commande livrée retire les quantités du même poste.
        </p>
    @else
        <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="lecture-seule">
            Consultation seule : seul l'administrateur passe, modifie, réceptionne, règle ou annule une commande.
        </p>
    @endif

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs font-bold text-success-deep" data-message>{{ $message }}</p>
    @endif
    @if ($erreur && ! $formulaire && ! $aAnnuler)
        <p role="alert" class="mb-md rounded-lg bg-error-container p-sm text-xs font-bold text-error-deep" data-erreur>{{ $erreur }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Commandes en Cours</span><x-icone nom="pending" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="en-cours">{{ $enCours }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Montant Total Engagé</span><x-icone nom="payments" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="engage">{{ $nombre($engage) }} <span class="text-xs font-normal">FCFA</span></p>
            <p class="text-caption text-outline">Commandes non encore réceptionnées</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-success-deep bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Achats Cumulés (Mois)</span><x-icone nom="shopping_cart" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="mois">{{ $nombre($achatsDuMois) }} <span class="text-xs font-normal">FCFA</span></p>
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
                    <th class="px-sm py-sm">Référence</th>
                    <th class="px-sm py-sm">Date</th>
                    <th class="px-sm py-sm">Fournisseur</th>
                    <th class="px-sm py-sm text-right">Montant</th>
                    <th class="px-sm py-sm">Mode</th>
                    <th class="px-sm py-sm text-center">Statut</th>
                    <th class="px-sm py-sm">Poste de stock</th>
                    <th class="px-sm py-sm text-right">Payé</th>
                    <th class="px-sm py-sm text-right">Solde Dû</th>
                    <th class="px-sm py-sm text-center">Ancienneté</th>
                    <th class="px-sm py-sm text-right">Actions</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($achats as $a)
                    @php
                        $solde = $a->statut === 'Annulé' ? 0 : max(0, $a->total - $a->paye);
                        $jours = max(0, (int) $a->date_achat->diffInDays($maintenant, true));
                    @endphp
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-achat="{{ $a->reference }}">
                        <td class="px-sm py-sm font-bold font-mono text-brand-navy">{{ $a->reference }}</td>
                        <td class="px-sm py-sm">{{ $a->date_achat->timezone($fuseau)->format('d/m/Y') }}</td>
                        <td class="px-sm py-sm">{{ $noms[$a->fournisseur_id] ?? '—' }}</td>
                        <td class="px-sm py-sm text-right font-bold">{{ $nombre($a->total) }}</td>
                        <td class="px-sm py-sm">{{ $a->mode ?: '—' }}</td>
                        <td class="px-sm py-sm text-center">
                            <span class="rounded-full px-sm py-xs font-semibold {{ $a->statut === 'Livré' ? 'bg-success-container text-success-deep' : ($a->statut === 'Annulé' ? 'bg-error-container text-error-deep' : 'bg-brand-gold/20 text-brand-navy') }}" data-statut>{{ $a->statut }}</span>
                        </td>
                        @php $sv = $suiviStock[$a->id]; @endphp
                        <td class="px-sm py-sm" data-poste-stock="{{ $sv['etat'] }}">
                            <span class="rounded-full px-sm py-xs font-semibold {{ in_array($sv['etat'], ['applique'], true) ? 'bg-success-container text-success-deep' : (in_array($sv['etat'], ['avertissement', 'ignore', 'revoque'], true) ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-outline') }}">{{ $sv['libelle'] }}</span>
                            @if ($sv['avertissement'])<br><span class="text-caption text-error-deep" data-avertissement-stock>{{ $sv['avertissement'] }}</span>@endif
                        </td>
                        <td class="px-sm py-sm text-right">{{ $nombre($a->paye) }}</td>
                        <td class="px-sm py-sm text-right {{ $solde > 0 ? 'font-bold text-error-deep' : 'text-outline' }}" data-solde>
                            {{ $solde > 0 ? $nombre($solde).' F' : 'Soldée' }}</td>
                        <td class="px-sm py-sm text-center">
                            @if ($solde > 0)
                                <span class="rounded-full px-sm py-xs font-semibold {{ $jours > 10 ? 'bg-error-container text-error-deep' : 'bg-surface-zebra text-outline' }}">{{ $jours }} j</span>
                            @else
                                <span class="text-outline">—</span>
                            @endif
                        </td>
                        <td class="px-sm py-sm text-right">
                            <div class="flex flex-wrap justify-end gap-xs">
                            <button type="button" wire:click="basculer('{{ $a->id }}')" aria-expanded="{{ $detail?->id === $a->id ? 'true' : 'false' }}"
                                    class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">
                                {{ $detail?->id === $a->id ? 'Masquer' : 'Lignes' }}</button>
                            <a href="{{ url('/achats/'.$a->id.'/bon') }}" target="_blank" rel="noopener" data-action="bon-de-commande"
                               class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Bon</a>
                            @if ($peutGerer && $a->statut !== 'Annulé')
                                @if ($a->statut === 'Commandé')
                                    <button type="button" wire:click="modifier('{{ $a->id }}')" data-action="modifier"
                                            class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier</button>
                                    <button type="button" wire:click="demanderReception('{{ $a->id }}')" data-action="receptionner"
                                            class="rounded-lg border border-brand-navy px-sm py-xs font-semibold text-brand-navy hover:bg-surface-zebra">Réceptionner</button>
                                @endif
                                @if ($solde > 0)
                                    <button type="button" wire:click="demanderReglement('{{ $a->id }}')" data-action="regler"
                                            class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Régler</button>
                                @endif
                                <button type="button" wire:click="demanderAnnulation('{{ $a->id }}')" data-action="annuler-commande"
                                        class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Annuler</button>
                            @endif
                            </div>
                        </td>
                    </tr>
                    @if ($detail?->id === $a->id)
                        <tr data-lignes-de="{{ $a->reference }}">
                            <td colspan="11" class="bg-surface-zebra px-sm py-sm">
                                <p class="mb-xs text-caption text-outline" data-echeance>Échéance : {{ $a->echeance ? $a->echeance->timezone($fuseau)->format('d/m/Y') : 'aucune convenue' }}</p>
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
                    <tr><td colspan="11" class="px-md py-lg text-center text-outline">
                        {{ $aucunAchat ? 'Aucune commande enregistrée. Composez-en une avec « Nouvelle commande ».' : 'Aucun achat ne correspond.' }}</td></tr>
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
                    <span class="rounded-full px-sm py-xs text-caption font-semibold {{ $a->statut === 'Livré' ? 'bg-success-container text-success-deep' : ($a->statut === 'Annulé' ? 'bg-error-container text-error-deep' : 'bg-brand-gold/20 text-brand-navy') }}">{{ $a->statut }}</span>
                </div>
                <p class="text-caption text-outline">{{ $a->date_achat->timezone($fuseau)->format('d/m/Y') }} · {{ $noms[$a->fournisseur_id] ?? '—' }} · {{ $a->mode ?: '—' }}</p>
                <p class="text-xs">Montant {{ $nombre($a->total) }} F · Payé {{ $nombre($a->paye) }} F</p>
                <p class="text-xs" data-carte-poste-stock="{{ $suiviStock[$a->id]['etat'] }}">Poste de stock : {{ $suiviStock[$a->id]['libelle'] }}</p>
                <p class="text-xs font-bold {{ $solde > 0 ? 'text-error-deep' : 'text-outline' }}">
                    {{ $solde > 0 ? 'Reste '.$nombre($solde).' F ('.$jours.' j)' : 'Soldée' }}</p>
                <button type="button" wire:click="basculer('{{ $a->id }}')"
                        class="mt-sm w-full rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">
                    {{ $detail?->id === $a->id ? 'Masquer les lignes' : 'Voir les lignes' }}</button>
                <div class="mt-sm flex flex-wrap gap-sm">
                    <a href="{{ url('/achats/'.$a->id.'/bon') }}" target="_blank" rel="noopener" class="rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Bon de commande</a>
                    @if ($peutGerer && $a->statut !== 'Annulé')
                        @if ($a->statut === 'Commandé')
                            <button type="button" wire:click="modifier('{{ $a->id }}')" class="rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Modifier</button>
                            <button type="button" wire:click="demanderReception('{{ $a->id }}')" class="rounded-lg border border-brand-navy px-sm py-sm text-xs font-semibold text-brand-navy">Réceptionner</button>
                        @endif
                        @if ($solde > 0)
                            <button type="button" wire:click="demanderReglement('{{ $a->id }}')" class="rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Régler</button>
                        @endif
                        <button type="button" wire:click="demanderAnnulation('{{ $a->id }}')" class="rounded-lg border border-error-deep px-sm py-sm text-xs font-semibold text-error-deep">Annuler</button>
                    @endif
                </div>
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
                {{ $aucunAchat ? 'Aucune commande enregistrée. Composez-en une avec « Nouvelle commande ».' : 'Aucun achat ne correspond.' }}</p>
        @endforelse
    </div>

    @include('livewire.achats._reglement')

    @if ($formulaire)
        <div class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-commande" data-modale="commande">
            <form wire:submit="enregistrer" class="my-md w-full max-w-2xl rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-commande" class="mb-md text-modal-title font-bold">{{ $achatId ? 'Modifier la commande' : 'Nouvelle commande' }}</h2>

                <h3 class="mb-xs text-xs font-bold uppercase text-outline">Panier d'Achat</h3>
                <div class="mb-sm flex gap-sm">
                    <select wire:model="intrantAjoute" aria-label="Intrant à commander" class="min-w-0 flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs" data-champ="intrant">
                        <option value="">Intrant à commander…</option>
                        @foreach ($intrants as $i)
                            <option value="{{ $i->code }}">{{ $i->name }} ({{ $i->unit }})</option>
                        @endforeach
                    </select>
                    <button type="button" wire:click="ajouterIntrant" data-action="ajouter-intrant" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Ajouter</button>
                </div>
                @if (count($lignes) === 0)
                    <p class="mb-sm rounded-lg bg-surface-zebra p-sm text-xs text-outline">Choisissez un intrant pour l'ajouter. Le prix unitaire est à saisir : le PMP est propre à chaque poste.</p>
                @endif
                @foreach ($lignes as $i => $l)
                    <div class="mb-xs flex items-center gap-sm" data-ligne-panier="{{ $l['intrant_code'] }}">
                        <span class="min-w-0 flex-1 truncate text-xs font-bold">{{ $intrantsParCode[$l['intrant_code']]->name ?? $l['intrant_code'] }}
                            <span class="font-normal text-outline">({{ $intrantsParCode[$l['intrant_code']]->unit ?? '' }})</span></span>
                        <input type="text" inputmode="numeric" wire:model.live.debounce.300ms="lignes.{{ $i }}.qte" aria-label="Quantité" placeholder="Qté"
                               class="w-16 rounded-lg border border-outline-variant px-sm py-xs text-center text-xs">
                        <input type="text" inputmode="decimal" wire:model.live.debounce.300ms="lignes.{{ $i }}.pu" aria-label="Prix unitaire" placeholder="Prix unitaire"
                               class="w-24 rounded-lg border border-outline-variant px-sm py-xs text-center text-xs">
                        <button type="button" wire:click="retirerLigne({{ $i }})" aria-label="Retirer la ligne" class="px-xs text-error-deep">✕</button>
                    </div>
                @endforeach

                <div class="mt-md grid grid-cols-1 gap-sm sm:grid-cols-2">
                    <label class="block text-xs">Fournisseur *
                        <select wire:model="fournisseurId" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm" data-champ="fournisseur">
                            <option value="">-- Sélectionner --</option>
                            @foreach ($fournisseurs as $f)
                                <option value="{{ $f->id }}">{{ $f->nom }}</option>
                            @endforeach
                        </select>
                        @if ($fournisseurs->isEmpty())
                            <span class="text-caption text-error-deep">Créez d'abord un fournisseur depuis l'écran Fournisseurs.</span>
                        @endif
                    </label>
                    <label class="block text-xs">Mode de règlement
                        <select wire:model="mode" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            @foreach ($modes as $m)
                                <option value="{{ $m }}">{{ $m }}</option>
                            @endforeach
                        </select>
                    </label>
                    <label class="block text-xs">Montant réglé
                        <input type="text" inputmode="decimal" wire:model="paye" {{ $achatId ? 'disabled' : '' }} class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm disabled:bg-surface-zebra">
                        @if ($achatId)<span class="text-caption text-outline">Un règlement se saisit par « Régler ».</span>@endif
                    </label>
                    <label class="block text-xs">Échéance de la dette (facultatif)
                        <input type="date" wire:model="echeance" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm" data-champ="echeance">
                    </label>
                    <label class="block text-xs sm:col-span-2">Poste de stock
                        <select wire:model="posteCible" {{ $posteLie ? 'disabled' : '' }} data-champ="poste-stock"
                                class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm disabled:bg-surface-zebra">
                            <option value="">Aucun (journal seul : aucun stock ne bouge)</option>
                            @foreach ($postesStock as $p)
                                <option value="{{ $p->device_id }}">{{ $p->code }}</option>
                            @endforeach
                            @if ($posteLie && ! $postesStock->contains('device_id', $posteLie))
                                <option value="{{ $posteLie }}">{{ \App\Services\PosteDeStock::code($posteLie) ?? 'poste inconnu' }}</option>
                            @endif
                        </select>
                        <span class="text-caption text-outline">{{ $posteLie ? 'Lié à la commande : il ne peut plus être changé.' : 'Le poste dont le stock et le PMP seront mis à jour à la réception. Une fois choisi, il ne change plus.' }}</span>
                        @if ($postesStock->isEmpty() && ! $posteLie)
                            <span class="block text-caption text-error-deep" data-aucun-poste>Aucun poste appairé, actif et déjà synchronisé n'est disponible.</span>
                        @endif
                    </label>
                </div>
                @unless ($achatId)
                    <label class="mt-sm flex items-center gap-sm text-xs">
                        <input type="checkbox" wire:model="livree" class="rounded border-outline-variant">
                        Livrée immédiatement (inscrit les entrées au journal ; le poste de stock choisi applique l'entrée et le PMP à son stock)
                    </label>
                @endunless

                <p class="mt-md text-right text-section-title font-bold" data-total-panier>TOTAL {{ number_format($totalPanier, 0, ',', ' ') }} FCFA</p>

                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs font-bold text-error-deep" data-erreur-formulaire>{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annulerFormulaire" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" data-action="valider-commande" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">{{ $achatId ? 'Enregistrer la modification' : 'Valider la Commande' }}</button>
                </div>
            </form>
        </div>
    @endif

    @if ($confirmationReception)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-reception" data-modale="reception">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-reception" class="mb-sm text-modal-title font-bold">Réceptionner {{ $confirmationReception->reference }} ?</h2>
                <p class="mb-sm text-xs">Une entrée par ligne est inscrite au journal partagé. Le <strong>poste de stock</strong> choisi ci-dessous ajoute les quantités à
                    <strong>son propre stock</strong> et recalcule son PMP, une seule fois, à sa prochaine synchronisation (rien ne se perd s'il est hors ligne).</p>
                <label class="mb-md block text-xs">Poste de stock
                    <select wire:model="posteReception" {{ $confirmationReception->poste_cible ? 'disabled' : '' }} data-champ="poste-reception"
                            class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm disabled:bg-surface-zebra">
                        <option value="">Aucun (journal seul : aucun stock ne bouge)</option>
                        @foreach ($postesStock as $p)
                            <option value="{{ $p->device_id }}">{{ $p->code }}</option>
                        @endforeach
                        @if ($confirmationReception->poste_cible && ! $postesStock->contains('device_id', $confirmationReception->poste_cible))
                            <option value="{{ $confirmationReception->poste_cible }}">{{ \App\Services\PosteDeStock::code($confirmationReception->poste_cible) ?? 'poste inconnu' }}</option>
                        @endif
                    </select>
                    <span class="text-caption text-outline">{{ $confirmationReception->poste_cible ? 'Lié à la commande : il ne peut plus être changé.' : 'Proposé : le poste qui a passé la commande, sinon votre dernier choix.' }}</span>
                </label>
                @if ($erreur)
                    <p role="alert" class="mb-sm text-xs font-bold text-error-deep" data-erreur-reception>{{ $erreur }}</p>
                @endif
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annulerReception" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerReception" data-action="confirmer-reception" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Réceptionner</button>
                </div>
            </div>
        </div>
    @endif

    @if ($confirmationAnnulation)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-annulation" data-modale="annulation">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-annulation" class="mb-sm text-modal-title font-bold">Annuler {{ $confirmationAnnulation->reference }} ?</h2>
                <p class="mb-sm text-xs">Les écritures de la commande sont <strong>extournées</strong> (écritures inverses, elles ne sont pas supprimées).
                    @if ($confirmationAnnulation->paye > 0)
                        <strong class="text-error-deep">{{ number_format($confirmationAnnulation->paye, 0, ',', ' ') }} FCFA ont été réglés : l'extourne suppose que le fournisseur les rembourse.</strong>
                    @endif
                    @if ($confirmationAnnulation->statut === 'Livré')
                        La commande est livrée : une sortie par ligne est inscrite au journal et
                        {{ $confirmationAnnulation->poste_cible ? 'le poste de stock '.(\App\Services\PosteDeStock::code($confirmationAnnulation->poste_cible) ?? '?').' retirera les quantités de son stock (sortie inverse, une seule fois)' : 'aucun stock ne bouge (aucun poste n\'était désigné)' }}.
                    @endif
                </p>
                <label class="block text-xs">Motif de l'annulation *
                    <input type="text" wire:model="motifAnnulation" maxlength="120" data-champ="motif" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs font-bold text-error-deep" data-erreur-annulation>{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="renoncerAnnulation" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Renoncer</button>
                    <button type="button" wire:click="confirmerAnnulation" data-action="confirmer-annulation" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Annuler la commande</button>
                </div>
            </div>
        </div>
    @endif
</div>
