@php
    $pct = fn (float $v): string => number_format($v, 1, ',', ' ').' %';
    $champ = 'mt-xs h-10 w-full rounded-lg border border-outline-variant bg-white px-md text-sm';
    $etiquette = 'block text-[12px] font-bold uppercase text-brand-navy';
    $carteKpi = 'rounded-lg border border-outline-variant border-l-4 bg-white p-md shadow-sm';
    $categories = $config['categories'];
    $colonnes = count($categories) > 3 ? 'sm:grid-cols-4' : 'sm:grid-cols-3';
    $mois = \App\Livewire\FicheEspece::MOIS;
@endphp
<div data-fiche="{{ $espece }}">
    {{-- En-tête (maquette fiche-goliaths.html) --}}
    <div class="mb-lg flex flex-col gap-sm border-b border-outline-variant pb-md lg:flex-row lg:items-center lg:justify-between">
        <div>
            <h1 class="flex items-center gap-xs text-xl font-bold text-on-surface lg:text-2xl">
                <x-icone nom="pets" class="text-[26px] text-brand-navy" />Fiche {{ $config['libelle'] }}
            </h1>
            <p class="mt-xs text-xs text-outline">Suivi de croissance — de la naissance à la maturité commerciale, jour après jour.</p>
        </div>
        <div class="flex flex-wrap items-center gap-xs print:hidden">
            <button type="button" onclick="window.print()" data-action="imprimer" class="flex items-center gap-xs rounded-full border border-outline-variant bg-white px-md py-2 text-xs font-bold text-brand-navy shadow-sm hover:bg-surface-zebra">
                <x-icone nom="picture_as_pdf" class="text-[18px]" />Imprimer / PDF</button>
            @can('export-elevage')
                <button type="button" wire:click="exporter" data-action="exporter" class="flex items-center gap-xs rounded-full border border-outline-variant bg-white px-md py-2 text-xs font-bold text-brand-navy shadow-sm hover:bg-surface-zebra">Exporter (XLSX)</button>
            @endcan
            <label class="flex items-center gap-xs rounded-lg border border-outline-variant bg-white px-sm py-1 shadow-sm">
                <x-icone nom="calendar_month" class="text-[18px] text-brand-navy" />
                <span class="sr-only">Jour actif</span>
                <input type="date" wire:model.live="jour" aria-label="Jour actif" min="2020-01-01"
                       class="cursor-pointer border-0 p-1 text-xs font-bold text-brand-navy outline-none focus:ring-0">
            </label>
        </div>
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

    {{-- Fiche modifiée ailleurs : aucune saisie n'est perdue, la personne choisit --}}
    @if ($modifieeAilleurs)
        <div class="mb-md rounded-lg border border-brand-gold bg-brand-gold/10 p-md" data-divergence role="alert">
            <p class="text-xs font-bold text-brand-navy">Fiche du {{ $date->format('d/m/Y') }} modifiée ailleurs</p>
            <p class="mb-sm text-caption text-outline">Un autre poste a saisi ce jour sans voir la version courante. Aucune saisie n'est perdue : choisissez la version à garder.</p>
            <div class="flex flex-col gap-sm">
                @foreach ($versions as $i => $v)
                    <div class="flex flex-wrap items-center justify-between gap-sm rounded-lg border border-outline-variant bg-surface-card p-sm" data-version="{{ $i }}">
                        <div class="text-xs">
                            <p class="font-bold text-brand-navy">{{ $v['origine'] }} — saisie le {{ \Carbon\CarbonImmutable::parse($v['instant'])->setTimezone(config('logialvia.fuseau'))->format('d/m/Y H:i') }}</p>
                            <p>Entrées {{ $v['journee']['achat'] + $v['journee']['ne'] }} · morts {{ array_sum($v['journee']['morts']) }} · effectif {{ $v['journee']['effectif'] }}@if ($v['journee']['poids_general_g'] !== null) · pesée {{ $v['journee']['poids_general_g'] }} g @endif @if (trim((string) $v['journee']['traitement_obs']) !== '') · « {{ $v['journee']['traitement_obs'] }} »@endif</p>
                        </div>
                        @if ($peutGerer)
                            <button type="button" wire:click="garderVersion({{ $i }})" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Garder celle-ci</button>
                        @endif
                    </div>
                @endforeach
            </div>
        </div>
    @endif

    {{-- Chaîne d'effectifs incohérente --}}
    @if (count($joursIncoherents) > 0)
        <div class="mb-md flex flex-wrap items-center justify-between gap-sm rounded-lg border border-brand-gold bg-brand-gold/10 p-md" data-chaine role="alert">
            <p class="text-xs">{{ count($joursIncoherents) }} jour{{ count($joursIncoherents) > 1 ? 's' : '' }} dont l'effectif ne découle pas de la veille (fiche d'un autre poste arrivée sans recalcul), à partir du {{ \Carbon\CarbonImmutable::parse($joursIncoherents[0]['jour'])->format('d/m/Y') }}.</p>
            @if ($peutGerer)
                <button type="button" wire:click="recalculerChaine" class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Recalculer la chaîne</button>
            @endif
        </div>
    @endif

    {{-- Rappel du cycle --}}
    <div class="mb-lg flex flex-wrap items-center gap-sm rounded-lg border border-outline-variant bg-white p-md" data-cycle>
        <x-icone nom="event_repeat" class="text-[20px] text-brand-navy" />
        <span class="text-xs font-bold text-brand-navy">Rappel du Cycle :</span>
        @foreach ($config['etapes'] as $i => $etape)
            @if ($i > 0)<x-icone nom="arrow_forward" class="text-[15px] text-outline" />@endif
            <span class="rounded-full px-sm py-1 text-[11px] font-bold
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
                    <div class="flex flex-wrap gap-sm">
                        <button type="button" wire:click="ouvrirRecodage" data-action="recoder" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Recoder la Bande</button>
                        <button type="button" wire:click="demanderCloture" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Clôturer la Bande</button>
                    </div>
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
    <div class="mb-lg grid grid-cols-2 gap-md md:grid-cols-4">
        <div class="{{ $carteKpi }} border-l-brand-navy">
            <div class="flex items-start justify-between"><span class="text-[12px] font-bold uppercase text-outline">Effectif Vivant</span><x-icone nom="pets" class="text-[18px] text-brand-navy" /></div>
            <span class="mt-xs block text-lg font-extrabold text-on-surface md:text-2xl" data-kpi="effectif">{{ $kpi['effectif'] }}</span>
            @unless ($kpi['a_des_donnees'])<p class="text-caption text-outline">Aucune journée saisie ce mois-ci</p>@endunless
        </div>
        <div class="{{ $carteKpi }} border-l-success-deep">
            <div class="flex items-start justify-between"><span class="text-[12px] font-bold uppercase text-outline">{{ $kpi['libelle_mature'] }} (Éligibles Vente)</span><x-icone nom="verified" class="text-[18px] text-success-deep" /></div>
            <span class="mt-xs block text-lg font-extrabold text-on-surface md:text-2xl" data-kpi="matures">{{ $kpi['matures'] }}</span>
        </div>
        <div class="{{ $carteKpi }} border-l-brand-gold">
            <div class="flex items-start justify-between"><span class="text-[12px] font-bold uppercase text-outline">{{ $kpi['libelle_immature'] }} (Immatures)</span><x-icone nom="child_care" class="text-[18px] text-brand-gold" /></div>
            <span class="mt-xs block text-lg font-extrabold text-on-surface md:text-2xl" data-kpi="immatures">{{ $kpi['immatures'] }}</span>
        </div>
        <div class="{{ $carteKpi }} {{ ['critique' => 'border-l-error-deep', 'avertissement' => 'border-l-brand-gold', 'normal' => 'border-l-success-deep'][$kpi['niveau_mortalite']] }}" data-niveau-mortalite="{{ $kpi['niveau_mortalite'] }}">
            <div class="flex items-start justify-between"><span class="text-[12px] font-bold uppercase text-outline">Taux de Mortalité (Cumul)</span><x-icone nom="trending_down" class="text-[18px] text-error-deep" /></div>
            <span class="mt-xs block text-lg font-extrabold text-on-surface md:text-2xl" data-kpi="mortalite">{{ $pct($kpi['mortalite']) }}</span>
        </div>
    </div>

        {{-- Saisie journalière --}}
    <section class="mb-lg rounded-lg border border-outline-variant bg-white p-md shadow-sm lg:p-lg" data-saisie aria-labelledby="titre-saisie">
        <div class="mb-md flex flex-wrap items-center justify-between gap-xs border-b border-outline-variant pb-sm">
            <div class="flex items-center gap-xs">
                <x-icone nom="edit_note" class="text-[24px] text-brand-navy" />
                <h2 id="titre-saisie" class="text-base font-bold text-brand-navy">Saisie Journalière — {{ $date->format('d/m/Y') }}@if ($bande) <span class="font-black text-brand-gold">· Jour {{ $jourDeCycle }}</span>@endif</h2>
            </div>
            <label class="flex items-center gap-xs print:hidden">
                <span class="text-xs font-semibold text-outline">Changer de date :</span>
                <input type="date" wire:model.live="jour" aria-label="Changer de date" min="2020-01-01"
                       class="h-9 cursor-pointer rounded-lg border border-outline-variant bg-surface-zebra px-md text-xs font-bold text-brand-navy">
            </label>
        </div>

        <fieldset @disabled(! $peutGerer) class="m-0 min-w-0 space-y-md border-0 p-0">
            <div class="grid grid-cols-2 gap-md sm:grid-cols-3">
                <label class="{{ $etiquette }}">{{ $config['libelle_achats'] }}
                    <input type="number" min="0" step="1" wire:model.live.debounce.400ms="achat" data-champ="achat" class="{{ $champ }}"></label>
                <label class="{{ $etiquette }}">{{ $config['libelle_naissances'] }}
                    <input type="number" min="0" step="1" wire:model.live.debounce.400ms="ne" data-champ="ne" class="{{ $champ }}"></label>
                <label class="{{ $etiquette }}">Ventes <span class="text-[9px] font-normal normal-case text-outline">(POS)</span>
                    <input type="number" value="{{ $venteDuJour }}" readonly data-champ="vente" class="{{ $champ }} cursor-not-allowed bg-surface-zebra text-outline"></label>
            </div>

            {{-- Morts et dons par catégorie : compteurs − / + (la saisie au clavier reste possible) --}}
            @foreach ([['morts', 'skull', 'Morts par catégorie', 'border-error-deep/20 bg-error-container/40', 'text-error-deep'], ['dons', 'redeem', 'Dons par catégorie', 'border-brand-navy/20 bg-brand-navy/5', 'text-brand-navy']] as [$groupe, $icone, $titre, $teinte, $couleur])
                <div class="rounded-lg border p-sm {{ $teinte }}" data-groupe="{{ $groupe }}">
                    <p class="mb-xs flex items-center gap-xs text-xs font-bold uppercase {{ $couleur }}"><x-icone :nom="$icone" class="text-[16px]" />{{ $titre }}</p>
                    <div class="grid grid-cols-2 gap-sm {{ $colonnes }}">
                        @foreach ($categories as $i => $categorie)
                            @php($valeur = (int) (($groupe === 'morts' ? $morts[$i] : $dons[$i]) ?? 0))
                            <div>
                                <span class="mb-xs block text-center text-[9px] font-bold uppercase text-outline">{{ $categorie[0] }}</span>
                                <div class="flex items-center overflow-hidden rounded-lg border border-outline-variant bg-white">
                                    <button type="button" wire:click="$set('{{ $groupe }}.{{ $i }}', {{ max(0, $valeur - 1) }})" aria-label="Moins {{ $categorie[0] }}" class="h-9 w-8 bg-surface-zebra font-bold text-brand-navy">−</button>
                                    <input type="number" min="0" step="1" wire:model.live.debounce.400ms="{{ $groupe }}.{{ $i }}" data-champ="{{ $groupe }}-{{ $i }}" aria-label="{{ $titre }} : {{ $categorie[0] }}"
                                           class="h-9 w-full border-0 px-0 text-center text-sm font-bold [appearance:textfield] focus:ring-0 [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none">
                                    <button type="button" wire:click="$set('{{ $groupe }}.{{ $i }}', {{ $valeur + 1 }})" aria-label="Plus {{ $categorie[0] }}" class="h-9 w-8 bg-surface-zebra font-bold text-brand-navy">+</button>
                                </div>
                            </div>
                        @endforeach
                    </div>
                </div>
            @endforeach

            <div class="space-y-md border-t border-outline-variant pt-md">
                <div class="grid grid-cols-1 gap-md rounded-lg border border-outline-variant bg-surface-zebra p-md sm:grid-cols-2">
                    <div>
                        <p class="text-[12px] font-bold uppercase text-brand-navy">Effectif Final du Jour (calculé)</p>
                        <p class="text-[12px] text-outline">= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)</p>
                        <p class="mt-1 flex h-10 items-center rounded-lg bg-white px-md text-base font-black text-brand-navy shadow-sm" data-total="effectif">{{ $totaux['effectif_total'] }}</p>
                    </div>
                    <div>
                        <p class="text-[12px] font-bold uppercase text-brand-navy">Taux de Mortalité du Jour (%)</p>
                        <p class="text-[12px] text-outline">= (Morts du Jour ÷ Effectif J-1) × 100</p>
                        <p class="mt-1 flex h-10 items-center rounded-lg bg-white px-md text-base font-black text-error-deep shadow-sm" data-total="mortalite">{{ $pct($totaux['taux_mortalite']) }}</p>
                    </div>
                </div>

                {{-- Contrôle de vraisemblance d'expert --}}
                @if (count($controle['erreurs']) + count($controle['avertissements']) > 0)
                    <div class="flex flex-col gap-xs text-caption" data-controle>
                        @foreach ($controle['erreurs'] as $e)
                            <p role="alert" class="text-error-deep" data-controle-erreur>{{ $e }}</p>
                        @endforeach
                        @foreach ($controle['avertissements'] as $a)
                            <p class="text-brand-gold" data-controle-avertissement>{{ $a }}</p>
                        @endforeach
                    </div>
                @endif

                {{-- Rationnement (provende) : barèmes synchronisés ; le stock reste propre à chaque poste --}}
                <div data-rationnement>
                    <p class="mb-xs flex items-center gap-xs text-xs font-bold uppercase text-brand-navy"><x-icone nom="restaurant" class="text-[16px] text-brand-gold" />Rationnement &amp; Provende Servie par Espèces (en Grammes g/j)</p>
                    <div class="overflow-hidden rounded-lg border border-outline-variant bg-white shadow-sm">
                        <table class="w-full text-xs">
                            <thead class="border-b border-outline-variant bg-surface-zebra text-outline">
                                <tr><th class="px-md py-xs text-left">Catégorie</th><th class="px-md py-xs text-center">Effectif</th><th class="px-md py-xs text-center">Ration (g/tête/j)</th><th class="px-md py-xs text-right">Provende servie (g)</th></tr>
                            </thead>
                            <tbody class="divide-y divide-outline-variant/60">
                                @foreach ($categories as $i => $categorie)
                                    <tr class="{{ $i % 2 === 1 ? 'bg-surface-zebra' : '' }}" data-ration="{{ $i }}">
                                        <td class="px-md py-xs font-bold text-brand-navy">{{ $categorie[0] }}</td>
                                        <td class="px-md py-xs text-center">{{ $totaux['par_categorie'][$i] ?? 0 }}</td>
                                        <td class="px-md py-xs text-center font-mono">{{ $rations[$i] }}</td>
                                        <td class="px-md py-xs text-right font-mono font-bold text-brand-navy">{{ ($totaux['par_categorie'][$i] ?? 0) * $rations[$i] }}</td>
                                    </tr>
                                @endforeach
                            </tbody>
                        </table>
                        <p class="border-t border-brand-gold/30 bg-brand-gold/10 px-md py-xs text-xs font-bold text-brand-navy" data-provende>Provende du jour : {{ number_format($provende['grammes'], 0, ',', ' ') }} g ({{ number_format($provende['grammes'] / 1000, 1, ',', ' ') }} kg)</p>
                    </div>
                    @if (in_array($espece, \App\Support\FilieresElevage::RATION_AU_POIDS_VIF, true))
                        <p class="mt-xs text-caption {{ $provende['sur_poids_vif'] ? 'text-success-deep' : 'text-outline' }}" data-mode-provende>
                            @if ($provende['sur_poids_vif'])
                                Poids moyen {{ number_format($provende['poids_moyen_g'], 0, ',', ' ') }} g, taux {{ str_replace('.', ',', (string) $provende['taux_pourcent']) }} % du poids vif : provende calculée sur le poids vif.
                            @else
                                Ration indicative par tête : saisissez une pesée pour calculer la provende sur le poids vif.
                            @endif
                        </p>
                    @endif
                    {{-- Dépend du STOCK d'intrants : propre à chaque poste (décision du client) --}}
                    <p class="mt-xs rounded-lg bg-surface-zebra p-sm text-caption text-outline opacity-60" data-stock-poste>Provende en stock et autonomie : Disponible sur le poste (le stock d'intrants est propre à chaque poste).</p>
                </div>
            </div>

            @if ($oeufs !== null)
                <div class="rounded-lg border border-brand-gold/40 bg-white p-md" data-oeufs>
                    <p class="mb-sm text-xs font-bold uppercase text-brand-navy">Suivi du Stock d'Œufs</p>
                    <div class="grid grid-cols-1 gap-md sm:grid-cols-3">
                        <div>
                            <p class="text-caption uppercase text-outline">Stock Hier (SRH)</p>
                            <p class="text-xs font-bold" data-oeufs="srh">{{ $srh }}</p>
                            <p class="text-caption text-outline">Stock Final de la veille</p>
                        </div>
                        <label class="{{ $etiquette }}">Œufs Pondus
                            <input type="number" min="0" step="1" wire:model.live.debounce.400ms="oeufsPondus" data-champ="oeufs-pondus" class="{{ $champ }}"></label>
                        <label class="{{ $etiquette }}">Œufs Cassés
                            <input type="number" min="0" step="1" wire:model.live.debounce.400ms="oeufsCasses" data-champ="oeufs-casses" class="{{ $champ }}">
                            @if ((int) $oeufsCasses > (int) $oeufsPondus)
                                <span class="text-caption normal-case text-error-deep">Ne peut dépasser les œufs pondus.</span>
                            @endif
                        </label>
                        <div>
                            <p class="text-caption uppercase text-outline">Total Stock (TS)</p>
                            <p class="text-xs font-bold" data-oeufs="ts">{{ $oeufs['total_stock'] }}</p>
                            <p class="text-caption text-outline">= (Pondus − Cassés) + SRH</p>
                        </div>
                        <label class="{{ $etiquette }}">Sorties (Plateaux)
                            <input type="number" min="0" step="1" wire:model.live.debounce.400ms="sortiesPlateaux" data-champ="oeufs-sorties" class="{{ $champ }}">
                            <span class="text-caption font-normal normal-case text-outline">{{ $oeufs['sorties_oeufs'] }} œufs ({{ \App\Support\CalculFicheJournaliere::OEUFS_PAR_PLATEAU }} par plateau)</span>
                        </label>
                        <div>
                            <p class="text-caption uppercase text-outline">Stock Final</p>
                            <p class="text-xs font-bold" data-oeufs="final">{{ $oeufs['stock_final'] }}</p>
                            <p class="text-caption text-outline">= TS − Sorties · devient le SRH de demain</p>
                        </div>
                    </div>
                </div>
            @endif

            {{-- Pesée : poids général, échantillon (= effectif final), poids moyen --}}
            <div class="grid grid-cols-1 gap-md border-t border-outline-variant pt-md md:grid-cols-3">
                <label class="{{ $etiquette }}">Pesée totale du lot (g)
                    <input type="number" min="0" step="1" wire:model.live.debounce.400ms="poids" placeholder="ex : 3500" data-champ="poids" class="{{ $champ }} font-bold"></label>
                <div>
                    <span class="{{ $etiquette }}">Taille Échantillon <span class="font-normal normal-case text-outline">(Auto = Effectif Final)</span></span>
                    <p class="mt-xs flex h-10 cursor-not-allowed items-center rounded-lg border border-outline-variant bg-surface-zebra px-md text-sm font-bold text-brand-navy">{{ $totaux['effectif_total'] }}</p>
                </div>
                <div>
                    <span class="{{ $etiquette }}">Poids Moyen Constaté</span>
                    <p class="mt-xs flex h-10 items-center rounded-lg border border-outline-variant bg-surface-zebra px-md text-sm font-bold text-brand-navy" data-poids-moyen>{{ $poidsMoyen !== null ? $poidsMoyen.' g' : '—' }}</p>
                </div>
            </div>

            {{-- Prophylaxie du jour (calendrier indexé sur le jour du cycle) + observation + validation --}}
            <div class="space-y-sm rounded-lg border border-info-blue/20 bg-info-blue/5 p-md" data-prophylaxie>
                <div class="flex items-center justify-between gap-sm">
                    <p class="flex items-center gap-xs text-xs font-bold text-brand-navy"><x-icone nom="vaccines" class="text-[18px] text-info-blue" />Traitements &amp; Prophylaxie Automatiques Prévus pour ce Jour</p>
                    @if ($bande)
                        <span class="rounded-full border px-sm py-0.5 text-[12px] font-bold {{ count($prophylaxieDuJour) === 0 ? 'border-outline-variant bg-surface-zebra text-outline' : 'border-brand-gold bg-brand-gold/30 text-brand-navy' }}">{{ count($prophylaxieDuJour) === 0 ? 'Libre' : count($prophylaxieDuJour).' Prévu(s)' }}</span>
                    @endif
                </div>
                <div class="rounded-lg border border-outline-variant bg-white p-sm">
                    @if (! $bande)
                        <p class="text-caption text-outline">Sans bande, aucune date de traitement n'est calculable : déclarez une mise en bande.</p>
                    @else
                        @forelse ($prophylaxieDuJour as $p)
                            <div class="flex flex-wrap items-center justify-between gap-sm border-b border-outline-variant/40 py-1 text-xs last:border-0" data-echeance="{{ $p['echeance']->id }}">
                                <p><strong class="text-brand-navy">{{ $p['echeance']->traitement }}</strong> — {{ $p['echeance']->produit }}@if ($p['echeance']->dose) ({{ $p['echeance']->dose }})@endif · J{{ $p['echeance']->jour_cycle }} du cycle</p>
                                @if ($p['soin'])
                                    <span class="rounded-full border border-success-deep bg-success-container px-sm py-0.5 text-[12px] font-bold text-success-deep">{{ $p['soin']->statut }}</span>
                                @elseif ($peutGerer)
                                    <span class="flex flex-wrap gap-xs">
                                        @foreach ($typesSoin as $type)
                                            <button type="button" wire:click="planifierEcheance('{{ $p['echeance']->id }}', '{{ $type }}')" class="rounded-lg border border-outline-variant px-sm py-xs text-caption font-semibold hover:bg-surface-zebra">Planifier : {{ $type }}</button>
                                        @endforeach
                                    </span>
                                @endif
                            </div>
                        @empty
                            <p class="py-1 text-xs italic text-outline">Aucun traitement prévu au J{{ $jourDeCycle }} du cycle.</p>
                        @endforelse
                        @if (count($prophylaxieBande) > 0)
                            <details class="mt-sm text-xs" data-calendrier-bande>
                                <summary class="cursor-pointer font-semibold text-brand-navy">Tout le calendrier de la bande ({{ count($prophylaxieBande) }})</summary>
                                @foreach ($prophylaxieBande as $p)
                                    <div class="flex flex-wrap items-center justify-between gap-sm border-t border-outline-variant py-xs" data-echeance-bande="{{ $p['echeance']->id }}">
                                        <p>{{ \Carbon\CarbonImmutable::parse($p['date_prevue'])->format('d/m/Y') }} · J{{ $p['echeance']->jour_cycle }} · {{ $p['echeance']->traitement }} — {{ $p['echeance']->produit }}</p>
                                        @if ($p['soin'])
                                            <span class="rounded-full bg-success-container px-sm py-xs text-caption font-bold text-success-deep">{{ $p['soin']->statut }}</span>
                                        @elseif ($peutGerer)
                                            <span class="flex flex-wrap gap-xs">
                                                @foreach ($typesSoin as $type)
                                                    <button type="button" wire:click="planifierEcheance('{{ $p['echeance']->id }}', '{{ $type }}')" class="rounded-lg border border-outline-variant px-sm py-xs text-caption hover:bg-surface-zebra">{{ $type }}</button>
                                                @endforeach
                                            </span>
                                        @endif
                                    </div>
                                @endforeach
                            </details>
                        @endif
                    @endif
                </div>
                <label class="{{ $etiquette }}">Observation de traitement <span class="font-normal normal-case text-outline">/ notes additionnelles de l'animalier</span>
                    <input type="text" wire:model="observation" placeholder="ex : RAS, léger picage enclos E2..." data-champ="observation" class="{{ $champ }} text-xs"></label>
                <div class="flex items-center justify-between border-t border-info-blue/20 pt-xs">
                    <label class="flex cursor-pointer items-center gap-xs">
                        <input type="checkbox" wire:model="traitementValide" data-champ="traitement-valide" class="h-4 w-4 rounded border-outline-variant text-brand-navy focus:ring-brand-navy">
                        <span class="text-xs font-bold text-brand-navy">Traitement du jour validé <span class="font-normal text-outline">(valider l'administration de tous ces traitements aujourd'hui)</span></span></label>
                </div>
            </div>

            @if ($peutGerer)
                <div class="flex justify-end pt-sm">
                    <button type="button" wire:click="enregistrer" wire:loading.attr="disabled"
                            class="flex items-center gap-xs rounded-lg bg-brand-navy px-lg py-sm text-sm font-bold text-white hover:bg-brand-navy-dark"><x-icone nom="save" class="text-[18px]" />Enregistrer la Saisie du Jour</button>
                </div>
            @endif
        </fieldset>
    </section>

    
    {{-- Historique du mois --}}
    <section class="mb-lg" aria-labelledby="titre-historique">
        <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
            <h2 id="titre-historique" class="text-sm font-bold text-brand-navy">Historique du Mois — {{ $libelleMois }}</h2>
            <div class="inline-flex items-center rounded-full border border-outline-variant bg-white p-1" role="group" aria-label="Densité d'affichage">
                <button type="button" wire:click="basculer(false)" data-bascule="quotidienne"
                        class="rounded-full px-md py-1.5 text-xs font-bold {{ $hebdomadaire ? 'text-outline' : 'bg-brand-navy text-white' }}">Grille Quotidienne</button>
                <button type="button" wire:click="basculer(true)" data-bascule="hebdomadaire"
                        class="rounded-full px-md py-1.5 text-xs font-bold {{ $hebdomadaire ? 'bg-brand-navy text-white' : 'text-outline' }}">Vue Hebdomadaire</button>
            </div>
        </div>

        @if (! $hebdomadaire)
            <div class="relative hidden overflow-hidden rounded-lg border border-outline-variant bg-white shadow-sm sm:block">
                <div class="overflow-x-auto">
                <table class="w-full text-xs" data-table="mensuel">
                    <thead>
                        <tr class="border-b border-outline-variant bg-surface-zebra text-[12px] font-bold uppercase text-outline">
                            <th rowspan="2" class="sticky left-0 border-r border-outline-variant bg-surface-zebra px-sm py-sm text-left">Date</th>
                            <th colspan="2" class="border-r border-outline-variant px-sm py-sm text-center">Entrées</th>
                            <th colspan="3" class="border-r border-outline-variant px-sm py-sm text-center">Sorties</th>
                            <th rowspan="2" class="border-r border-outline-variant px-sm py-sm text-right">Effectif Final</th>
                            <th rowspan="2" class="border-r border-outline-variant px-sm py-sm text-right">Taux Mort. %</th>
                            <th rowspan="2" class="border-r border-outline-variant px-sm py-sm text-right">Poids Moy. (g)</th>
                            <th rowspan="2" class="px-sm py-sm text-left">Traitements &amp; Prophylaxie</th>
                        </tr>
                        <tr class="border-b border-outline-variant bg-surface-zebra text-[12px] font-bold uppercase text-outline">
                            <th class="px-sm py-sm text-right">Achat</th>
                            <th class="border-r border-outline-variant px-sm py-sm text-right">Né</th>
                            <th class="px-sm py-sm text-right">Mort</th>
                            <th class="px-sm py-sm text-right">Vente</th>
                            <th class="border-r border-outline-variant px-sm py-sm text-right">Don</th>
                        </tr>
                    </thead>
                    <tbody>
                        @for ($j = 1; $j <= $nombreJours; $j++)
                            @php($d = $journees[$j] ?? null)
                            @php($saisie = $d !== null && $d['is_recorded'])
                            @php($actif = $j === $date->day)
                            @php($veille = $journees[$j - 1] ?? null)
                            @php($morts = $saisie ? array_sum($d['morts']) : 0)
                            <tr wire:click="selectionnerJour({{ $j }})" data-jour="{{ $j }}" @if($actif) aria-current="date" @endif
                                class="cursor-pointer border-b border-outline-variant hover:bg-brand-navy/5 {{ $actif ? 'bg-brand-gold/10' : '' }} {{ $saisie ? '' : 'italic text-outline/60' }}">
                                <td class="sticky left-0 bg-white px-sm py-xs font-semibold {{ $actif ? 'text-brand-navy' : '' }}">{{ str_pad($j, 2, '0', STR_PAD_LEFT) }}/{{ $date->format('m') }}</td>
                                <td class="px-sm py-xs text-right">{{ $saisie ? $d['achat'] : '—' }}</td>
                                <td class="border-r border-outline-variant px-sm py-xs text-right">{{ $saisie ? $d['ne'] : '—' }}</td>
                                <td class="px-sm py-xs text-right {{ $morts > 0 ? 'font-bold text-error-deep' : '' }}">{{ $saisie ? $morts : '—' }}</td>
                                <td class="px-sm py-xs text-right">{{ $saisie ? $d['vente'] : '—' }}</td>
                                <td class="border-r border-outline-variant px-sm py-xs text-right">{{ $saisie ? array_sum($d['dons']) : '—' }}</td>
                                <td class="border-r border-outline-variant px-sm py-xs text-right font-bold">{{ $saisie ? $d['effectif'] : '—' }}</td>
                                <td class="border-r border-outline-variant px-sm py-xs text-right">{{ $saisie && $veille !== null && $veille['is_recorded'] && $veille['effectif'] > 0 ? number_format($morts / $veille['effectif'] * 100, 1, ',', ' ').'%' : ($saisie ? '0,0%' : '—') }}</td>
                                <td class="border-r border-outline-variant px-sm py-xs text-right">{{ $saisie && ($d['poids_general_g'] ?? null) !== null && $d['effectif'] > 0 ? number_format($d['poids_general_g'] / $d['effectif'], 0, ',', ' ') : '—' }}</td>
                                <td class="px-sm py-xs text-left not-italic">{{ $saisie && trim((string) ($d['traitement_obs'] ?? '')) !== '' ? $d['traitement_obs'] : '—' }}</td>
                            </tr>
                        @endfor
                    </tbody>
                </table>
                </div>
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

    {{-- Modale : recoder la bande --}}
    @if ($formulaireRecodage && $bande)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-recodage">
            <form wire:submit="recoderBande" class="w-full max-w-sm rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-recodage" class="mb-xs text-modal-title font-bold">Recoder la bande {{ $bande->code }}</h2>
                <p class="mb-sm text-caption text-outline">Le code est unique par filière ; l'ancien code reste tracé dans les observations de la bande.</p>
                <label class="block text-xs font-semibold uppercase">Nouveau code *
                    <input type="text" wire:model="nouveauCode" data-champ="nouveau-code" class="{{ $champ }} normal-case font-normal"></label>
                @if ($erreurRecodage)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreurRecodage }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Recoder</button>
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
