@php
    $pct = fn (float $v): string => number_format($v, 1, ',', ' ').' %';
    $iconesModules = ['cuniculture' => 'cruelty_free', 'aviculture_classique' => 'egg_alt', 'pisciculture' => 'set_meal', 'heliciculture' => 'eco', 'ovins' => 'grass'];
    $couleursMortalite = ['critique' => 'text-error-deep', 'avertissement' => 'text-brand-gold', 'normal' => 'text-success-deep'];
@endphp
<div>
    <div class="mb-lg flex flex-wrap items-center justify-between gap-sm">
        <div>
            <h1 class="flex items-center gap-xs text-page-title font-bold text-brand-navy"><x-icone nom="monitoring" class="text-[24px]" />Dashboard Élevage</h1>
            <p class="mt-xs text-xs text-outline">Vue consolidée — filières actives et couveuse en un seul écran.</p>
        </div>
        <button type="button" onclick="window.print()" data-action="imprimer" class="flex items-center gap-xs rounded-full border border-outline-variant bg-white px-md py-sm text-xs font-bold text-brand-navy shadow-sm hover:bg-surface-zebra print:hidden">
            <x-icone nom="picture_as_pdf" class="text-[16px]" />Exporter PDF</button>
    </div>

    <div class="mb-lg grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3" data-grille="filieres">
        @foreach ($filieres as $f)
            @php $conf = \App\Support\FilieresElevage::configuration($f['espece']); $permanente = in_array($f['espece'], \App\Livewire\DashboardElevage::ESPECES_PERMANENTES, true); @endphp
            <a href="{{ $f['route'] }}" data-filiere="{{ $f['espece'] }}"
               class="block rounded-lg border bg-white p-md shadow-sm transition-all hover:border-brand-navy hover:shadow-md {{ $permanente ? 'border-outline-variant' : 'border-brand-gold/40' }}">
                <div class="mb-sm flex items-center justify-between">
                    <div class="flex items-center gap-xs"><x-icone :nom="$conf['icone']" class="text-[20px] text-brand-navy" /><h2 class="text-xs font-bold text-brand-navy">{{ $f['libelle'] }}</h2></div>
                    @unless ($permanente)<span class="rounded-full bg-brand-gold/20 px-xs py-0.5 text-caption font-bold text-brand-navy">Module Actif</span>@endunless
                </div>
                @if ($f['a_des_donnees'])
                    <div class="grid grid-cols-2 gap-sm text-xs">
                        <div><p class="text-outline">Effectif</p><p class="text-section-title font-bold" data-chiffre="effectif">{{ $f['effectif'] }}</p></div>
                        <div><p class="text-outline">Matures</p><p class="text-section-title font-bold text-success-deep" data-chiffre="matures">{{ $f['matures'] }}</p></div>
                        <div><p class="text-outline">{{ $f['libelle_jeunes'] }}</p><p class="text-section-title font-bold" data-chiffre="jeunes">{{ $f['jeunes'] }}</p></div>
                        <div><p class="text-outline">Mortalité</p><p class="text-section-title font-bold {{ $couleursMortalite[$f['niveau_mortalite']] }}" data-niveau="{{ $f['niveau_mortalite'] }}" data-chiffre="mortalite">{{ $pct($f['mortalite']) }}</p></div>
                    </div>
                @else
                    <p class="text-xs text-outline" data-vide>Aucune journée saisie pour cette filière. Les effectifs apparaîtront dès la première saisie sur sa fiche.</p>
                @endif
            </a>
        @endforeach

        <a href="/elevage/couveuse" data-carte="couveuse" class="block rounded-lg border border-outline-variant bg-white p-md shadow-sm transition-all hover:border-brand-navy hover:shadow-md">
            <div class="mb-sm flex items-center gap-xs"><x-icone nom="egg" class="text-[20px] text-brand-gold" /><h2 class="text-xs font-bold text-brand-navy">Couveuse</h2></div>
            <div class="grid grid-cols-2 gap-sm text-xs">
                <div><p class="text-outline">Cycles en cours</p><p class="text-section-title font-bold" data-couveuse="cycles">{{ $couveuse['cycles_en_cours'] }}</p></div>
                <div><p class="text-outline">Œufs chargés</p><p class="text-section-title font-bold" data-couveuse="oeufs">{{ $couveuse['oeufs_charges'] }}</p></div>
                <div><p class="text-outline">Taux Éclosion Moy.</p><p class="text-section-title font-bold" data-couveuse="taux">{{ $couveuse['taux_eclosion'] === null ? '—' : number_format($couveuse['taux_eclosion'], 1, ',', ' ').' %' }}</p></div>
                <div><p class="text-outline">Poussins Attendus</p><p class="text-section-title font-bold" data-couveuse="attendus">{{ $couveuse['poussins_attendus'] }}</p></div>
            </div>
        </a>

        @foreach ($apercus as $module => [$titre, $texte])
            <div class="flex flex-col justify-between rounded-lg border border-dashed border-outline-variant bg-surface-zebra p-md" data-apercu="{{ $module }}">
                <div class="mb-sm flex items-center justify-between">
                    <div class="flex items-center gap-xs opacity-60"><x-icone :nom="$iconesModules[$module] ?? 'pets'" class="text-[20px] text-outline" /><h2 class="text-xs font-bold text-outline">{{ $titre }} <span class="font-normal">(non activée)</span></h2></div>
                    <x-icone nom="lock" class="text-[18px] text-outline-variant" />
                </div>
                <p class="mb-sm text-caption text-outline">{{ $texte }}</p>
                @if ($peutParametrer)
                    <a href="/parametres/generaux" class="w-fit text-caption font-bold text-brand-navy underline">Activer depuis Paramètres →</a>
                @endif
            </div>
        @endforeach
    </div>

    <div class="mb-lg grid grid-cols-1 gap-md lg:grid-cols-2">
        <section class="rounded-lg border border-outline-variant bg-white p-md shadow-sm" data-panneau="gmq">
            <h2 class="mb-md text-xs font-bold text-brand-navy">Gain Moyen Quotidien (GMQ) par Espèce — 4 Dernières Semaines</h2>
            @if (count($gmq) === 0)
                <p class="text-xs text-outline" data-gmq="vide">Le GMQ se calcule à partir de deux pesées de la fiche sur les 4 dernières semaines (« Pesée totale du lot »). Aucune filière n'en a encore deux.</p>
            @else
                @php($gmqMax = max(1.0, (float) max(array_column($gmq, 'gmq'))))
                <ul class="flex flex-col gap-sm text-xs">
                    @foreach ($filieres as $f)
                        @if (isset($gmq[$f['espece']]))
                            @php($g = $gmq[$f['espece']])
                            <li data-gmq="{{ $f['espece'] }}">
                                <span class="font-semibold text-brand-navy">{{ $f['libelle'] }} : {{ number_format($g['gmq'], 1, ',', '') }} g/j</span>
                                <span class="text-outline">({{ (int) round($g['poids_initial_g']) }} g → {{ (int) round($g['poids_final_g']) }} g en {{ $g['jours'] }} j)</span>
                                <span class="mt-xs block h-2 rounded-full bg-surface-zebra"><span class="block h-2 rounded-full bg-brand-navy" style="width: {{ max(3, round($g['gmq'] / $gmqMax * 100)) }}%"></span></span>
                            </li>
                        @endif
                    @endforeach
                </ul>
            @endif
        </section>
        <section class="rounded-lg border border-outline-variant bg-white p-md shadow-sm" data-panneau="rappels">
            <h2 class="mb-md flex items-center gap-xs text-xs font-bold text-brand-navy"><x-icone nom="event_repeat" class="text-[18px] text-info-blue" />Rappels Vétérinaires à Venir</h2>
            @forelse ($rappels as $r)
                @php($retard = \App\Support\RetardDeSoin::estEnRetard($r, $aujourdhui))
                <a href="/elevage/soins" data-rappel="{{ $r->id }}" class="mb-sm flex items-center justify-between rounded-lg p-sm {{ $retard ? 'bg-error-container' : 'bg-surface-zebra hover:bg-brand-navy/5' }}">
                    <span>
                        <span class="block text-xs font-bold {{ $retard ? 'text-error-deep' : 'text-brand-navy' }}">{{ $r->type_soin }} — {{ $libellesEspeces[$r->espece] ?? $r->espece }}@if ($retard) (En retard)@endif</span>
                        <span class="block text-caption {{ $retard ? 'text-error-deep' : 'text-outline' }}">Prévu le {{ $r->date_prevue->format('d/m/Y') }}</span>
                    </span>
                    <x-icone nom="chevron_right" class="text-[16px] text-outline" />
                </a>
            @empty
                <p class="text-xs text-outline" data-rappel="vide">Aucun rappel : tous les soins sont effectués.</p>
            @endforelse
        </section>
    </div>

    <div class="grid grid-cols-1 gap-md lg:grid-cols-2">
        <section class="rounded-lg border border-outline-variant bg-white p-md shadow-sm" data-panneau="alertes">
            <h2 class="mb-md flex items-center gap-xs text-xs font-bold text-brand-navy"><x-icone nom="coronavirus" class="text-[18px] text-error-deep" />Alertes Sanitaires du Jour</h2>
            @forelse ($alertes as $a)
                <a href="/elevage/soins" data-alerte="{{ $a->id }}" class="mb-sm flex items-start gap-sm rounded-lg bg-error-container p-sm hover:bg-error-container/70">
                    <x-icone nom="medical_information" class="text-[18px] text-error-deep" />
                    <p class="text-xs text-error-deep">{{ $a->type_soin }} — {{ $libellesEspeces[$a->espece] ?? $a->espece }} (En Retard, prévu le {{ $a->date_prevue->format('d/m/Y') }})</p>
                </a>
            @empty
                <p class="text-xs text-outline" data-alerte="vide">Aucun soin en retard.</p>
            @endforelse
            {{-- Dépend du STOCK d'intrants : propre à chaque poste (décision du client) --}}
            <p class="mt-sm rounded-lg bg-surface-zebra p-sm text-caption text-outline opacity-60" data-stock-poste>Stocks d'intrants sous leur seuil : Disponible sur le poste (le stock est propre à chaque poste).</p>
        </section>

        <section class="rounded-lg border border-outline-variant bg-white p-md shadow-sm" data-panneau="bilan">
            <h2 class="mb-md flex items-center gap-xs text-xs font-bold text-brand-navy"><x-icone nom="query_stats" class="text-[18px] text-success-deep" />Bilan Économique Élevage (Mois)</h2>
            <div class="grid grid-cols-2 gap-md">
                <div class="rounded-lg bg-surface-zebra p-sm">
                    <p class="text-caption font-bold uppercase text-outline">Revenus Élevage</p>
                    <p class="text-modal-title font-extrabold text-success-deep" data-bilan="revenus">{{ number_format($revenus, 0, ',', ' ') }} <span class="text-xs font-normal">FCFA</span></p>
                </div>
                <div class="rounded-lg bg-surface-zebra p-sm">
                    <p class="text-caption font-bold uppercase text-outline">Coûts Élevage</p>
                    <p class="text-modal-title font-extrabold text-error-deep" data-bilan="couts">—</p>
                </div>
            </div>
            <div class="mt-md rounded-lg bg-brand-gold/10 p-sm">
                <p class="text-caption font-bold uppercase text-outline">Marge nette élevage</p>
                <p class="text-modal-title font-extrabold text-brand-navy" data-bilan="marge">—</p>
            </div>
            <p class="mt-sm text-xs text-outline">Revenus = ventes d'activité Avicole du mois. Les coûts (intrants provende + vétérinaire) proviendront du module Achats & Commandes, non encore disponible — la marge ne peut donc pas être calculée.</p>
        </section>
    </div>
</div>
