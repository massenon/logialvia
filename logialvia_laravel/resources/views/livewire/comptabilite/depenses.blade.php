<div>
    @php($f = \App\Support\FormatComptable::class)
    @include('livewire.comptabilite._entete')

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="faits-immuables">
        Une dépense enregistrée est une pièce comptable partagée entre tous les postes : elle ne se modifie pas, elle s'annule par une
        écriture inverse. « Corriger » annule la pièce puis passe la pièce corrigée (en une seule opération). Pas de pièce justificative
        au web (le poste n'en stocke pas non plus). Export : XLSX (bouton « Exporter ») et vue imprimable (« Imprimer / PDF ») ; le PDF généré du poste n'est pas reproduit.
    </p>

    @if ($message)
        <p class="mb-md rounded-lg bg-success-container p-sm text-xs font-bold text-success-deep" data-message>{{ $message }}</p>
    @endif
    @if ($erreur)
        <p class="mb-md rounded-lg bg-error-container p-sm text-xs font-bold text-error-deep" role="alert" data-erreur>{{ $erreur }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Dépenses du Mois</span><x-icone nom="payments" class="text-[18px] text-brand-navy" /></div>
            <p class="text-page-title font-bold" data-kpi="mois">{{ $f::montant($depensesDuMois) }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Charges Fixes</span><x-icone nom="event_repeat" class="text-[18px] text-brand-navy" /></div>
            <p class="text-page-title font-bold" data-kpi="fixes">{{ $f::montant($chargesFixes) }}</p>
            <p class="text-caption text-outline">Comptes {{ implode(' et ', \App\Support\PlanSyscohada::COMPTES_CHARGES_FIXES) }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-success-deep bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Charges Variables</span><x-icone nom="trending_down" class="text-[18px] text-success-deep" /></div>
            <p class="text-page-title font-bold" data-kpi="variables">{{ $f::montant($chargesVariables) }}</p>
            <p class="text-caption text-outline">Autres comptes de charge</p>
        </div>
    </div>

    @if ($peutGerer)
        <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-lg shadow-sm" data-formulaire="depense">
            <h2 class="mb-xs flex items-center gap-xs text-section-title font-bold text-brand-navy"><x-icone nom="add_circle" class="text-[20px]" />Nouvelle Dépense</h2>
            <p class="mb-md text-xs text-outline">Enregistrez une charge d'exploitation de trésorerie directe. L'écriture comptable part immédiatement au Journal : compte de charge au débit, compte de trésorerie au crédit.</p>

            @if ($planIncomplet)
                <p class="rounded-lg bg-error-container p-sm text-xs text-error-deep" data-avertissement>Le plan comptable ne contient pas les comptes nécessaires (classe 6 et classe 5). Complétez-le depuis Plan Comptable avant de saisir une dépense.</p>
            @elseif ($cloture)
                <p class="rounded-lg bg-error-container p-sm text-xs text-error-deep" data-avertissement>L'exercice {{ $annee }} est clôturé : aucune écriture ne peut plus y être ajoutée ni modifiée.</p>
            @else
                <div class="grid grid-cols-1 gap-md md:grid-cols-2">
                    <div>
                        <label for="jour" class="block text-caption font-bold uppercase text-outline">Date de la transaction *</label>
                        <input id="jour" type="date" wire:model="jour" class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                    </div>
                    <div>
                        <label for="libelle" class="block text-caption font-bold uppercase text-outline">Libellé de la dépense *</label>
                        <input id="libelle" type="text" wire:model="libelle" class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                        @isset($erreurs['libelle'])<p class="text-invalid text-error-deep" data-erreur-champ="libelle">{{ $erreurs['libelle'] }}</p>@endisset
                    </div>
                    <div>
                        <label for="categorie" class="block text-caption font-bold uppercase text-outline">Catégorie de charges (SYSCOHADA) *</label>
                        <select id="categorie" wire:model="categorie" class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                            <option value="">-- Sélectionner --</option>
                            @foreach ($comptesCharge as $c)<option value="{{ $c->numero_compte }}">{{ $c->numero_compte }} - {{ $c->libelle }}</option>@endforeach
                        </select>
                        @isset($erreurs['categorie'])<p class="text-invalid text-error-deep" data-erreur-champ="categorie">{{ $erreurs['categorie'] }}</p>@endisset
                    </div>
                    <div>
                        <label for="montant" class="block text-caption font-bold uppercase text-outline">Montant décaissé (FCFA) *</label>
                        <input id="montant" type="text" inputmode="decimal" wire:model="montant" placeholder="ex : 12000" class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                        @isset($erreurs['montant'])<p class="text-invalid text-error-deep" data-erreur-champ="montant">{{ $erreurs['montant'] }}</p>@endisset
                    </div>
                    <div>
                        <label for="reglement" class="block text-caption font-bold uppercase text-outline">Compte de trésorerie crédité *</label>
                        <select id="reglement" wire:model="reglement" class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                            <option value="">-- Sélectionner --</option>
                            @foreach ($comptesTresorerie as $c)<option value="{{ $c->numero_compte }}">{{ $c->libelle }} ({{ $c->numero_compte }})</option>@endforeach
                            @foreach ($comptesFournisseurs as $c)<option value="{{ $c->numero_compte }}">À crédit — {{ $c->libelle }} ({{ $c->numero_compte }})</option>@endforeach
                        </select>
                        @isset($erreurs['reglement'])<p class="text-invalid text-error-deep" data-erreur-champ="reglement">{{ $erreurs['reglement'] }}</p>@endisset
                    </div>
                    <div>
                        <label for="centre" class="block text-caption font-bold uppercase text-outline">Centre analytique (facultatif)</label>
                        <select id="centre" wire:model="centre" class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                            <option value="">Non imputé</option>
                            @foreach ($centres as $c)<option value="{{ $c }}">{{ $c }}</option>@endforeach
                        </select>
                    </div>
                </div>
                <div class="mt-md flex justify-end">
                    @if ($corrigeDe)
                        <button type="button" wire:click="renoncerCorrection" data-action="renoncer-correction"
                                class="mr-sm rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Renoncer à la correction</button>
                    @endif
                    <button type="button" wire:click="enregistrer" data-action="enregistrer"
                            class="rounded-lg bg-brand-navy px-md py-sm text-xs font-bold text-white">Enregistrer la Dépense</button>
                </div>
            @endif
        </section>
    @endif

    <div class="mb-sm flex flex-wrap items-center gap-sm">
        <a href="{{ url('/depenses/impression') }}?statut={{ urlencode($statut) }}&amp;recherche={{ urlencode($recherche) }}" target="_blank" rel="noopener" data-action="imprimer-liste"
           class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra sm:order-last sm:ml-auto">Imprimer / PDF</a>
        <button type="button" wire:click="exporter" data-action="exporter"
                class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra sm:order-last">Exporter (XLSX)</button>
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Rechercher…" aria-label="Rechercher une dépense"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-xs">
        <select wire:model.live="statut" aria-label="Filtrer par statut" class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
            <option value="">Tous les statuts</option>
            <option value="payee">Payée</option>
            <option value="attente">En attente</option>
        </select>
        <button type="button" wire:click="reinitialiserFiltres" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Réinitialiser</button>
    </div>

    <h2 class="mb-sm text-section-title font-bold">Dépenses enregistrées</h2>
    <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs" data-table="depenses">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">N° Pièce</th>
                    <th class="px-md py-sm">Date</th>
                    <th class="px-md py-sm">Libellé</th>
                    <th class="px-md py-sm">Catégorie</th>
                    <th class="px-md py-sm text-right">Montant</th>
                    <th class="px-md py-sm text-center">Statut</th>
                    <th class="px-md py-sm text-right">Actions</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($depenses as $d)
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-depense="{{ $d['numero_piece'] }}">
                        <td class="px-md py-sm font-mono">{{ $d['numero_piece'] }}</td>
                        <td class="px-md py-sm">{{ $d['date']->format('d/m/Y') }}</td>
                        <td class="px-md py-sm font-bold">{{ $d['libelle'] }}</td>
                        <td class="px-md py-sm">{{ $d['compte'] }} - {{ $d['libelle_compte'] }}</td>
                        <td class="px-md py-sm text-right font-bold">{{ $f::montant($d['montant']) }}</td>
                        <td class="px-md py-sm text-center">
                            <span class="rounded-full px-sm py-xs font-semibold {{ $d['payee'] ? 'bg-success-container text-success-deep' : 'bg-brand-gold/20 text-brand-navy' }}" data-statut>{{ $d['payee'] ? 'Payée' : 'En attente' }}</span>
                        </td>
                        <td class="px-md py-sm text-right">
                            @if ($peutGerer && ! $cloture)
                                <button type="button" wire:click="corriger('{{ $d['piece_id'] }}')" data-action="corriger-depense"
                                        class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Corriger</button>
                                <button type="button" wire:click="demanderAnnulation('{{ $d['piece_id'] }}')" data-action="annuler-depense"
                                        class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Annuler la dépense</button>
                            @endif
                        </td>
                    </tr>
                @empty
                    <tr><td colspan="7" class="px-md py-lg text-center text-outline">
                        {{ $aucuneDepense ? "Aucune dépense enregistrée sur l'exercice $annee. Utilisez « Nouvelle Dépense » pour saisir une charge d'exploitation ; l'écriture correspondante partira automatiquement au Journal." : 'Aucune dépense ne correspond à ces filtres.' }}</td></tr>
                @endforelse
            </tbody>
            @if (count($depenses) > 0)
                <tfoot class="bg-surface-zebra">
                    <tr data-total>
                        <td colspan="4" class="px-md py-sm font-bold">TOTAL AFFICHÉ ({{ count($depenses) }} dépense{{ count($depenses) > 1 ? 's' : '' }})</td>
                        <td class="px-md py-sm text-right font-bold">{{ $f::montant($totalAffiche) }}</td>
                        <td colspan="2"></td>
                    </tr>
                </tfoot>
            @endif
        </table>
    </div>

    <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($depenses as $d)
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-depense="{{ $d['numero_piece'] }}">
                <p class="font-mono font-bold text-brand-navy">{{ $d['numero_piece'] }} <span class="text-caption font-normal text-outline">{{ $d['date']->format('d/m/Y') }}</span></p>
                <p class="text-xs font-bold">{{ $d['libelle'] }}</p>
                <p class="text-xs text-outline">{{ $d['compte'] }} - {{ $d['libelle_compte'] }}</p>
                <p class="text-xs font-bold">{{ $f::montant($d['montant']) }} · {{ $d['payee'] ? 'Payée' : 'En attente' }}</p>
                @if ($peutGerer && ! $cloture)
                    <button type="button" wire:click="demanderAnnulation('{{ $d['piece_id'] }}')" class="mt-sm w-full rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Annuler la dépense</button>
                @endif
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">
                {{ $aucuneDepense ? "Aucune dépense enregistrée sur l'exercice $annee." : 'Aucune dépense ne correspond à ces filtres.' }}</p>
        @endforelse
    </div>

    @if ($aAnnuler)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-annulation" data-modale="annulation">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-lg">
                <h2 id="titre-annulation" class="mb-md text-modal-title font-bold">Annuler cette dépense ?</h2>
                <p class="mb-md text-xs">Cette dépense est un fait partagé entre tous les postes : elle ne peut plus être effacée. Une écriture inverse (ANN-…) sera passée au Journal : la charge disparaîtra du Compte de Résultat et la trésorerie sera reconstituée d'autant.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-bold">Garder la dépense</button>
                    <button type="button" wire:click="confirmerAnnulation" data-action="confirmer-annulation" class="rounded-lg bg-error-deep px-md py-sm text-xs font-bold text-white">Annuler la dépense</button>
                </div>
            </div>
        </div>
    @endif
</div>
