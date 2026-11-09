@php
    $nb = fn ($v) => number_format($v, 0, ',', ' ');
    // Cartes grisees : donnees absentes du serveur (declarees, jamais inventees). [libelle, droit requis, raison]
    $surLePoste = [
        ['Trésorerie', $voirComptabilite, 'Le solde de caisse se lit sur le poste (comptabilité).'],
        ['Dépenses', $voirAchats, 'Les dépenses se lisent sur le poste (achats et comptabilité).'],
        ['Résultat Net', $voirComptabilite, 'Il dépend des dépenses de la période, propres au poste.'],
        ['Stock Critique', $voirStocks, 'Le stock est propre à chaque poste.'],
        ['Effectif Cheptel', $voirElevage, 'Les journées d\'élevage restent sur le poste.'],
        ['Cycles Couveuse en Cours', $voirElevage, 'Les cycles de couveuse restent sur le poste.'],
    ];
@endphp
<div>
    <div class="mb-md flex flex-wrap items-start justify-between gap-sm">
        <div>
            <h1 class="text-page-title font-bold text-brand-navy" data-titre="bienvenue">Bienvenue, {{ auth()->user()->name }}</h1>
            <p class="text-caption text-outline">Rapport généré le {{ $maintenant->format('d/m/Y') }} à {{ $maintenant->format('H:i') }} · ALLMANY ET COMPAGNIE</p>
        </div>
        <div class="flex flex-wrap gap-sm">
            @if ($voirVentes)
                <a href="/ventes" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Enregistrer une Vente</a>
            @endif
            @if ($voirElevage)
                <a href="/elevage/dashboard" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">Dashboard Élevage</a>
            @endif
        </div>
    </div>

    @if ($voirVentes)
        <div class="mb-md flex flex-wrap items-center gap-sm rounded-lg border border-outline-variant bg-surface-card p-sm">
            <label class="flex items-center gap-sm text-xs text-outline">Du
                <input type="date" wire:model.live="debut" aria-label="Début de la période"
                       class="rounded-lg border border-outline-variant px-sm py-xs text-xs text-on-surface"></label>
            <label class="flex items-center gap-sm text-xs text-outline">au
                <input type="date" wire:model.live="fin" aria-label="Fin de la période"
                       class="rounded-lg border border-outline-variant px-sm py-xs text-xs text-on-surface"></label>
        </div>
        @unless ($periodeValide)
            <p role="alert" class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep" data-alerte="periode">
                Période invalide (le début doit précéder la fin) : le mois en cours est affiché.</p>
        @endunless
    @endif

    <div class="mb-lg grid grid-cols-1 gap-md sm:grid-cols-2 xl:grid-cols-4" id="kpi-panel">
        @if ($voirVentes)
            <div class="rounded-lg border-l-4 border-brand-navy bg-surface-card p-md shadow-sm" data-carte="ca">
                <p class="text-caption uppercase text-outline">Chiffre d'Affaires</p>
                <p class="text-kpi-value font-bold" data-kpi="ca">{{ $nb($ca['total']) }} <span class="text-xs font-normal">FCFA</span></p>
                <p class="text-caption text-outline">Avicole : <span data-kpi="ca-avicole">{{ $nb($ca['avicole']) }}</span> · Commerce annexe : <span data-kpi="ca-commerce">{{ $nb($ca['commerce']) }}</span></p>
            </div>
        @endif

        @foreach ($surLePoste as [$libelle, $droit, $raison])
            @if ($droit)
                <div class="rounded-lg border-l-4 border-outline-variant bg-surface-zebra p-md text-outline" data-carte-poste="{{ $libelle }}">
                    <p class="text-caption uppercase">{{ $libelle }}</p>
                    <p class="text-kpi-value font-bold">—</p>
                    <p class="text-caption font-semibold">Disponible sur le poste</p>
                    <p class="text-caption">{{ $raison }}</p>
                </div>
            @endif
        @endforeach

        @if ($voirVentes)
            <div class="rounded-lg border-l-4 border-error-deep bg-surface-card p-md shadow-sm" data-carte="encours">
                <p class="text-caption uppercase text-outline">Soldes Restant Dus</p>
                <p class="text-kpi-value font-bold" data-kpi="encours">{{ $nb($encours) }} <span class="text-xs font-normal">FCFA</span></p>
                <p class="text-caption text-outline" data-detail="encours">{{ $encoursNombre === 0 ? 'Aucune vente en avance non soldée' : "$encoursNombre vente(s) en avance non soldée(s)" }}</p>
            </div>
            <div class="rounded-lg border-l-4 border-info-blue bg-surface-card p-md shadow-sm" data-carte="clients">
                <p class="text-caption uppercase text-outline">Clients Enregistrés</p>
                <p class="text-kpi-value font-bold" data-kpi="clients">{{ $clients }}</p>
                <p class="text-caption text-outline">Clients actifs de tous les postes</p>
            </div>
        @endif

        @if ($voirAchats)
            <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm" data-carte="dettes">
                <p class="text-caption uppercase text-outline">Dettes Fournisseurs</p>
                <p class="text-kpi-value font-bold" data-kpi="dettes">{{ $nb($dettes) }} <span class="text-xs font-normal">FCFA</span></p>
                <p class="text-caption text-outline" data-detail="dettes">{{ $dettesNombre === 0 ? 'Aucune commande non soldée' : "$dettesNombre commande(s) non soldée(s)" }}</p>
            </div>
        @endif
    </div>

    @if ($voirVentes)
        @php
            // Courbe SVG simple (hors ligne, sans bibliotheque) : CA des 6 derniers mois.
            $largeur = 600; $hauteur = 200; $gauche = 56; $bas = 24; $haut = 12; $droite = 12;
            $max = max(array_column($mois, 'ca'));
            $maxY = $max > 0 ? $max * 1.15 : 1;
            $pas = (count($mois) - 1) > 0 ? ($largeur - $gauche - $droite) / (count($mois) - 1) : 0;
            $points = [];
            foreach ($mois as $i => $m) {
                $points[] = [
                    'x' => $gauche + $i * $pas,
                    'y' => $hauteur - $bas - ($m['ca'] / $maxY) * ($hauteur - $bas - $haut),
                    'm' => $m,
                ];
            }
            $trace = implode(' ', array_map(fn ($p) => round($p['x'], 1).','.round($p['y'], 1), $points));
        @endphp
        <div class="mb-lg grid grid-cols-1 gap-md lg:grid-cols-3">
            <section class="rounded-lg border border-outline-variant bg-surface-card p-md lg:col-span-2" data-bloc="courbe">
                <h2 class="mb-sm text-section-title font-bold">Chiffre d'Affaires — 6 derniers mois</h2>
                <svg viewBox="0 0 {{ $largeur }} {{ $hauteur }}" class="h-52 w-full" role="img" aria-label="Chiffre d'affaires par mois sur les 6 derniers mois">
                    <line x1="{{ $gauche }}" y1="{{ $haut }}" x2="{{ $gauche }}" y2="{{ $hauteur - $bas }}" class="stroke-outline-variant" stroke-width="1" />
                    <line x1="{{ $gauche }}" y1="{{ $hauteur - $bas }}" x2="{{ $largeur - $droite }}" y2="{{ $hauteur - $bas }}" class="stroke-outline-variant" stroke-width="1" />
                    <text x="{{ $gauche - 6 }}" y="{{ $hauteur - $bas }}" text-anchor="end" class="fill-outline" font-size="10">0</text>
                    <text x="{{ $gauche - 6 }}" y="{{ $haut + 8 }}" text-anchor="end" class="fill-outline" font-size="10">{{ $nb($maxY) }}</text>
                    <polyline points="{{ $trace }}" fill="none" class="stroke-brand-navy" stroke-width="3" stroke-linejoin="round" />
                    @foreach ($points as $p)
                        <circle cx="{{ round($p['x'], 1) }}" cy="{{ round($p['y'], 1) }}" r="4" class="fill-brand-navy" data-mois="{{ $p['m']['cle'] }}" data-ca="{{ round($p['m']['ca']) }}">
                            <title>{{ $p['m']['libelle'] }} : {{ $nb($p['m']['ca']) }} FCFA</title>
                        </circle>
                        <text x="{{ round($p['x'], 1) }}" y="{{ $hauteur - 8 }}" text-anchor="middle" class="fill-outline" font-size="10">{{ $p['m']['libelle'] }}</text>
                    @endforeach
                </svg>
                <p class="mt-sm text-caption text-outline">Les dépenses ne sont pas connues du serveur : la courbe « CA vs Dépenses » est complète sur le poste.</p>
            </section>

            <section class="rounded-lg border border-outline-variant bg-surface-card p-md" data-bloc="recentes">
                <h2 class="mb-sm text-section-title font-bold">Transactions Récentes</h2>
                <div class="mb-sm rounded-lg bg-surface-zebra p-sm">
                    <p class="text-section-title font-bold text-brand-navy" data-kpi="semaine">{{ $nb($semaine) }} F</p>
                    <p class="text-caption text-outline">Revenu (semaine)</p>
                </div>
                <ul class="text-xs">
                    @forelse ($recentes as $v)
                        <li class="flex justify-between gap-sm border-b border-outline-variant py-sm" data-recente="{{ $v->reference }}">
                            <span>{{ $v->reference }} · {{ $v->client }}</span>
                            <span class="font-bold {{ $v->status === 'Avance' ? 'text-brand-gold' : '' }}">{{ $nb($v->status === 'Avance' ? $v->paye : $v->total) }} F{{ $v->status === 'Avance' ? ' (avance)' : '' }}</span>
                        </li>
                    @empty
                        <li class="py-sm text-center text-outline">Aucune vente enregistrée.</li>
                    @endforelse
                </ul>
            </section>
        </div>

        <section class="mb-lg rounded-lg border border-outline-variant bg-surface-card p-md" data-bloc="meilleures">
            <h2 class="mb-sm text-section-title font-bold">Meilleures Ventes de la Période</h2>
            <div class="overflow-x-auto">
                <table class="w-full text-left text-xs" data-table="meilleures">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-md py-sm">Produit</th>
                            <th class="px-md py-sm">Activité</th>
                            <th class="px-md py-sm text-right">Quantité</th>
                            <th class="px-md py-sm text-right">Chiffre d'Affaires</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse ($meilleures as $l)
                            <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-meilleure="{{ $l['produit'] }}">
                                <td class="px-md py-sm font-bold">{{ $l['produit'] }}</td>
                                <td class="px-md py-sm">{{ $l['activite'] }}</td>
                                <td class="px-md py-sm text-right">{{ rtrim(rtrim(number_format($l['quantite'], 2, ',', ' '), '0'), ',') }}</td>
                                <td class="px-md py-sm text-right font-bold">{{ $nb($l['ca']) }} F</td>
                            </tr>
                        @empty
                            <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucune vente sur la période.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
        </section>
    @endif

    <section class="rounded-lg border border-dashed border-outline-variant bg-surface-zebra p-md" data-bloc="ecarts">
        <h2 class="mb-xs text-section-title font-bold">Disponible sur le poste</h2>
        <p class="text-xs text-outline">
            Le web ne montre que ce que le serveur calcule : ventes, créances, clients et dettes fournisseurs. Restent au poste (jamais estimés ici) :
            trésorerie, dépenses et résultat net, effectif du cheptel et cartes de filière, cycles de couveuse, stock critique et alertes de stock,
            rappels de prophylaxie, fil d'activités du jour, courbe « CA vs Dépenses » complète et export d'état.
        </p>
    </section>
</div>
