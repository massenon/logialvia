<div>
    @php($f = \App\Support\FormatComptable::class)
    @php($fuseau = config('logialvia.fuseau'))
    @include('livewire.comptabilite._entete')

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="faits-immuables">
        Une pièce enregistrée est un fait partagé entre tous les postes : elle ne se supprime pas, elle s'annule par une
        écriture inverse (ANN-…). Export : XLSX (bouton « Exporter ») et vue imprimable (« Imprimer / PDF ») ; le PDF généré du poste n'est pas reproduit.
    </p>

    @if ($message)
        <p class="mb-md rounded-lg bg-success-container p-sm text-xs font-bold text-success-deep" data-message>{{ $message }}</p>
    @endif

    @if ($peutGerer)
        <div class="mb-md">
            <button type="button" wire:click="nouvelle" @disabled($cloture) data-action="nouvelle"
                    class="rounded-lg bg-brand-navy px-md py-sm text-xs font-bold text-white disabled:opacity-50">Nouvelle Écriture</button>
        </div>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Total Débit (Période)</p>
            <p class="text-page-title font-bold" data-kpi="debit">{{ $f::montant($totalDebit) }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Total Crédit (Période)</p>
            <p class="text-page-title font-bold" data-kpi="credit">{{ $f::montant($totalCredit) }}</p>
        </div>
        <div class="rounded-lg p-md {{ $equilibre ? 'bg-success-container text-success-deep' : 'bg-error-container text-error-deep' }}" data-kpi="equilibre">
            <p class="text-caption font-bold uppercase">Équilibre</p>
            <p class="text-section-title font-bold">{{ $equilibre ? 'Équilibré' : 'Écart de '.$f::montant(abs($totalDebit - $totalCredit)) }}</p>
        </div>
    </div>

    <h2 class="mb-sm text-section-title font-bold">Écritures de l'exercice {{ $annee }}</h2>
    <div class="mb-sm flex flex-wrap gap-sm">
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Libellé, compte, n° de pièce…" aria-label="Rechercher une écriture"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">
        <select wire:model.live="journal" aria-label="Filtrer par journal" class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
            <option value="">Journal : Tous</option>
            @foreach ($journaux as $code => $libelleJournal)
                <option value="{{ $code }}">{{ $code }} — {{ $libelleJournal }}</option>
            @endforeach
        </select>
    </div>

    <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs" data-table="journal">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">N° Pièce</th>
                    <th class="px-md py-sm">Date</th>
                    <th class="px-md py-sm">Jal</th>
                    <th class="px-md py-sm">Compte</th>
                    <th class="px-md py-sm">Libellé</th>
                    <th class="px-md py-sm text-right">Débit</th>
                    <th class="px-md py-sm text-right">Crédit</th>
                    <th class="px-md py-sm"></th>
                </tr>
            </thead>
            <tbody>
                @forelse ($lignes as $l)
                    @php($e = $l['ecriture'])
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }} {{ $l['premiere'] ? 'border-t-2 border-outline-variant' : '' }}" data-ligne="{{ $e->id }}" data-piece="{{ $e->pieceId }}">
                        <td class="px-md py-sm font-mono font-bold">
                            {{ $l['premiere'] ? ($e->numeroPiece ?? '—') : '' }}
                            @if ($l['premiere'] && $e->verrouillee)<span title="Exercice clôturé — écriture verrouillée" data-verrou>🔒</span>@endif
                            @if ($l['premiere'] && $annulees->has($e->pieceId))<span class="rounded-full bg-surface-zebra px-sm py-xs text-caption text-outline" data-annulee>Annulée</span>@endif
                            @if ($l['premiere'] && $e->contrepasseDe)<span class="rounded-full bg-surface-zebra px-sm py-xs text-caption text-outline" data-annulation>Annulation</span>@endif
                        </td>
                        <td class="px-md py-sm">{{ $l['premiere'] ? $e->date->format('d/m/Y') : '' }}</td>
                        <td class="px-md py-sm text-outline">{{ $e->journal }}</td>
                        <td class="px-md py-sm">{{ $e->compte }} — {{ $plan->get($e->compte)?->libelle ?? 'Compte inconnu' }}</td>
                        <td class="px-md py-sm">{{ $e->libelle }}
                            @if ($e->estAutomatique())<span title="Écriture générée automatiquement par {{ $e->venteRef ?? $e->achatRef }}" data-auto>⚡</span>@endif
                            @if ($l['premiere'])<span class="text-caption text-outline" data-origine>· {{ \App\Services\Comptabilite\Saisie::libellePoste($e->deviceId, $codes) }}</span>@endif
                        </td>
                        <td class="px-md py-sm text-right">{{ $f::ouTiret($e->debit) }}</td>
                        <td class="px-md py-sm text-right">{{ $f::ouTiret($e->credit) }}</td>
                        <td class="px-md py-sm text-right">
                            @if ($peutGerer && $l['premiere'] && ! $e->estAutomatique() && ! $e->verrouillee && ! $e->contrepasseDe && ! $annulees->has($e->pieceId))
                                <button type="button" wire:click="demanderAnnulation('{{ $e->pieceId }}')" data-action="annuler-piece"
                                        class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Annuler la pièce</button>
                            @endif
                        </td>
                    </tr>
                @empty
                    <tr><td colspan="8" class="px-md py-lg text-center text-outline">
                        {{ $aucuneEcriture ? "Aucune écriture sur l'exercice $annee. Chaque vente et chaque achat enregistré sur un poste génère automatiquement son écriture ici — rien à ressaisir." : 'Aucune écriture ne correspond à ces critères.' }}</td></tr>
                @endforelse
            </tbody>
            @if ($lignes->isNotEmpty())
                <tfoot class="bg-brand-navy text-white">
                    <tr data-totaux>
                        <td colspan="5" class="px-md py-sm font-bold">TOTAUX</td>
                        <td class="px-md py-sm text-right font-bold">{{ $f::nombre($totalDebit) }}</td>
                        <td class="px-md py-sm text-right font-bold">{{ $f::nombre($totalCredit) }}</td>
                        <td></td>
                    </tr>
                </tfoot>
            @endif
        </table>
    </div>

    <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($lignes as $l)
            @php($e = $l['ecriture'])
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-ligne="{{ $e->id }}">
                <p class="font-mono font-bold text-brand-navy">{{ $e->numeroPiece ?? '—' }} <span class="text-caption font-normal text-outline">{{ $e->journal }} · {{ $e->date->format('d/m/Y') }}</span></p>
                <p class="text-xs">{{ $e->compte }} — {{ $plan->get($e->compte)?->libelle ?? 'Compte inconnu' }}</p>
                <p class="text-xs text-outline">{{ $e->libelle }}</p>
                <p class="text-xs font-bold">Débit {{ $f::ouTiret($e->debit) }} · Crédit {{ $f::ouTiret($e->credit) }}</p>
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">
                {{ $aucuneEcriture ? "Aucune écriture sur l'exercice $annee." : 'Aucune écriture ne correspond à ces critères.' }}</p>
        @endforelse
    </div>

    @if ($formulaire)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-ecriture" data-modale="ecriture">
            <div class="max-h-full w-full max-w-lg overflow-y-auto rounded-lg bg-surface-card p-lg shadow-lg">
                <h2 id="titre-ecriture" class="mb-md text-modal-title font-bold">Nouvelle Écriture (Opération Diverse)</h2>
                @if ($erreur)
                    <p class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep" role="alert" data-erreur>{{ $erreur }}</p>
                @endif
                <label class="mb-sm block text-caption font-bold uppercase text-outline" for="jour">Date</label>
                <input id="jour" type="date" wire:model="jour" class="mb-md w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                <label class="mb-sm block text-caption font-bold uppercase text-outline" for="libelle">Libellé</label>
                <input id="libelle" type="text" wire:model="libelle" placeholder="Ex. Régularisation caisse" class="mb-md w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2">
                    <div>
                        <label class="mb-sm block text-caption font-bold uppercase text-outline" for="debit">Compte à débiter</label>
                        <select id="debit" wire:model="compteDebit" class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                            @foreach ($comptesActifs as $c)<option value="{{ $c->numero_compte }}">{{ $c->numero_compte }} — {{ $c->libelle }}</option>@endforeach
                        </select>
                    </div>
                    <div>
                        <label class="mb-sm block text-caption font-bold uppercase text-outline" for="credit">Compte à créditer</label>
                        <select id="credit" wire:model="compteCredit" class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                            @foreach ($comptesActifs as $c)<option value="{{ $c->numero_compte }}">{{ $c->numero_compte }} — {{ $c->libelle }}</option>@endforeach
                        </select>
                    </div>
                </div>
                <label class="mb-sm block text-caption font-bold uppercase text-outline" for="montant">Montant (FCFA)</label>
                <input id="montant" type="text" inputmode="decimal" wire:model="montant" class="mb-sm w-full rounded-lg border border-outline-variant px-md py-sm text-xs">
                <p class="mb-md text-caption text-outline">Le même montant est appliqué au Débit et au Crédit — l'équilibre est garanti par construction, pas de saisie séparée possible.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-bold">Annuler</button>
                    <button type="button" wire:click="enregistrer" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-bold text-white" data-action="enregistrer">Enregistrer l'Écriture</button>
                </div>
            </div>
        </div>
    @endif

    @if ($aAnnuler)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-annulation" data-modale="annulation">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-lg">
                <h2 id="titre-annulation" class="mb-md text-modal-title font-bold">Annuler cette pièce ?</h2>
                <p class="mb-md text-xs">Cette pièce est un fait partagé entre tous les postes : elle ne peut plus être effacée. Une pièce inverse (ANN-…) sera passée au Journal, à la date du jour.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-bold">Garder la pièce</button>
                    <button type="button" wire:click="confirmerAnnulation" class="rounded-lg bg-error-deep px-md py-sm text-xs font-bold text-white" data-action="confirmer-annulation">Annuler la pièce</button>
                </div>
            </div>
        </div>
    @endif
</div>
