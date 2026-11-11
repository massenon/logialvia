@php
    /* Tableau de bord : transcrit de dashboard.html (structure, classes, tailles) et de dashboard_screen.dart (donnees). */
    $nb = fn ($v) => number_format((float) $v, 0, ',', ' ');
    $tresorerie ??= null; $depenses ??= null; $resultatNet ??= null; $stockCritique ??= null; $cheptel ??= null;
    $couveuse ??= null; $filieres ??= []; $alertes ??= []; $jours ??= []; $moisDepenses ??= []; $activites ??= [];
    $transactions ??= ['ventes' => [], 'achats' => [], 'depenses' => []];

    /* Export (Dart `_exports`) : ouvre l'ecran qui porte le PDF ; seuls les ecrans permis au compte sont proposes. */
    $exports = array_values(array_filter([
        ['État des Stocks', '/stocks'], ['État du Cycle d\'Élevage', '/elevage/dashboard'], ['État des Cycles de Couveuse', '/elevage/couveuse'],
        ['État des Recettes et Dépenses', '/rapports'], ['État des Créances et Avances', '/clients'], ['Rapport Mensuel de Synthèse', '/rapports'],
    ], fn ($e) => \App\Support\Navigation::accessible(auth()->user(), $e[1])));
    $pourcent = fn ($v) => $v === null ? '—' : rtrim(rtrim(number_format($v, 1, ',', ' '), '0'), ',').' %';

    /* Courbe CA vs Depenses : 6 derniers mois, echelle commune. */
    $courbe = null;
    if ($voirVentes) {
        $depParMois = collect($moisDepenses)->pluck('depenses', 'cle');
        $maxC = max(1, ...array_column($mois, 'ca'), ...($depenses !== null ? array_map(fn ($m) => (float) ($depParMois[$m['cle']] ?? 0), $mois) : [0]));
        $x0 = 40; $x1 = 580; $yh = 10; $yb = 190;
        $pas = count($mois) > 1 ? ($x1 - $x0 - 60) / (count($mois) - 1) : 0;
        $pt = fn ($i, $v) => [round($x0 + 30 + $i * $pas, 1), round($yb - ($v / ($maxC * 1.15)) * ($yb - $yh), 1)];
        $pointsCa = []; $pointsDep = [];
        foreach ($mois as $i => $m) {
            $pointsCa[] = $pt($i, $m['ca']) + [2 => $m];
            $pointsDep[] = $pt($i, (float) ($depParMois[$m['cle']] ?? 0));
        }
        $courbe = ['ca' => $pointsCa, 'dep' => $pointsDep];
    }

    /* Barres : 6 derniers jours. */
    $maxJ = max(1, ...array_map(fn ($j) => max($j['ca'], $j['depenses']), $jours ?: [['ca' => 0, 'depenses' => 0]]));
    $depSemaine = array_sum(array_column($jours, 'depenses'));
    $carte = 'rounded-lg border border-outline-variant bg-white p-md shadow-sm';
@endphp
<div x-data="{ onglet: 'ventes' }">
    <div class="mb-lg flex flex-col gap-md">
        <div class="flex flex-wrap items-center justify-between gap-sm">
            <div>
                <h1 class="text-page-title font-bold text-brand-navy" data-titre="bienvenue">Bienvenue, {{ auth()->user()->name }} 👋</h1>
                <p class="text-xs text-outline">Rapport généré le {{ $maintenant->format('d/m/Y') }} à {{ $maintenant->format('H:i') }} · ALLMANY ET COMPAGNIE</p>
            </div>
            <div class="flex w-full flex-col items-stretch gap-xs sm:w-auto sm:flex-row sm:items-center">
                @if ($voirVentes)
                    <a href="/ventes" class="flex items-center justify-center gap-xs whitespace-nowrap rounded-full bg-brand-navy px-md py-sm text-xs font-bold text-white shadow-sm hover:bg-brand-navy-dark">
                        <x-icone nom="point_of_sale" class="text-[16px]" />Enregistrer une Vente
                    </a>
                @endif
                @if ($voirElevage)
                    <a href="/elevage/dashboard" class="flex items-center justify-center gap-xs whitespace-nowrap rounded-full border border-outline-variant bg-white px-md py-sm text-xs font-bold text-brand-navy shadow-sm hover:bg-surface-zebra">
                        <x-icone nom="monitoring" class="text-[16px]" />Dashboard Élevage
                    </a>
                @endif
            </div>
        </div>

        @if ($voirVentes)
            <div class="flex flex-col items-stretch gap-sm rounded-lg border border-outline-variant bg-white p-sm sm:flex-row sm:items-center" x-data="{ etat: '' }">
                <div class="flex flex-1 items-center gap-xs">
                    <x-icone nom="calendar_month" class="text-[18px] text-outline" />
                    <input type="date" wire:model.live="debut" aria-label="Début de la période" class="flex-1 rounded-lg border border-outline-variant px-sm py-1.5 text-xs">
                    <span class="text-xs text-outline">au</span>
                    <input type="date" wire:model.live="fin" aria-label="Fin de la période" class="flex-1 rounded-lg border border-outline-variant px-sm py-1.5 text-xs">
                </div>
                @if (count($exports))
                    <div class="flex items-center gap-xs">
                        <select x-model="etat" aria-label="État ou rapport à exporter" class="flex-1 rounded-lg border border-outline-variant bg-white px-sm py-2 text-xs sm:w-56">
                            <option value="">-- Choisir un état / rapport --</option>
                            @foreach ($exports as [$libelle, $route])
                                <option value="{{ $route }}">{{ $libelle }}</option>
                            @endforeach
                        </select>
                        <button type="button" @click="etat && (window.location.href = etat)" :disabled="!etat"
                                class="flex items-center gap-1 rounded-lg bg-brand-navy px-md py-2 text-xs font-bold text-white hover:bg-brand-navy-dark disabled:opacity-50">
                            <x-icone nom="picture_as_pdf" class="text-[16px]" />PDF
                        </button>
                    </div>
                @endif
            </div>
            @unless ($periodeValide)
                <p role="alert" class="rounded-lg bg-error-container p-sm text-xs text-error-deep" data-alerte="periode">
                    Période invalide (le début doit précéder la fin) : le mois en cours est affiché.</p>
            @endunless
        @endif
    </div>

    {{-- Indicateurs --}}
    <div class="mb-lg">
        <div id="kpi-panel" class="grid grid-cols-2 gap-md xl:grid-cols-4">
            @if ($voirVentes)
                <div class="{{ $carte }} border-l-4 border-l-brand-navy" data-carte="ca">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Chiffre d'Affaires</span><x-icone nom="trending_up" class="text-[18px] text-brand-navy" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="ca">{{ $nb($ca['total']) }} <small class="text-xs font-normal">FCFA</small></span>
                    <p class="mt-xs text-caption text-outline">Avicole : <span data-kpi="ca-avicole">{{ $nb($ca['avicole']) }}</span> · Commerce annexe : <span data-kpi="ca-commerce">{{ $nb($ca['commerce']) }}</span></p>
                </div>
            @endif
            @if ($tresorerie !== null)
                <div class="{{ $carte }} border-l-4 border-l-info-blue" data-carte="tresorerie">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Trésorerie</span><x-icone nom="account_balance_wallet" class="text-[18px] text-info-blue" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="tresorerie">{{ $nb($tresorerie['total']) }} <small class="text-xs font-normal">FCFA</small></span>
                    <p class="mt-xs text-caption text-outline">Espèces : {{ $nb($tresorerie['especes']) }} · Mobile Money : {{ $nb($tresorerie['mobile']) }}</p>
                </div>
            @endif
            @if ($depenses !== null)
                <div class="{{ $carte }} border-l-4 border-l-brand-gold" data-carte="depenses">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Dépenses</span><x-icone nom="shopping_cart" class="text-[18px] text-brand-navy" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="depenses">{{ $nb($depenses['total']) }} <small class="text-xs font-normal">FCFA</small></span>
                    <p class="mt-xs text-caption text-outline">Dont intrants provende : {{ $nb($depenses['intrants']) }}</p>
                </div>
            @endif
            @if ($resultatNet !== null)
                <div class="{{ $carte }} border-l-4 border-l-success-deep" data-carte="resultat">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Résultat Net</span><x-icone nom="savings" class="text-[18px] text-success-deep" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="resultat">{{ $nb($resultatNet['montant']) }} <small class="text-xs font-normal">FCFA</small></span>
                    <p class="mt-xs text-caption text-outline">{{ $resultatNet['marge'] === null ? 'Marge nette : —' : 'Marge nette : '.$pourcent($resultatNet['marge']) }}</p>
                </div>
            @endif
            @if ($voirVentes)
                <div class="{{ $carte }} border-l-4 border-l-error-deep" data-carte="encours">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Soldes Restant Dus</span><x-icone nom="request_quote" class="text-[18px] text-error-deep" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="encours">{{ $nb($encours) }} <small class="text-xs font-normal">FCFA</small></span>
                    <p class="mt-xs text-caption text-outline" data-detail="encours">{{ $encoursNombre === 0 ? 'Aucune vente en avance non soldée' : "$encoursNombre vente(s) en avance non soldée(s)" }}</p>
                </div>
            @endif
            @if ($stockCritique !== null)
                <div class="{{ $carte }} border-l-4 border-l-error-deep" data-carte="stock">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Stock Critique</span><x-icone nom="warning" class="text-[18px] text-error-deep" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="stock">{{ $stockCritique['nombre'] }} <small class="text-xs font-normal">{{ $stockCritique['nombre'] > 1 ? 'intrants' : 'intrant' }}</small></span>
                    <p class="mt-xs text-caption text-outline">{{ $stockCritique['nombre'] === 0 ? 'Aucun intrant sous le seuil d\'alerte' : ($stockCritique['premier'] ?? '').' sous le seuil d\'alerte' }}</p>
                </div>
            @endif
            @if ($stockCritique === null && $voirStocks)
                {{-- Le stock d'intrants est propre à chaque poste : jamais un chiffre inventé ici. --}}
                <div class="rounded-lg border border-l-4 border-outline-variant border-l-outline-variant bg-surface-zebra p-md text-outline" data-carte-poste="Stock Critique">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase">Stock Critique</span><x-icone nom="warning" class="text-[18px]" /></div>
                    <span class="mt-xs block text-kpi-value font-extrabold">—</span>
                    <p class="mt-xs text-caption font-semibold">Disponible sur le poste</p>
                    <p class="text-caption">Le stock est propre à chaque poste.</p>
                </div>
            @endif
            @if ($cheptel !== null)
                <div class="{{ $carte }} border-l-4 border-l-brand-navy" data-carte="cheptel">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Effectif Cheptel</span><x-icone nom="pets" class="text-[18px] text-brand-navy" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="cheptel">{{ $nb($cheptel['effectif']) }} <small class="text-xs font-normal">têtes</small></span>
                    <p class="mt-xs text-caption text-outline">{{ $cheptel['libelle'] }}</p>
                </div>
            @endif
            @if ($couveuse !== null)
                <div class="{{ $carte }} border-l-4 border-l-brand-gold" data-carte="couveuse">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Cycles Couveuse en Cours</span><x-icone nom="egg" class="text-[18px] text-brand-gold" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="couveuse">{{ $couveuse['cycles'] }} <small class="text-xs font-normal">{{ $couveuse['cycles'] > 1 ? 'cycles' : 'cycle' }}</small></span>
                    <p class="mt-xs text-caption text-outline">{{ $couveuse['eclosionProchaine'] ?? 'Aucune éclosion prévue prochainement' }}</p>
                </div>
            @endif
            @if ($voirVentes)
                <div class="{{ $carte }} border-l-4 border-l-info-blue" data-carte="clients">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Clients Enregistrés</span><x-icone nom="person" class="text-[18px] text-info-blue" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="clients">{{ $clients }}</span>
                    <p class="mt-xs text-caption text-outline">Clients actifs de tous les postes</p>
                </div>
            @endif
            @if ($voirAchats)
                <div class="{{ $carte }} border-l-4 border-l-brand-gold" data-carte="dettes">
                    <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Dettes Fournisseurs</span><x-icone nom="local_shipping" class="text-[18px] text-brand-gold" /></div>
                    <span class="mt-xs block truncate text-kpi-value font-extrabold text-on-surface" data-kpi="dettes">{{ $nb($dettes) }} <small class="text-xs font-normal">FCFA</small></span>
                    <p class="mt-xs text-caption text-outline" data-detail="dettes">{{ $dettesNombre === 0 ? 'Aucune commande non soldée' : "$dettesNombre commande(s) non soldée(s)" }}</p>
                </div>
            @endif
        </div>
    </div>

    @if ($voirVentes || count($alertes))
        <div class="mb-lg grid grid-cols-1 gap-md lg:grid-cols-12">
            @if ($voirVentes)
                <section class="{{ $carte }} lg:col-span-8" id="tour-chart" data-bloc="courbe">
                    <h3 class="mb-md text-xs font-bold text-on-surface">CA vs Dépenses — 6 derniers mois</h3>
                    <svg viewBox="0 0 600 220" class="h-52 w-full" role="img" aria-label="Chiffre d'affaires et dépenses par mois sur les 6 derniers mois">
                        <line x1="40" y1="10" x2="40" y2="190" stroke="#D8DCE3" stroke-width="1" />
                        <line x1="40" y1="190" x2="580" y2="190" stroke="#D8DCE3" stroke-width="1" />
                        <polyline fill="none" stroke="#1F3864" stroke-width="3" stroke-linejoin="round" points="{{ implode(' ', array_map(fn ($p) => $p[0].','.$p[1], $courbe['ca'])) }}" />
                        @if ($depenses !== null)
                            <polyline fill="none" stroke="#B33A3A" stroke-width="3" stroke-dasharray="5,4" stroke-linejoin="round" points="{{ implode(' ', array_map(fn ($p) => $p[0].','.$p[1], $courbe['dep'])) }}" />
                        @endif
                        @foreach ($courbe['ca'] as $p)
                            <circle cx="{{ $p[0] }}" cy="{{ $p[1] }}" r="4" fill="#1F3864" data-mois="{{ $p[2]['cle'] }}" data-ca="{{ round($p[2]['ca']) }}"><title>{{ $p[2]['libelle'] }} : {{ $nb($p[2]['ca']) }} FCFA</title></circle>
                            <text x="{{ $p[0] }}" y="205" text-anchor="middle" font-size="10" fill="#6B7280">{{ $p[2]['libelle'] }}</text>
                        @endforeach
                    </svg>
                    <div class="mt-sm flex items-center gap-lg text-xs">
                        <span class="flex items-center gap-xs text-outline"><span class="inline-block h-3 w-3 rounded-full bg-brand-navy"></span>Chiffre d'affaires</span>
                        @if ($depenses !== null)
                            <span class="flex items-center gap-xs text-outline"><span class="inline-block h-3 w-3 rounded-full bg-error-deep"></span>Dépenses</span>
                        @endif
                    </div>
                </section>
            @endif
            <section class="{{ $carte }} {{ $voirVentes ? 'lg:col-span-4' : 'lg:col-span-12' }}" id="tour-alerts" data-bloc="alertes">
                <h3 class="mb-md text-xs font-bold text-on-surface">Alertes Critiques</h3>
                <div class="space-y-sm">
                    @forelse ($alertes as $a)
                        @php($critique = $a['niveau'] === 'critique')
                        <div class="flex items-start gap-sm rounded-lg p-sm {{ $critique ? 'bg-error-container' : 'bg-brand-gold/20' }}">
                            <x-icone :nom="['stock' => 'inventory_2', 'eclosion' => 'egg', 'solde' => 'request_quote', 'anniversaire' => 'cake', 'soin' => 'vaccines'][$a['icone']] ?? 'warning'" :class="'text-[18px] '.($critique ? 'text-error-deep' : 'text-brand-navy')" />
                            <p class="text-xs {{ $critique ? 'text-error-deep' : 'text-brand-navy' }}">{{ $a['texte'] }}</p>
                        </div>
                    @empty
                        <p class="text-xs text-outline">Aucune alerte en cours.</p>
                    @endforelse
                </div>
            </section>
        </div>
    @endif

    @if (count($filieres) || $couveuse !== null)
        <div id="tour-species-cards" class="mb-lg grid grid-cols-1 gap-md md:grid-cols-3" data-bloc="filieres">
            @foreach ($filieres as $f)
                <a href="{{ $f['route'] }}" class="{{ $carte }} block hover:bg-surface-zebra" data-filiere="{{ $f['code'] }}">
                    <div class="mb-sm flex items-center gap-xs"><x-icone nom="pets" class="text-brand-navy" /><h3 class="text-xs font-bold">{{ $f['nom'] }}</h3></div>
                    <div class="grid grid-cols-2 gap-sm text-xs">
                        <div><p class="text-outline">Effectif</p><p class="text-section-title font-bold">{{ $nb($f['effectif']) }}</p></div>
                        <div><p class="text-outline">Matures</p><p class="text-section-title font-bold">{{ $nb($f['matures']) }}</p></div>
                        <div><p class="text-outline">{{ $f['libelleJeunes'] }}</p><p class="text-section-title font-bold">{{ $nb($f['jeunes']) }}</p></div>
                        <div><p class="text-outline">Mortalité</p><p class="text-section-title font-bold {{ ($f['mortalite'] ?? 0) > 2 ? 'text-error-deep' : 'text-success-deep' }}">{{ $pourcent($f['mortalite']) }}</p></div>
                    </div>
                </a>
            @endforeach
            @if ($couveuse !== null)
                <div class="{{ $carte }}" data-filiere="couveuse">
                    <div class="mb-sm flex items-center gap-xs"><x-icone nom="egg" class="text-brand-gold" /><h3 class="text-xs font-bold">Couveuse</h3></div>
                    <div class="grid grid-cols-2 gap-sm text-xs">
                        <div><p class="text-outline">Cycles en cours</p><p class="text-section-title font-bold">{{ $couveuse['cycles'] }}</p></div>
                        <div><p class="text-outline">Œufs chargés</p><p class="text-section-title font-bold">{{ $nb($couveuse['oeufs']) }}</p></div>
                        <div><p class="text-outline">Taux éclosion moy.</p><p class="text-section-title font-bold">{{ $pourcent($couveuse['eclosionMoy']) }}</p></div>
                        <div><p class="text-outline">Taux perte moy.</p><p class="text-section-title font-bold text-error-deep">{{ $pourcent($couveuse['perteMoy']) }}</p></div>
                    </div>
                </div>
            @endif
        </div>
    @endif

    @if ($voirVentes)
        <div class="mb-lg grid grid-cols-1 gap-md lg:grid-cols-2">
            {{-- Statistiques de ventes --}}
            <section class="{{ $carte }}" data-bloc="statistiques">
                <div class="mb-md flex items-center justify-between">
                    <h3 class="flex items-center gap-xs text-xs font-bold text-on-surface"><x-icone nom="bar_chart" class="text-[18px] text-brand-navy" />Statistiques de Ventes</h3>
                    <span class="text-caption font-bold text-outline">{{ $maintenant->format('Y') }}</span>
                </div>
                <div class="mb-md grid grid-cols-2 gap-sm">
                    <div class="rounded-lg bg-surface-zebra p-sm"><span class="text-section-title font-extrabold text-brand-navy" data-kpi="semaine">{{ $nb($semaine) }} F</span><p class="text-caption text-outline">Revenu (semaine)</p></div>
                    @if ($depenses !== null)
                        <div class="rounded-lg bg-surface-zebra p-sm"><span class="text-section-title font-extrabold text-error-deep" data-kpi="depenses-jours">{{ $nb($depSemaine) }} F</span><p class="text-caption text-outline">Dépenses (6 jours)</p></div>
                    @endif
                </div>
                <svg viewBox="0 0 500 140" class="h-32 w-full" role="img" aria-label="Chiffre d'affaires et dépenses des 6 derniers jours">
                    <line x1="0" y1="120" x2="500" y2="120" stroke="#D8DCE3" stroke-width="1" />
                    @foreach ($jours as $i => $j)
                        @php($hc = round(($j['ca'] / $maxJ) * 100, 1))
                        @php($hd = round(($j['depenses'] / $maxJ) * 100, 1))
                        <rect x="{{ 10 + $i * 50 }}" y="{{ 120 - $hc }}" width="14" height="{{ $hc }}" rx="3" fill="#1F3864" />
                        @if ($depenses !== null)<rect x="{{ 28 + $i * 50 }}" y="{{ 120 - $hd }}" width="14" height="{{ $hd }}" rx="3" fill="#B33A3A" />@endif
                    @endforeach
                </svg>
                <div class="mt-xs flex justify-between px-1 text-caption text-outline">
                    @foreach ($jours as $j)<span>{{ $j['libelle'] }}</span>@endforeach
                </div>
            </section>

            {{-- Transactions recentes --}}
            <section class="{{ $carte }}" data-bloc="recentes">
                <div class="mb-md flex items-center justify-between">
                    <h3 class="flex items-center gap-xs text-xs font-bold text-on-surface"><x-icone nom="receipt" class="text-[18px] text-brand-navy" />Transactions Récentes</h3>
                    <a href="/ventes" class="text-caption font-bold text-brand-navy hover:underline">Voir tout</a>
                </div>
                <div class="mb-sm flex items-center gap-xs overflow-x-auto border-b border-outline-variant" role="tablist">
                    @foreach ([['ventes', 'Vente'], ['achats', 'Achat'], ['depenses', 'Dépenses']] as [$cle, $libelle])
                        @if ($cle === 'ventes' || $transactions[$cle] !== null)
                            <button type="button" role="tab" @click="onglet = '{{ $cle }}'"
                                    :class="onglet === '{{ $cle }}' ? 'border-brand-navy text-brand-navy' : 'border-transparent text-outline'"
                                    class="whitespace-nowrap border-b-2 px-sm py-1.5 text-caption font-bold">{{ $libelle }}</button>
                        @endif
                    @endforeach
                </div>
                <ul x-show="onglet === 'ventes'" class="space-y-xs text-xs">
                    @forelse ($recentes as $v)
                        <li class="flex items-center justify-between gap-sm border-b border-outline-variant py-1.5 last:border-b-0" data-recente="{{ $v->reference }}">
                            <span>{{ $v->reference }} · {{ $v->client }}</span>
                            <span class="font-bold {{ $v->status === 'Avance' ? 'text-brand-gold' : 'text-brand-navy' }}">{{ $nb($v->status === 'Avance' ? $v->paye : $v->total) }} F{{ $v->status === 'Avance' ? ' (avance)' : '' }}</span>
                        </li>
                    @empty
                        <li class="py-sm text-center text-outline">Aucune vente enregistrée.</li>
                    @endforelse
                </ul>
                @foreach (['achats' => 'Aucun achat enregistré.', 'depenses' => 'Aucune dépense enregistrée.'] as $cle => $vide)
                    @if ($transactions[$cle] !== null)
                        <ul x-show="onglet === '{{ $cle }}'" x-cloak class="space-y-xs text-xs" data-transactions="{{ $cle }}">
                            @forelse ($transactions[$cle] as $t)
                                <li class="flex items-center justify-between gap-sm border-b border-outline-variant py-1.5 last:border-b-0">
                                    <span>{{ $t['ref'] }} · {{ $t['libelle'] }}</span>
                                    <span class="font-bold {{ $cle === 'depenses' ? 'text-error-deep' : 'text-brand-navy' }}">{{ $nb($t['montant']) }} F</span>
                                </li>
                            @empty
                                <li class="py-sm text-center text-outline">{{ $vide }}</li>
                            @endforelse
                        </ul>
                    @endif
                @endforeach
            </section>
        </div>
    @endif

    <div class="grid grid-cols-1 gap-md lg:grid-cols-2">
        @if (count($activites) || $voirVentes)
            <section class="{{ $carte }}" data-bloc="activites">
                <h3 class="mb-md text-xs font-bold text-on-surface">Activités du Jour</h3>
                <div class="space-y-md">
                    @forelse ($activites as $a)
                        <div class="flex gap-sm">
                            <span class="mt-1.5 h-2 w-2 flex-shrink-0 rounded-full bg-brand-navy"></span>
                            <div><p class="text-xs font-semibold">{{ $a['texte'] }}</p><p class="text-caption text-outline">{{ $a['heure'] }}{{ ($a['auteur'] ?? null) ? ' — '.$a['auteur'] : '' }}</p></div>
                        </div>
                    @empty
                        <p class="text-xs text-outline">Aucune activité aujourd'hui.</p>
                    @endforelse
                </div>
            </section>
        @endif

        @if ($voirVentes)
            <section class="{{ $carte }} overflow-x-auto" data-bloc="meilleures">
                <h3 class="mb-md text-xs font-bold text-on-surface">Meilleures Ventes de la Période</h3>
                <table class="w-full text-xs" data-table="meilleures">
                    <thead><tr class="border-b border-outline-variant text-outline"><th class="py-xs text-left">Produit</th><th class="py-xs text-right">Qté</th><th class="py-xs text-right">CA</th><th class="py-xs text-right">Activité</th></tr></thead>
                    <tbody>
                        @forelse ($meilleures as $l)
                            <tr class="border-b border-outline-variant {{ $loop->odd ? 'bg-surface-zebra' : '' }}" data-meilleure="{{ $l['produit'] }}">
                                <td class="py-xs font-bold">{{ $l['produit'] }}</td>
                                <td class="text-right">{{ rtrim(rtrim(number_format($l['quantite'], 2, ',', ' '), '0'), ',') }}</td>
                                <td class="text-right font-bold">{{ $nb($l['ca']) }} F</td>
                                <td class="text-right {{ $l['activite'] === 'Commerce' ? 'text-brand-gold' : 'text-brand-navy' }}">{{ $l['activite'] }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="4" class="py-lg text-center text-outline">Aucune vente sur la période.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </section>
        @endif
    </div>
</div>
