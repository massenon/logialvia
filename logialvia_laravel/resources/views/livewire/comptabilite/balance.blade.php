<div>
    @php($f = \App\Support\FormatComptable::class)
    @include('livewire.comptabilite._entete')

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="lecture-seule">
        Lecture seule : somme des écritures de tous les postes. Export : XLSX (bouton « Exporter ») et vue imprimable (« Imprimer / PDF ») ; le PDF généré du poste n'est pas reproduit.
    </p>

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        <div class="rounded-lg border-l-4 border-success-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Total Débits (Soldes Finaux)</p>
            <p class="text-page-title font-bold" data-kpi="debits">{{ $f::montant($totaux['final_debit']) }}</p>
        </div>
        <div class="rounded-lg border-l-4 border-error-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Total Crédits (Soldes Finaux)</p>
            <p class="text-page-title font-bold" data-kpi="credits">{{ $f::montant($totaux['final_credit']) }}</p>
        </div>
        <div class="rounded-lg border-l-4 {{ $equilibree ? 'border-success-deep' : 'border-error-deep' }} bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Écart (doit être 0)</p>
            <p class="text-page-title font-bold {{ $equilibree ? '' : 'text-error-deep' }}" data-kpi="ecart">{{ $f::montant(abs($ecart)) }}</p>
        </div>
    </div>

    @unless ($equilibree)
        <p class="mb-md rounded-lg bg-error-container p-md text-xs text-error-deep" role="alert" data-bandeau="desequilibre">
            <span class="font-bold">Balance Déséquilibrée — BR-CPT-004</span><br>
            Une anomalie de saisie doit être corrigée avant toute clôture (périodique ou annuelle) de l'exercice.
        </p>
    @endunless

    <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
        <h2 class="text-section-title font-bold">Soldes par compte — exercice {{ $annee }}</h2>
        <select wire:model.live="perimetre" aria-label="Période de la balance" data-selecteur="perimetre"
                class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
            <option value="mois">Mois en cours — {{ $libelleMois }}</option>
            <option value="exercice">Exercice complet — {{ $annee }}</option>
        </select>
    </div>

    @if (count($lignes) === 0)
        <p class="rounded-lg bg-surface-card p-lg text-center text-xs text-outline" data-vide>
            Aucun compte n'a été mouvementé sur l'exercice {{ $annee }}. La balance se remplit dès la première vente, le premier achat ou la première dépense.</p>
    @else
        <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs" data-table="balance">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm" rowspan="2">N° Compte</th>
                        <th class="px-md py-sm" rowspan="2">Libellé</th>
                        <th class="px-md py-sm text-center" colspan="2">Solde Ouverture</th>
                        <th class="px-md py-sm text-center" colspan="2">Mouvements Période</th>
                        <th class="px-md py-sm text-center" colspan="2">Solde Final</th>
                    </tr>
                    <tr>
                        @foreach (['Débit', 'Crédit', 'Débit', 'Crédit', 'Débit', 'Crédit'] as $sens)
                            <th class="px-md py-xs text-right">{{ $sens }}</th>
                        @endforeach
                    </tr>
                </thead>
                <tbody>
                    @foreach ($lignes as $l)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-compte="{{ $l['numero'] }}">
                            <td class="px-md py-sm font-mono font-bold">{{ $l['numero'] }}</td>
                            <td class="px-md py-sm">{{ $l['libelle'] }}</td>
                            <td class="px-md py-sm text-right">{{ $f::ouTiret($l['ouverture_debit']) }}</td>
                            <td class="px-md py-sm text-right">{{ $f::ouTiret($l['ouverture_credit']) }}</td>
                            <td class="px-md py-sm text-right">{{ $f::ouTiret($l['mouvements_debit']) }}</td>
                            <td class="px-md py-sm text-right">{{ $f::ouTiret($l['mouvements_credit']) }}</td>
                            <td class="px-md py-sm text-right font-bold text-success-deep" data-final-debit>{{ $f::ouTiret($l['final_debit']) }}</td>
                            <td class="px-md py-sm text-right font-bold text-error-deep" data-final-credit>{{ $f::ouTiret($l['final_credit']) }}</td>
                        </tr>
                    @endforeach
                </tbody>
                <tfoot class="bg-brand-navy text-white">
                    <tr data-totaux>
                        <td colspan="2" class="px-md py-sm font-bold">TOTAUX</td>
                        @foreach (['ouverture_debit', 'ouverture_credit', 'mouvements_debit', 'mouvements_credit', 'final_debit', 'final_credit'] as $cle)
                            <td class="px-md py-sm text-right font-bold" data-total="{{ $cle }}">{{ $f::nombre($totaux[$cle]) }}</td>
                        @endforeach
                    </tr>
                </tfoot>
            </table>
        </div>

        <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @foreach ($lignes as $l)
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-compte="{{ $l['numero'] }}">
                    <p class="font-mono font-bold text-brand-navy">{{ $l['numero'] }} <span class="font-sans font-normal text-outline">{{ $l['libelle'] }}</span></p>
                    <p class="text-xs">Mouvements : {{ $f::ouTiret($l['mouvements_debit']) }} / {{ $f::ouTiret($l['mouvements_credit']) }}</p>
                    <p class="text-xs font-bold">Solde final : {{ $f::ouTiret($l['final_debit']) }} D · {{ $f::ouTiret($l['final_credit']) }} C</p>
                </article>
            @endforeach
        </div>

        <p class="rounded-lg p-md text-xs font-bold {{ $equilibree ? 'bg-success-container text-success-deep' : 'bg-error-container text-error-deep' }}" data-bandeau="equilibre">
            @if ($equilibree)
                Total débiteur = total créditeur — équilibré
            @else
                Total débiteur = total créditeur — écart de {{ $f::montant(abs($ecart)) }}. Une clôture est impossible tant qu'il subsiste (BR-CPT-004).
            @endif
        </p>
    @endif
</div>
