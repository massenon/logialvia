@php
    $pct = fn (float $v): string => number_format($v, 1, ',', ' ').' %';
    $champ = 'mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm text-xs';
    $categories = $config['categories'];
    $colonnes = count($categories) > 3 ? 'sm:grid-cols-4' : 'sm:grid-cols-3';
    $mois = \App\Livewire\FicheEspece::MOIS;
@endphp
<div data-fiche="{{ $espece }}">
    {{-- En-tête --}}
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <h1 class="text-page-title font-bold">Fiche {{ $config['libelle'] }}</h1>
        <label class="flex items-center gap-sm text-xs font-semibold text-outline">Jour actif :
            <input type="date" wire:model.live="jour" aria-label="Jour actif" min="2020-01-01"
                   class="rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs font-normal text-on-surface">
        </label>
    </div>

    @if (count($onglets) > 0)
        <div class="mb-md flex gap-sm border-b border-outline-variant" role="tablist" data-onglets>
            @foreach ($onglets as $o)
                <button type="button" role="tab" wire:click="choisirOnglet('{{ $o }}')" aria-selected="{{ $o === $espece ? 'true' : 'false' }}"
                        class="px-md py-sm text-xs font-bold {{ $o === $espece ? 'border-b-2 border-brand-navy text-brand-navy' : 'text-outline' }}">
                    {{ \App\Support\FilieresElevage::configuration($o)['libelle'] }}
                </button>
            @endforeach
        </div>
    @endif

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif
    @if ($erreur)
        <p role="alert" class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep">{{ $erreur }}</p>
    @endif

    {{-- Rappel du cycle --}}
    <div class="mb-md flex flex-wrap items-center gap-sm rounded-lg border border-outline-variant bg-surface-card p-md" data-cycle>
        <span class="text-xs font-bold text-brand-navy">Rappel du Cycle :</span>
        @foreach ($config['etapes'] as $i => $etape)
            @if ($i > 0)<span class="text-outline" aria-hidden="true">→</span>@endif
            <span class="rounded-full px-sm py-xs text-caption font-bold
                {{ $i % 3 === 0 ? 'bg-brand-navy text-white' : ($i % 3 === 1 ? 'bg-brand-gold/30 text-brand-navy' : 'bg-success-container text-success-deep') }}">{{ $etape }}</span>
        @endforeach
    </div>

    {{-- Bande --}}
    <div class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md" data-bande>
        @if ($bande)
            <div class="flex flex-wrap items-center justify-between gap-sm">
                <div>
                    <p class="text-xs font-bold">Bande {{ $bande->code }} — mise en place le {{ \Carbon\CarbonImmutable::parse($bande->date_mise_en_bande)->format('d/m/Y') }}</p>
                    <p class="text-caption text-outline">
                        {{ collect([$bande->effectif_initial !== null ? $bande->effectif_initial.' sujets mis en place' : null, $bande->observations])->filter()->implode(' · ') }}
                    </p>
                    <p class="mt-xs inline-block rounded-full bg-brand-navy px-sm py-xs text-caption font-bold text-white" data-cycle-jour>Jour de cycle J{{ $jourDeCycle }}</p>
                </div>
                @if ($peutGerer)
                    <button type="button" wire:click="demanderCloture" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Clôturer la Bande</button>
                @endif
            </div>
            <p class="mt-sm text-caption text-outline">L'effectif mis en place est indicatif : l'effectif réel de la fiche reste calculé jour après jour depuis les saisies.</p>
        @else
            <div class="flex flex-wrap items-center justify-between gap-sm">
                <div>
                    <p class="text-xs font-bold">Aucune bande déclarée à cette date</p>
                    <p class="text-caption text-outline">Déclarez la mise en place pour suivre l'âge du lot.</p>
                </div>
                @if ($peutGerer)
                    <button type="button" wire:click="ouvrirBande" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Déclarer une Mise en Bande</button>
                @endif
            </div>
        @endif
    </div>

    {{-- KPI --}}
    <div class="mb-md grid grid-cols-2 gap-md md:grid-cols-4">
        <div class="rounded-lg border-l-4 border-brand-navy bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Effectif Vivant</p>
            <p class="text-page-title font-bold" data-kpi="effectif">{{ $kpi['effectif'] }}</p>
            @unless ($kpi['a_des_donnees'])<p class="text-caption text-outline">Aucune journée saisie ce mois-ci</p>@endunless
        </div>
        <div class="rounded-lg border-l-4 border-success-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">{{ $kpi['libelle_mature'] }} (Éligibles Vente)</p>
            <p class="text-page-title font-bold" data-kpi="matures">{{ $kpi['matures'] }}</p>
        </div>
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">{{ $kpi['libelle_immature'] }} (Immatures)</p>
            <p class="text-page-title font-bold" data-kpi="immatures">{{ $kpi['immatures'] }}</p>
        </div>
        <div class="rounded-lg border-l-4 border-error-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Taux de Mortalité (Cumul)</p>
            <p class="text-page-title font-bold" data-kpi="mortalite">{{ $pct($kpi['mortalite']) }}</p>
        </div>
    </div>

    {{-- Saisie journalière --}}
    <section class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md" data-saisie aria-labelledby="titre-saisie">
        <h2 id="titre-saisie" class="mb-sm text-section-title font-bold">Saisie Journalière — {{ $date->format('d/m/Y') }}</h2>

        <fieldset @disabled(! $peutGerer) class="m-0 min-w-0 border-0 p-0">
            <div class="grid grid-cols-1 gap-md sm:grid-cols-3">
                <label class="block text-xs font-semibold">{{ $config['libelle_achats'] }}
                    <input type="number" min="0" step="1" wire:model.live.debounce.400ms="achat" data-champ="achat" class="{{ $champ }}"></label>
                <label class="block text-xs font-semibold">{{ $config['libelle_naissances'] }}
                    <input type="number" min="0" step="1" wire:model.live.debounce.400ms="ne" data-champ="ne" class="{{ $champ }}"></label>
                <label class="block text-xs font-semibold">Ventes <span class="text-[9px] font-normal text-outline">(POS)</span>
                    <input type="number" value="{{ $venteDuJour }}" readonly data-champ="vente" class="{{ $champ }} bg-surface-zebra"></label>
            </div>

            <div class="mt-md rounded-lg border border-error-deep/20 bg-error-container p-sm">
                <p class="mb-xs text-xs font-bold uppercase text-error-deep">Morts par catégorie</p>
                <div class="grid grid-cols-2 gap-sm {{ $colonnes }}">
                    @foreach ($categories as $i => $categorie)
                        <label class="block text-xs font-semibold">{{ $categorie[0] }}
                            <input type="number" min="0" step="1" wire:model.live.debounce.400ms="morts.{{ $i }}" data-champ="morts-{{ $i }}" class="{{ $champ }}"></label>
                    @endforeach
                </div>
            </div>

            <div class="mt-md rounded-lg border border-brand-navy/20 bg-brand-navy/5 p-sm">
                <p class="mb-xs text-xs font-bold uppercase text-brand-navy">Dons par catégorie</p>
                <div class="grid grid-cols-2 gap-sm {{ $colonnes }}">
                    @foreach ($categories as $i => $categorie)
                        <label class="block text-xs font-semibold">{{ $categorie[0] }}
                            <input type="number" min="0" step="1" wire:model.live.debounce.400ms="dons.{{ $i }}" data-champ="dons-{{ $i }}" class="{{ $champ }}"></label>
                    @endforeach
                </div>
            </div>

            <div class="mt-md grid grid-cols-1 gap-md rounded-lg border border-outline-variant bg-surface-zebra p-md sm:grid-cols-2">
                <div>
                    <p class="text-xs font-bold">Effectif Final du Jour (calculé)</p>
                    <p class="text-caption text-outline">= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)</p>
                    <p class="text-page-title font-bold text-brand-navy" data-total="effectif">{{ $totaux['effectif_total'] }}</p>
                </div>
                <div>
                    <p class="text-xs font-bold">Taux de Mortalité du Jour</p>
                    <p class="text-caption text-outline">= (Morts du Jour ÷ Effectif J-1) × 100</p>
                    <p class="text-page-title font-bold text-error-deep" data-total="mortalite">{{ $pct($totaux['taux_mortalite']) }}</p>
                </div>
            </div>

            {{-- Écart déclaré avec le Dart : rationnement et prophylaxie du jour --}}
            <p class="mt-md rounded-lg bg-surface-zebra p-sm text-caption text-outline" data-ecart="rationnement">
                Le rationnement (provende) et la prophylaxie du jour sont disponibles sur le poste : les barèmes de ration et le calendrier de prophylaxie ne sont pas encore synchronisés.
            </p>

            @if ($oeufs !== null)
                <div class="mt-md rounded-lg border border-brand-gold/40 bg-surface-card p-md" data-oeufs>
                    <p class="mb-sm text-xs font-bold uppercase text-brand-navy">Suivi du Stock d'Œufs</p>
                    <div class="grid grid-cols-1 gap-md sm:grid-cols-3">
                        <div>
                            <p class="text-caption uppercase text-outline">Stock Hier (SRH)</p>
                            <p class="text-xs font-bold" data-oeufs="srh">{{ $srh }}</p>
                            <p class="text-caption text-outline">Stock Final de la veille</p>
                        </div>
                        <label class="block text-xs font-semibold">Œufs Pondus
                            <input type="number" min="0" step="1" wire:model.live.debounce.400ms="oeufsPondus" data-champ="oeufs-pondus" class="{{ $champ }}"></label>
                        <label class="block text-xs font-semibold">Œufs Cassés
                            <input type="number" min="0" step="1" wire:model.live.debounce.400ms="oeufsCasses" data-champ="oeufs-casses" class="{{ $champ }}">
                            @if ((int) $oeufsCasses > (int) $oeufsPondus)
                                <span class="text-caption text-error-deep">Ne peut dépasser les œufs pondus.</span>
                            @endif
                        </label>
                        <div>
                            <p class="text-caption uppercase text-outline">Total Stock (TS)</p>
                            <p class="text-xs font-bold" data-oeufs="ts">{{ $oeufs['total_stock'] }}</p>
                            <p class="text-caption text-outline">= (Pondus − Cassés) + SRH</p>
                        </div>
                        <label class="block text-xs font-semibold">Sorties (Plateaux)
                            <input type="number" min="0" step="1" wire:model.live.debounce.400ms="sortiesPlateaux" data-champ="oeufs-sorties" class="{{ $champ }}">
                            <span class="text-caption text-outline">{{ $oeufs['sorties_oeufs'] }} œufs ({{ \App\Support\CalculFicheJournaliere::OEUFS_PAR_PLATEAU }} par plateau)</span>
                        </label>
                        <div>
                            <p class="text-caption uppercase text-outline">Stock Final</p>
                            <p class="text-xs font-bold" data-oeufs="final">{{ $oeufs['stock_final'] }}</p>
                            <p class="text-caption text-outline">= TS − Sorties · devient le SRH de demain</p>
                        </div>
                    </div>
                </div>
            @endif

            <div class="mt-md grid grid-cols-1 gap-md sm:grid-cols-2">
                <label class="block text-xs font-semibold">Pesée totale du lot (g)
                    <input type="number" min="0" step="1" wire:model.live.debounce.400ms="poids" data-champ="poids" class="{{ $champ }}">
                    @if ($poidsMoyen !== null)<span class="text-caption text-outline" data-poids-moyen>Poids moyen : {{ $poidsMoyen }} g</span>@endif
                </label>
                <label class="block text-xs font-semibold">Observation de traitement
                    <input type="text" wire:model="observation" data-champ="observation" class="{{ $champ }}"></label>
            </div>

            <div class="mt-md flex flex-wrap items-center justify-between gap-sm">
                <label class="flex items-center gap-sm text-xs">
                    <input type="checkbox" wire:model="traitementValide" data-champ="traitement-valide" class="rounded border-outline-variant">
                    Traitement du jour validé</label>
                @if ($peutGerer)
                    <button type="button" wire:click="enregistrer" wire:loading.attr="disabled"
                            class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Enregistrer</button>
                @endif
            </div>
        </fieldset>
    </section>

    {{-- Historique du mois --}}
    <section class="rounded-lg border border-outline-variant bg-surface-card p-md" aria-labelledby="titre-historique">
        <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
            <h2 id="titre-historique" class="text-section-title font-bold">Historique du Mois — {{ $libelleMois }}</h2>
            <div class="inline-flex rounded-full border border-outline-variant bg-surface-card p-xs" role="group" aria-label="Densité d'affichage">
                <button type="button" wire:click="basculer(false)" data-bascule="quotidienne"
                        class="rounded-full px-md py-xs text-xs font-semibold {{ $hebdomadaire ? 'text-outline' : 'bg-brand-navy text-white' }}">Grille Quotidienne</button>
                <button type="button" wire:click="basculer(true)" data-bascule="hebdomadaire"
                        class="rounded-full px-md py-xs text-xs font-semibold {{ $hebdomadaire ? 'bg-brand-navy text-white' : 'text-outline' }}">Vue Hebdomadaire</button>
            </div>
        </div>

        @if (! $hebdomadaire)
            <div class="hidden overflow-x-auto rounded-lg border border-outline-variant sm:block">
                <table class="w-full text-xs" data-table="mensuel">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-md py-sm text-left">Date</th>
                            <th class="px-md py-sm text-center">Achat</th>
                            <th class="px-md py-sm text-center">Né</th>
                            <th class="px-md py-sm text-center">Vente</th>
                            <th class="px-md py-sm text-center">Morts</th>
                            <th class="px-md py-sm text-center">Dons</th>
                            <th class="px-md py-sm text-center">Effectif</th>
                        </tr>
                    </thead>
                    <tbody>
                        @for ($j = 1; $j <= $nombreJours; $j++)
                            @php($d = $journees[$j] ?? null)
                            @php($saisie = $d !== null && $d['is_recorded'])
                            @php($actif = $j === $date->day)
                            <tr wire:click="selectionnerJour({{ $j }})" data-jour="{{ $j }}" @if($actif) aria-current="date" @endif
                                class="cursor-pointer border-t border-outline-variant {{ $actif ? 'bg-brand-navy/10' : ($j % 2 === 0 ? 'bg-surface-zebra' : '') }} {{ $saisie ? '' : 'text-outline-variant' }}">
                                <td class="px-md py-xs font-bold {{ $actif ? 'text-brand-navy' : '' }}">{{ str_pad($j, 2, '0', STR_PAD_LEFT) }}/{{ $date->format('m') }}</td>
                                <td class="px-md py-xs text-center">{{ $saisie ? $d['achat'] : '—' }}</td>
                                <td class="px-md py-xs text-center">{{ $saisie ? $d['ne'] : '—' }}</td>
                                <td class="px-md py-xs text-center">{{ $saisie ? $d['vente'] : '—' }}</td>
                                <td class="px-md py-xs text-center">{{ $saisie ? array_sum($d['morts']) : '—' }}</td>
                                <td class="px-md py-xs text-center">{{ $saisie ? array_sum($d['dons']) : '—' }}</td>
                                <td class="px-md py-xs text-center font-bold">{{ $saisie ? $d['effectif'] : '—' }}</td>
                            </tr>
                        @endfor
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-xs sm:hidden" data-vue="cartes">
                @for ($j = 1; $j <= $nombreJours; $j++)
                    @php($d = $journees[$j] ?? null)
                    @php($saisie = $d !== null && $d['is_recorded'])
                    <button type="button" wire:click="selectionnerJour({{ $j }})" data-carte-jour="{{ $j }}"
                            class="rounded-lg border border-outline-variant p-sm text-left text-xs {{ $j === $date->day ? 'bg-brand-navy/10' : 'bg-surface-card' }}">
                        <span class="font-bold">{{ str_pad($j, 2, '0', STR_PAD_LEFT) }}/{{ $date->format('m') }}</span>
                        @if ($saisie)
                            <span class="text-outline"> — Achat {{ $d['achat'] }} · Né {{ $d['ne'] }} · Vente {{ $d['vente'] }} · Morts {{ array_sum($d['morts']) }} · Dons {{ array_sum($d['dons']) }} ·</span>
                            <span class="font-bold">Effectif {{ $d['effectif'] }}</span>
                        @else
                            <span class="text-outline"> — non saisi</span>
                        @endif
                    </button>
                @endfor
            </div>
        @else
            <div class="hidden overflow-x-auto rounded-lg border border-outline-variant sm:block">
                <table class="w-full text-xs" data-table="hebdomadaire">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-md py-sm text-left">Semaine</th>
                            <th class="px-md py-sm text-right">Cumul Achats</th>
                            <th class="px-md py-sm text-right">Cumul {{ mb_strtoupper($config['libelle_naissances']) }}</th>
                            <th class="px-md py-sm text-right">Cumul Morts</th>
                            <th class="px-md py-sm text-right">Cumul Ventes</th>
                            <th class="px-md py-sm text-right">Effectif fin de semaine</th>
                            <th class="px-md py-sm text-right">Taux mortalité semaine</th>
                            <th class="px-md py-sm text-left">Traitements</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($semaines as $s)
                            @php($vide = ! $s['a_des_journees_saisies'])
                            @php($notes = collect(range($s['premier_jour'], $s['dernier_jour']))->map(fn ($j) => trim((string) ($journees[$j]['traitement_obs'] ?? '')))->filter()->implode(' · '))
                            <tr class="border-t border-outline-variant {{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-semaine="{{ $s['numero'] }}">
                                <td class="px-md py-sm font-bold">Semaine {{ $s['numero'] }} ({{ $s['premier_jour'] }}-{{ $s['dernier_jour'] }} {{ mb_strtolower($mois[$date->month - 1]) }})</td>
                                <td class="px-md py-sm text-right">{{ $vide ? '—' : $s['cumul_achats'] }}</td>
                                <td class="px-md py-sm text-right">{{ $vide ? '—' : $s['cumul_naissances'] }}</td>
                                <td class="px-md py-sm text-right {{ ! $vide && $s['cumul_morts'] > 0 ? 'font-bold text-error-deep' : '' }}">{{ $vide ? '—' : $s['cumul_morts'] }}</td>
                                <td class="px-md py-sm text-right">{{ $vide ? '—' : $s['cumul_ventes'] }}</td>
                                <td class="px-md py-sm text-right font-bold">{{ $vide ? '—' : $s['effectif_fin'] }}</td>
                                <td class="px-md py-sm text-right font-semibold {{ ! $vide && ($s['taux_mortalite'] ?? 0) > 0 ? 'text-error-deep' : '' }}">{{ $vide || $s['taux_mortalite'] === null ? '—' : $pct($s['taux_mortalite']) }}</td>
                                <td class="px-md py-sm">{{ $notes === '' ? '—' : $notes }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($semaines as $s)
                    @php($vide = ! $s['a_des_journees_saisies'])
                    <article class="rounded-lg border border-outline-variant p-md text-xs" data-carte-semaine="{{ $s['numero'] }}">
                        <p class="font-bold">Semaine {{ $s['numero'] }} ({{ $s['premier_jour'] }}-{{ $s['dernier_jour'] }} {{ mb_strtolower($mois[$date->month - 1]) }})</p>
                        @if ($vide)
                            <p class="text-outline">Aucune journée saisie.</p>
                        @else
                            <p>Achats {{ $s['cumul_achats'] }} · Nés {{ $s['cumul_naissances'] }} · Morts {{ $s['cumul_morts'] }} · Ventes {{ $s['cumul_ventes'] }}</p>
                            <p class="font-bold">Effectif fin de semaine {{ $s['effectif_fin'] }}@if ($s['taux_mortalite'] !== null) · Mortalité {{ $pct($s['taux_mortalite']) }}@endif</p>
                        @endif
                    </article>
                @endforeach
            </div>
        @endif
    </section>

    {{-- Modale : déclarer une mise en bande --}}
    @if ($formulaireBande)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-bande">
            <form wire:submit="declarerBande" class="w-full max-w-sm rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-bande" class="mb-xs text-modal-title font-bold">Déclarer une Mise en Bande</h2>
                <p class="mb-md text-caption text-outline">Filière : {{ $config['libelle'] }}</p>
                <label class="mb-sm block text-xs font-semibold uppercase">Code de la bande *
                    <input type="text" wire:model="bandeCode" data-champ="bande-code" class="{{ $champ }} normal-case font-normal"></label>
                <p class="mb-sm text-caption text-outline">Proposé avec le préfixe par défaut ; le préfixe se règle aux Paramètres Élevage du poste.</p>
                <label class="mb-sm block text-xs font-semibold uppercase">Date de mise en place *
                    <input type="date" wire:model="bandeDate" data-champ="bande-date" class="{{ $champ }} normal-case font-normal"></label>
                <label class="mb-sm block text-xs font-semibold uppercase">Effectif mis en place
                    <input type="number" min="0" step="1" wire:model="bandeEffectif" placeholder="Facultatif" data-champ="bande-effectif" class="{{ $champ }} normal-case font-normal"></label>
                <p class="mb-sm text-caption text-outline">Indicatif : l'effectif de la fiche reste calculé depuis les saisies journalières.</p>
                <label class="block text-xs font-semibold uppercase">Observations
                    <input type="text" wire:model="bandeObservations" placeholder="Ex. Enclos E2, souche locale" data-champ="bande-observations" class="{{ $champ }} normal-case font-normal"></label>
                @if ($erreurBande)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreurBande }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Déclarer</button>
                </div>
            </form>
        </div>
    @endif

    {{-- Modale : clôturer la bande --}}
    @if ($confirmerCloture && $bande)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-cloture">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-cloture" class="mb-sm text-modal-title font-bold">Clôturer la Bande ?</h2>
                <p class="mb-xs text-xs"><strong>Bande {{ $bande->code }}</strong>, mise en place le {{ \Carbon\CarbonImmutable::parse($bande->date_mise_en_bande)->format('d/m/Y') }}.</p>
                <p class="mb-md text-xs text-outline">Le cycle s'arrête à aujourd'hui : les saisies journalières et l'effectif ne changent pas.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="cloturerBande" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Clôturer</button>
                </div>
            </div>
        </div>
    @endif
</div>
