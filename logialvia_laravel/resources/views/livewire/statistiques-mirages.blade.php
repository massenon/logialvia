<div>
    <div class="mb-xs flex flex-wrap items-center justify-between gap-sm">
        <div><h1 class="flex items-center gap-xs text-page-title font-bold text-brand-navy"><x-icone nom="fact_check" class="text-[24px]" />Statistiques des Mirages</h1><p class="mt-xs text-xs text-outline">Œufs clairs, gâtés et retenus, taux d'éclosion réel et pertes par lot et par filière.</p></div>
        <div class="flex flex-wrap gap-sm">
            <select wire:model.live="filtreEspece" aria-label="Filtrer par filière" class="rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs">
                <option value="">Toutes filières</option>
                @foreach ($especes as $cle => $e)
                    <option value="{{ $cle }}">{{ $e['libelle'] }}</option>
                @endforeach
            </select>
            <select wire:model.live="filtreMachine" aria-label="Filtrer par incubateur" class="rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs">
                <option value="">Tous incubateurs</option>
                @foreach ($machines as $m)
                    <option value="{{ $m->id }}">{{ $m->code }}</option>
                @endforeach
            </select>
        </div>
    </div>
    <p class="mb-md text-xs text-outline">Le mirage sépare ce que le taux d'éclosion confond : un œuf clair n'a jamais été fécondé, un œuf gâté a démarré puis s'est arrêté. Le premier accuse les reproducteurs, le second la conduite de la machine.</p>

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6" data-bloc="kpi">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Œufs Chargés</span><x-icone nom="egg" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="charges">{{ $agregat['charges'] }}</p>
            <p class="text-caption text-outline">{{ $agregat['lots'] }} lot(s)</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-error-deep bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Clairs (J+7)</span><x-icone nom="visibility" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="clairs">{{ $agregat['clairs'] }}</p>
            <p class="text-caption text-outline">Infertilité {{ \App\Support\SuiviIncubation::pourcentage($agregat['infertilite']) }} — reproducteurs</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-error-deep bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Gâtés (J+14)</span><x-icone nom="warning" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="gates">{{ $agregat['gates'] }}</p>
            <p class="text-caption text-outline">Mortalité embryonnaire {{ \App\Support\SuiviIncubation::pourcentage($agregat['mortalite']) }} — conduite</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Œufs Retenus</span><x-icone nom="verified" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="retenus">{{ $agregat['retenus'] }}</p>
            <p class="text-caption text-outline">Après les deux mirages</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-success-deep bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Taux d'Éclosion Réel</span><x-icone nom="percent" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="ter">{{ \App\Support\SuiviIncubation::pourcentage($agregat['ter']) }}</p>
            <p class="text-caption text-outline">Éclos ÷ œufs retenus</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-error-deep bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Perte Totale</span><x-icone nom="trending_down" class="text-[18px] text-brand-navy" /></div>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="perte">{{ \App\Support\SuiviIncubation::pourcentage($agregat['perte']) }}</p>
            <p class="text-caption text-outline">Sur les lots clôturés seulement</p>
        </div>
    </div>

    @if ($manquants->isNotEmpty())
        <p role="alert" class="mb-md rounded-lg bg-error-container p-md text-xs text-error-deep" data-bloc="manquants">
            {{ $manquants->count() }} lot(s) attendent un mirage échu : {{ $manquants->pluck('code_incubation')->join(', ') }}.
            Tant qu'il manque, les taux ci-dessus sont faux : un mirage oublié gonfle le dénominateur du TER et fait passer une bonne couvée pour une mauvaise.
        </p>
    @endif

    <h2 class="mb-sm flex items-center gap-xs text-section-title font-bold text-brand-navy"><x-icone nom="receipt_long" class="text-[20px]" />Détail par lot</h2>
    @if ($lots->isEmpty())
        <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun lot d'incubation ne correspond à ces filtres.</p>
    @else
        @php
            $avecTaux = fn (?int $valeur, ?float $taux) => $valeur === null ? 'Non mirés' : ($taux === null ? (string) $valeur : $valeur.'  ('.\App\Support\SuiviIncubation::pourcentage($taux).')');
        @endphp
        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs" data-table="mirages">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Lot</th>
                        <th class="px-md py-sm">Espèce</th>
                        <th class="px-md py-sm text-right">Chargés</th>
                        <th class="px-md py-sm text-right">Clairs J+7</th>
                        <th class="px-md py-sm text-right">Gâtés J+14</th>
                        <th class="px-md py-sm text-right">Retenus</th>
                        <th class="px-md py-sm text-right">Éclos</th>
                        <th class="px-md py-sm text-right">TER</th>
                        <th class="px-md py-sm text-right">Perte</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach ($lots as $l)
                        @php
                            $ter = \App\Support\SuiviIncubation::ter($l);
                            $perte = \App\Support\SuiviIncubation::tauxPerteLot($l);
                        @endphp
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-lot="{{ $l->code_incubation }}">
                            <td class="px-md py-sm font-bold">{{ $l->code_incubation }}</td>
                            <td class="px-md py-sm">{{ \App\Support\SuiviIncubation::libelleEspece($l->espece) }}</td>
                            <td class="px-md py-sm text-right">{{ $l->oeufs_couves }}</td>
                            <td class="px-md py-sm text-right {{ $l->oeufs_blancs_j7 === null ? 'text-outline' : 'text-error-deep' }}" data-cellule="clairs">{{ $avecTaux($l->oeufs_blancs_j7, \App\Support\SuiviIncubation::tauxInfertilite($l)) }}</td>
                            <td class="px-md py-sm text-right {{ $l->oeufs_gates_j14 === null ? 'text-outline' : 'text-error-deep' }}" data-cellule="gates">{{ $avecTaux($l->oeufs_gates_j14, \App\Support\SuiviIncubation::mortaliteEmbryonnaire($l)) }}</td>
                            <td class="px-md py-sm text-right font-bold">{{ \App\Support\SuiviIncubation::retenus($l) }}</td>
                            <td class="px-md py-sm text-right {{ $l->poussins_nes === null ? 'text-outline' : '' }}">{{ $l->poussins_nes ?? '—' }}</td>
                            <td class="px-md py-sm text-right font-bold {{ $ter === null ? 'text-outline' : 'text-success-deep' }}">{{ \App\Support\SuiviIncubation::pourcentage($ter) }}</td>
                            <td class="px-md py-sm text-right {{ $perte === null ? 'text-outline' : 'text-error-deep' }}">{{ \App\Support\SuiviIncubation::pourcentage($perte) }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </div>
        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @foreach ($lots as $l)
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-lot="{{ $l->code_incubation }}">
                    <p class="font-bold">{{ $l->code_incubation }} <span class="text-caption font-normal text-outline">{{ \App\Support\SuiviIncubation::libelleEspece($l->espece) }} · {{ $l->oeufs_couves }} œufs</span></p>
                    <p class="text-xs">Clairs J+7 : {{ $avecTaux($l->oeufs_blancs_j7, \App\Support\SuiviIncubation::tauxInfertilite($l)) }}</p>
                    <p class="text-xs">Gâtés J+14 : {{ $avecTaux($l->oeufs_gates_j14, \App\Support\SuiviIncubation::mortaliteEmbryonnaire($l)) }}</p>
                    <p class="text-xs">Retenus {{ \App\Support\SuiviIncubation::retenus($l) }} · Éclos {{ $l->poussins_nes ?? '—' }} · TER {{ \App\Support\SuiviIncubation::pourcentage(\App\Support\SuiviIncubation::ter($l)) }}</p>
                </article>
            @endforeach
        </div>
    @endif
</div>
