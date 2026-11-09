@php
    $pct = fn (float $v): string => number_format($v, 1, ',', ' ').' %';
@endphp
<div>
    <div class="mb-md">
        <h1 class="text-page-title font-bold">Dashboard Élevage</h1>
        <p class="text-xs text-outline">Vue consolidée — filières actives et couveuse en un seul écran.</p>
    </div>

    <div class="mb-lg grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3" data-grille="filieres">
        @foreach ($filieres as $f)
            <a href="{{ $f['route'] }}" data-filiere="{{ $f['espece'] }}"
               class="block rounded-lg border border-outline-variant bg-surface-card p-md shadow-sm hover:border-brand-navy">
                <h2 class="mb-sm text-section-title font-bold">{{ $f['libelle'] }}</h2>
                @if ($f['a_des_donnees'])
                    <div class="grid grid-cols-2 gap-sm">
                        <div>
                            <p class="text-caption uppercase text-outline">Effectif</p>
                            <p class="text-page-title font-bold" data-chiffre="effectif">{{ $f['effectif'] }}</p>
                        </div>
                        <div>
                            <p class="text-caption uppercase text-outline">Matures</p>
                            <p class="text-page-title font-bold text-success-deep" data-chiffre="matures">{{ $f['matures'] }}</p>
                        </div>
                        <div>
                            <p class="text-caption uppercase text-outline">{{ $f['libelle_jeunes'] }}</p>
                            <p class="text-page-title font-bold" data-chiffre="jeunes">{{ $f['jeunes'] }}</p>
                        </div>
                        <div>
                            <p class="text-caption uppercase text-outline">Mortalité</p>
                            <p class="text-page-title font-bold {{ ['critique' => 'text-error-deep', 'avertissement' => 'text-brand-gold', 'normal' => 'text-success-deep'][$f['niveau_mortalite']] }}" data-niveau="{{ $f['niveau_mortalite'] }}" data-chiffre="mortalite">{{ $pct($f['mortalite']) }}</p>
                        </div>
                    </div>
                @else
                    <p class="text-xs text-outline" data-vide>Aucune journée saisie pour cette filière. Les effectifs apparaîtront dès la première saisie sur sa fiche.</p>
                @endif
            </a>
        @endforeach

        <div class="rounded-lg border border-dashed border-outline-variant bg-surface-zebra p-md text-outline" data-carte-poste="Couveuse">
            <h2 class="mb-sm text-section-title font-bold">Couveuse</h2>
            <p class="text-caption font-semibold">Disponible sur le poste</p>
            <p class="text-caption">Les cycles de couveuse ne sont pas encore synchronisés avec le serveur.</p>
        </div>

        @foreach ($apercus as $module => [$titre, $texte])
            <div class="rounded-lg border border-outline-variant bg-surface-zebra p-md" data-apercu="{{ $module }}">
                <h2 class="mb-sm text-section-title font-bold text-outline">{{ $titre }} <span class="text-caption font-normal">(non activée)</span></h2>
                <p class="mb-sm text-xs text-outline">{{ $texte }}</p>
                @if ($peutParametrer)
                    <a href="/parametres/generaux" class="text-xs font-bold text-brand-navy underline">Activer depuis Paramètres →</a>
                @endif
            </div>
        @endforeach
    </div>

    <div class="mb-lg grid grid-cols-1 gap-md lg:grid-cols-2">
        <section class="rounded-lg border border-outline-variant bg-surface-card p-md" data-panneau="gmq">
            <h2 class="mb-sm text-section-title font-bold">Gain Moyen Quotidien (GMQ) par Espèce — 4 Dernières Semaines</h2>
            @if (count($gmq) === 0)
                <p class="text-xs text-outline" data-gmq="vide">Le GMQ se calcule à partir de deux pesées de la fiche sur les 4 dernières semaines (« Pesée totale du lot »). Aucune filière n'en a encore deux.</p>
            @else
                <ul class="flex flex-col gap-xs text-xs">
                    @foreach ($filieres as $f)
                        @if (isset($gmq[$f['espece']]))
                            @php($g = $gmq[$f['espece']])
                            <li data-gmq="{{ $f['espece'] }}">{{ $f['libelle'] }} : {{ number_format($g['gmq'], 1, ',', '') }} g/j ({{ (int) round($g['poids_initial_g']) }} g → {{ (int) round($g['poids_final_g']) }} g en {{ $g['jours'] }} j)</li>
                        @endif
                    @endforeach
                </ul>
            @endif
        </section>
        <section class="rounded-lg border border-dashed border-outline-variant bg-surface-zebra p-md text-outline" data-carte-poste="Rappels Vétérinaires à Venir">
            <h2 class="mb-sm text-section-title font-bold">Rappels Vétérinaires à Venir</h2>
            <p class="text-caption font-semibold">Disponible sur le poste</p>
            <p class="text-caption">Le calendrier de soins n'est pas encore synchronisé avec le serveur.</p>
        </section>
    </div>

    <div class="grid grid-cols-1 gap-md lg:grid-cols-2">
        <section class="rounded-lg border border-dashed border-outline-variant bg-surface-zebra p-md text-outline" data-carte-poste="Alertes Sanitaires du Jour">
            <h2 class="mb-sm text-section-title font-bold">Alertes Sanitaires du Jour</h2>
            <p class="text-caption font-semibold">Disponible sur le poste</p>
            <p class="text-caption">Soins en retard et stocks d'intrants sous leur seuil : propres au poste, jamais estimés ici.</p>
        </section>

        <section class="rounded-lg border border-outline-variant bg-surface-card p-md" data-panneau="bilan">
            <h2 class="mb-sm text-section-title font-bold">Bilan Économique Élevage (Mois)</h2>
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
