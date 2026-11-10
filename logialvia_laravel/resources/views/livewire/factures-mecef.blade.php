<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <div>
            <h1 class="text-page-title font-bold">Facturation MeCeF</h1>
            <p class="text-xs text-outline">Factures de vente et factures d'avoir, conformité fiscale.</p>
        </div>
        <div class="flex flex-wrap gap-sm">
            <button type="button" wire:click="exporter" data-action="exporter"
                    class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Exporter (XLSX)</button>
            @if ($peutGerer)
                <button type="button" wire:click="ouvrirEmission" data-action="emettre"
                        class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Émettre une Facture</button>
            @endif
        </div>
    </div>

    <p class="mb-md rounded-lg border border-brand-gold bg-surface-zebra p-sm text-xs text-brand-gold" data-ecart="factures-mecef">
        Le web émet les factures de vente et les avoirs (statut « À transmettre »), mais il ne transmet rien à la DGI : le jeton et
        l'adresse du service e-MECeF restent sur les postes, jamais sur le serveur. Une facture émise au web se transmet depuis
        n'importe quel poste appairé (le serveur réserve la transmission à un seul poste à la fois, pour qu'elle ne soit pas
        normalisée deux fois). Une facture émise est immuable : pour la corriger, émettez un avoir.
    </p>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Facturé Net</p>
            <p class="text-page-title font-bold" data-kpi="net">{{ number_format($factureNet, 0, ',', ' ') }} <span class="text-xs font-normal">FCFA</span></p>
            <p class="text-caption text-outline">Factures de vente moins avoirs</p>
        </div>
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">À Transmettre</p>
            <p class="text-page-title font-bold" data-kpi="a-transmettre">{{ $aTransmettre }}</p>
            <p class="text-caption text-outline">Non encore normalisées</p>
        </div>
        <div class="rounded-lg border-l-4 border-success-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Normalisées</p>
            <p class="text-page-title font-bold" data-kpi="normalisees">{{ $normalisees }}</p>
            <p class="text-caption text-outline">Code MeCeF reçu de la DGI</p>
        </div>
        <div class="rounded-lg border-l-4 border-error-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Rejetées</p>
            <p class="text-page-title font-bold" data-kpi="rejetees">{{ $rejetees }}</p>
            <p class="text-caption text-outline">Transmission refusée</p>
        </div>
    </div>

    <div class="mb-sm flex flex-wrap items-center gap-sm">
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Rechercher une référence ou un client…" aria-label="Rechercher une facture"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-xs">
        <div class="flex flex-wrap gap-xs" role="group" aria-label="Filtrer par statut">
            @foreach (['' => 'Toutes'] + $libellesStatut as $cle => $libelle)
                <button type="button" wire:click="filtrer('{{ $cle }}')" data-filtre="{{ $cle === '' ? 'toutes' : $cle }}" aria-pressed="{{ $statut === $cle ? 'true' : 'false' }}"
                        class="rounded-full border px-md py-xs text-xs font-semibold {{ $statut === $cle ? 'border-brand-navy bg-brand-navy text-white' : 'border-outline-variant bg-surface-card text-brand-navy' }}">{{ $libelle }}</button>
            @endforeach
        </div>
    </div>

    @php
        $badge = fn (string $s) => match ($s) {
            'normalisee' => 'bg-success-container text-success-deep',
            'rejetee' => 'bg-error-container text-error-deep',
            default => 'bg-surface-zebra text-brand-gold',
        };
        $signe = fn ($f) => $f->type === 'FA' ? -1 : 1;
    @endphp

    <section class="rounded-lg border border-outline-variant bg-surface-card" aria-labelledby="titre-liste">
        <h2 id="titre-liste" class="border-b border-outline-variant px-md py-sm text-section-title font-bold">Factures et avoirs</h2>

        @if ($factures->isEmpty())
            <p class="p-lg text-center text-xs text-outline" data-vide>
                {{ $statut === '' && trim($recherche) === '' ? 'Aucune facture émise. Les factures émises depuis le poste apparaissent ici.' : 'Aucune facture ne correspond à ces filtres.' }}
            </p>
        @else
            <div class="hidden overflow-x-auto sm:block">
                <table class="w-full text-left text-xs" data-table="factures">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-md py-sm">Référence</th>
                            <th class="px-md py-sm">Date</th>
                            <th class="px-md py-sm">Client</th>
                            <th class="px-md py-sm text-right">Total TTC</th>
                            <th class="px-md py-sm">Statut</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($factures as $f)
                            <tr class="cursor-pointer {{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-facture="{{ $f->reference }}" wire:click="ouvrir('{{ $f->id }}')">
                                <td class="px-md py-sm font-bold {{ $f->type === 'FA' ? 'text-error-deep' : 'text-brand-navy' }}">{{ $f->reference }}</td>
                                <td class="px-md py-sm">{{ $f->date_facture->timezone($fuseau)->format('d/m/Y') }}</td>
                                <td class="px-md py-sm">
                                    {{ $f->client }}
                                    @if ($f->origine_ref !== null)
                                        <span class="block text-caption text-outline">sur {{ $f->origine_ref }}</span>
                                    @endif
                                </td>
                                <td class="px-md py-sm text-right font-bold">{{ number_format($signe($f) * $f->total_ttc, 0, ',', ' ') }} FCFA</td>
                                <td class="px-md py-sm" title="{{ $f->erreur_transmission }}"><span class="rounded-full px-sm py-xs font-bold {{ $badge($f->statut) }}">{{ $libellesStatut[$f->statut] }}</span></td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-sm p-sm sm:hidden" data-vue="cartes">
                @foreach ($factures as $f)
                    <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-facture="{{ $f->reference }}" wire:click="ouvrir('{{ $f->id }}')">
                        <div class="flex items-center justify-between gap-sm">
                            <p class="font-bold {{ $f->type === 'FA' ? 'text-error-deep' : 'text-brand-navy' }}">{{ $f->reference }}</p>
                            <span class="rounded-full px-sm py-xs text-caption font-bold {{ $badge($f->statut) }}">{{ $libellesStatut[$f->statut] }}</span>
                        </div>
                        <p class="text-caption text-outline">{{ $f->date_facture->timezone($fuseau)->format('d/m/Y') }} · {{ $f->client }}@if ($f->origine_ref !== null) · sur {{ $f->origine_ref }}@endif</p>
                        <p class="font-bold">{{ number_format($signe($f) * $f->total_ttc, 0, ',', ' ') }} FCFA</p>
                    </article>
                @endforeach
            </div>
        @endif
    </section>

    @if ($ouverte)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-facture">
            <div class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl" data-detail="{{ $ouverte->reference }}">
                <h2 id="titre-facture" class="mb-md text-modal-title font-bold">{{ $ouverte->type === 'FA' ? "Facture d'avoir" : 'Facture de vente' }} {{ $ouverte->reference }}</h2>
                @php
                    $details = ['Client' => $ouverte->client];
                    if ($ouverte->client_ifu !== null) { $details['IFU du client'] = $ouverte->client_ifu; }
                    if ($ouverte->client_adresse !== null) { $details['Adresse du client'] = $ouverte->client_adresse; }
                    $details['Date'] = $ouverte->date_facture->timezone($fuseau)->format('d/m/Y');
                    if ($ouverte->vente_ref !== null) { $details['Vente d\'origine'] = $ouverte->vente_ref; }
                    if ($ouverte->origine_ref !== null) { $details['Facture corrigée'] = $ouverte->origine_ref; }
                    if ($ouverte->motif !== null) { $details['Motif'] = $ouverte->motif; }
                    $details['Statut'] = $libellesStatut[$ouverte->statut];
                    if ($ouverte->statut === 'normalisee') {
                        $details['Code MeCeF'] = $ouverte->code_mecef;
                        $details['NIM'] = $ouverte->nim;
                        if ($ouverte->compteur !== null) { $details['Compteur'] = $ouverte->compteur; }
                        if ($ouverte->lien_verification !== null) { $details['Lien de vérification'] = $ouverte->lien_verification; }
                        if ($ouverte->date_normalisation !== null) { $details['Normalisée le'] = $ouverte->date_normalisation->timezone($fuseau)->format('d/m/Y'); }
                    }
                    if ($ouverte->erreur_transmission !== null && $ouverte->statut !== 'normalisee') { $details['Erreur de transmission'] = $ouverte->erreur_transmission; }
                    $details['Émise sur'] = $posteEmission;
                @endphp
                <dl class="mb-sm text-xs">
                    @foreach ($details as $libelle => $valeur)
                        <div class="mb-xs flex gap-sm"><dt class="w-40 shrink-0 text-outline">{{ $libelle }}</dt><dd class="break-words font-semibold">{{ $valeur }}</dd></div>
                    @endforeach
                </dl>
                <hr class="my-sm border-outline-variant">
                <p class="mb-xs text-caption font-bold uppercase text-outline">Lignes</p>
                <ul class="mb-sm text-xs" data-lignes>
                    @foreach ($ouverte->lignes as $l)
                        <li class="mb-xs flex justify-between gap-sm">
                            <span>{{ $l->designation }} × {{ rtrim(rtrim(number_format($l->quantite, 2, ',', ' '), '0'), ',') }}{{ $l->unite !== null ? ' '.$l->unite : '' }} <span class="text-outline">({{ $l->groupe_taxe }} · {{ rtrim(rtrim(number_format($l->taux_taxe, 2, ',', ' '), '0'), ',') }} %)</span></span>
                            <span>{{ number_format($l->montant_ht, 0, ',', ' ') }}</span>
                        </li>
                    @endforeach
                </ul>
                <p class="mb-xs text-caption font-bold uppercase text-outline">Totaux par groupe de taxe</p>
                <ul class="mb-sm text-xs" data-groupes>
                    @foreach ($totauxParGroupe as $g)
                        <li class="mb-xs flex justify-between gap-sm" data-groupe="{{ $g['groupe'] }}">
                            <span>Groupe {{ $g['groupe'] }} ({{ rtrim(rtrim(number_format($g['taux'], 2, ',', ' '), '0'), ',') }} %)</span>
                            <span>base {{ number_format($g['base'], 0, ',', ' ') }} · taxe {{ number_format($g['taxe'], 0, ',', ' ') }}</span>
                        </li>
                    @endforeach
                </ul>
                <hr class="my-sm border-outline-variant">
                <div class="flex items-center justify-between text-xs">
                    <span class="text-outline">Total HT</span><span class="font-semibold" data-total="ht">{{ number_format($ouverte->total_ht, 0, ',', ' ') }} FCFA</span>
                </div>
                <div class="flex items-center justify-between text-xs">
                    <span class="text-outline">Taxe</span><span class="font-semibold" data-total="taxe">{{ number_format($ouverte->total_taxe, 0, ',', ' ') }} FCFA</span>
                </div>
                <div class="flex items-center justify-between">
                    <span class="text-caption font-bold uppercase text-outline">Total TTC</span>
                    <span class="text-section-title font-bold text-brand-navy" data-total="ttc">{{ number_format(($ouverte->type === 'FA' ? -1 : 1) * $ouverte->total_ttc, 0, ',', ' ') }} FCFA</span>
                </div>
                @if ($ouverte->device_id === \App\Livewire\Catalogue::POSTE_WEB && $ouverte->statut !== 'normalisee')
                    <p class="mt-sm text-caption text-outline" data-info="transmission-web">Émise au web : à transmettre à la DGI depuis un poste appairé (le serveur réserve la transmission à un seul poste).</p>
                @endif
                <div class="mt-md flex flex-wrap justify-end gap-sm">
                    <a href="{{ route('factures-mecef.imprimer', $ouverte->id) }}" target="_blank" rel="noopener" data-action="imprimer"
                       class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Imprimer / PDF</a>
                    @if ($peutGerer && $ouverte->type === 'FV')
                        <button type="button" wire:click="ouvrirAvoir('{{ $ouverte->id }}')" data-action="avoir"
                                class="rounded-lg border border-error-deep px-md py-sm text-xs font-semibold text-error-deep hover:bg-error-container">Émettre un avoir</button>
                    @endif
                    <button type="button" wire:click="fermer" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Fermer</button>
                </div>
            </div>
        </div>
    @endif
    @if ($emission)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-emission">
            <form wire:submit="emettre" class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl" data-form="emission">
                <h2 id="titre-emission" class="mb-sm text-modal-title font-bold">Émettre une facture de vente</h2>
                <p class="mb-md text-xs text-outline">Les prix de la caisse sont des montants toutes taxes comprises : ils sont ramenés hors taxe selon le groupe de taxe de chaque produit. Une seule facture par vente.</p>
                <label class="mb-sm block text-xs">Vente à facturer *
                    <select wire:model="venteId" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                        <option value="">— Choisir une vente —</option>
                        @foreach ($ventesAFacturer as $v)
                            <option value="{{ $v->id }}">{{ $v->reference }} · {{ $v->client }} · {{ number_format($v->total, 0, ',', ' ') }} FCFA · {{ $v->date_vente->timezone($fuseau)->format('d/m/Y') }}</option>
                        @endforeach
                    </select></label>
                @if ($ventesAFacturer->isEmpty())
                    <p class="mb-sm text-xs text-outline" data-vide>Toutes les ventes ont déjà leur facture.</p>
                @endif
                <label class="mb-sm block text-xs">IFU du client (facultatif)
                    <input type="text" wire:model="ifu" maxlength="40" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="block text-xs">Adresse du client (facultatif)
                    <input type="text" wire:model="adresse" maxlength="255" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annulerSaisie" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Émettre la Facture</button>
                </div>
            </form>
        </div>
    @endif

    @if ($origineAvoir)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-avoir">
            <form wire:submit="emettreAvoir" class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl" data-form="avoir">
                <h2 id="titre-avoir" class="mb-sm text-modal-title font-bold">Émettre un avoir sur {{ $origineAvoir->reference }}</h2>
                <p class="mb-sm text-xs text-outline">Facture de {{ number_format($origineAvoir->total_ttc, 0, ',', ' ') }} FCFA TTC, dont {{ number_format($dejaCredite, 0, ',', ' ') }} FCFA déjà crédités par des avoirs. Un avoir ne dépasse jamais la facture.</p>
                <label class="mb-sm flex items-center gap-sm text-xs"><input type="checkbox" wire:model.live="avoirTotal"> Avoir total (reprend toutes les lignes de la facture)</label>
                @unless ($avoirTotal)
                    <ul class="mb-sm text-xs" data-lignes-avoir>
                        @foreach ($origineAvoir->lignes as $l)
                            <li class="mb-xs flex items-center justify-between gap-sm">
                                <span>{{ $l->designation }} <span class="text-outline">(facturé : {{ rtrim(rtrim(number_format($l->quantite, 2, ',', ' '), '0'), ',') }})</span></span>
                                <input type="text" inputmode="decimal" wire:model="avoirQuantites.{{ $l->id }}" placeholder="0" aria-label="Quantité créditée de {{ $l->designation }}"
                                       class="w-24 rounded-lg border border-outline-variant px-sm py-xs text-right">
                            </li>
                        @endforeach
                    </ul>
                @endunless
                <label class="block text-xs">Motif de l'avoir *
                    <input type="text" wire:model="avoirMotif" maxlength="255" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annulerSaisie" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Émettre l'Avoir</button>
                </div>
            </form>
        </div>
    @endif
</div>
