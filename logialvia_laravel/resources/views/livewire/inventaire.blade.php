@php
    use App\Livewire\Inventaire as Inv;
    // Encarts grises : ce que le serveur ne possede pas (stock, PMP, valeur : propres a chaque poste). [libelle, detail]
    $surLePoste = [
        ['Valeur Totale du Stock', 'Intrants au PMP + produits au coût de revient : le stock est propre à chaque poste.'],
        ['Dont Intrants', 'Valorisés au PMP, calculé sur le poste.'],
        ['Dont Produits Finis', 'Valorisés au coût de revient sur le stock du poste.'],
    ];
    $signe = fn (float $v) => ($v > 0 ? '+ ' : '− ').Inv::qte(abs($v));
@endphp
<div>
    <div class="mb-md flex flex-wrap items-center gap-sm">
        <div>
            <h1 class="text-page-title font-bold text-brand-navy">Inventaire</h1>
            <p class="text-caption text-outline" data-libelle-periode>{{ $libellePeriode }}</p>
        </div>
    </div>

    <p class="mb-md text-xs text-outline">
        Le serveur ne possède ni le stock ni le prix moyen pondéré (PMP) : ils sont <strong>propres à chaque poste</strong>.
        Cet écran montre uniquement les <strong>faits synchronisés</strong> de la période (mouvements, ventes, achats, saisies d'élevage).
        L'état daté complet (valeurs de départ et d'arrivée, valorisation) se lit et s'imprime sur le poste.
    </p>

    <div class="mb-md flex flex-wrap items-center gap-sm rounded-lg border border-outline-variant bg-surface-card p-md" data-bloc="filtres">
        @foreach (Inv::PERIODES as $cle => $libelle)
            @if ($cle === 'plage')
                <span class="rounded-full border px-md py-xs text-caption font-bold {{ $periode === $cle ? 'border-brand-navy bg-brand-navy text-white' : 'border-outline-variant text-outline' }}"
                      data-periode="{{ $cle }}" @if ($periode === $cle) aria-current="true" @endif>{{ $libelle }}</span>
            @else
                <button type="button" wire:click="changerPeriode('{{ $cle }}')" data-periode="{{ $cle }}"
                        @if ($periode === $cle) aria-current="true" @endif
                        class="rounded-full border px-md py-xs text-caption font-bold {{ $periode === $cle ? 'border-brand-navy bg-brand-navy text-white' : 'border-outline-variant text-outline hover:bg-surface-zebra' }}">{{ $libelle }}</button>
            @endif
        @endforeach
        <label class="flex items-center gap-sm text-xs text-outline">Du
            <input type="date" wire:model.live="debut" aria-label="Début de la période"
                   class="rounded-lg border border-outline-variant px-sm py-xs text-xs text-on-surface"></label>
        <label class="flex items-center gap-sm text-xs text-outline">Au
            <input type="date" wire:model.live="fin" aria-label="Fin de la période"
                   class="rounded-lg border border-outline-variant px-sm py-xs text-xs text-on-surface"></label>
        <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="Rechercher un article, un code…"
               aria-label="Rechercher un article"
               class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:w-64">
    </div>

    @unless ($periodeValide)
        <p role="alert" class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep" data-alerte="periode">
            Période invalide (dates incorrectes ou début après la fin) : le jour en cours est affiché.</p>
    @endunless

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-4" data-bloc="kpi">
        @foreach ($surLePoste as [$libelle, $detail])
            <div class="rounded-lg border-l-4 border-outline-variant bg-surface-zebra p-md text-outline" data-carte-poste="{{ $libelle }}">
                <p class="text-caption uppercase">{{ $libelle }}</p>
                <p class="text-kpi-value font-bold">—</p>
                <p class="text-caption font-semibold">Disponible sur le poste</p>
                <p class="text-caption">{{ $detail }}</p>
            </div>
        @endforeach
        <div class="rounded-lg border-l-4 border-success-deep bg-surface-card p-md shadow-sm" data-kpi="animaux">
            <p class="text-caption uppercase text-outline">Animaux sur Pied</p>
            <p class="text-kpi-value font-bold">{{ $effectifTotal }}</p>
            <p class="text-caption text-outline">Comptés, non valorisés</p>
        </div>
    </div>

    <div class="mb-md rounded-lg border border-dashed border-outline-variant bg-surface-zebra p-md text-outline" data-carte-poste="equilibre">
        <p class="text-caption font-semibold uppercase">Contrôle d'équilibre des articles</p>
        <p class="text-caption font-semibold">Disponible sur le poste</p>
        <p class="text-caption">Vérifier que les mouvements expliquent l'écart entre deux dates exige le stock de chaque article, propre à chaque poste.</p>
    </div>

    {{-- ===== Intrants ===== --}}
    <section class="mb-lg" data-section="intrants">
        <h2 class="mb-sm text-section-title font-bold">Intrants — mouvements de la période</h2>
        <div class="mb-sm rounded-lg border border-dashed border-outline-variant bg-surface-zebra p-sm text-outline" data-carte-poste="intrants">
            <p class="text-caption"><span class="font-semibold">Disponible sur le poste :</span> stocks de début et de fin, PMP, valeur et total des intrants.</p>
        </div>

        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Article</th>
                        <th class="px-md py-sm">Catégorie</th>
                        <th class="px-md py-sm text-right">Entrées</th>
                        <th class="px-md py-sm text-right">Sorties</th>
                        <th class="px-md py-sm text-right">Dont ajustements</th>
                        <th class="px-md py-sm text-right">Achats livrés</th>
                        <th class="px-md py-sm">Postes</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse ($intrants as $l)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-intrant="{{ $l['code'] }}">
                            <td class="px-md py-sm"><span class="font-bold">{{ $l['article'] }}</span><br><span class="text-caption text-outline">{{ $l['code'] }}</span></td>
                            <td class="px-md py-sm">{{ $l['categorie'] }}</td>
                            <td class="px-md py-sm text-right {{ $l['entrees'] == 0 ? 'text-outline' : 'text-success-deep' }}" data-col="entrees">{{ $l['entrees'] == 0 ? '—' : '+ '.Inv::qte($l['entrees']) }}</td>
                            <td class="px-md py-sm text-right {{ $l['sorties'] == 0 ? 'text-outline' : 'text-error-deep' }}" data-col="sorties">{{ $l['sorties'] == 0 ? '—' : '− '.Inv::qte($l['sorties']) }}</td>
                            <td class="px-md py-sm text-right {{ $l['ajustements'] == 0 ? 'text-outline' : '' }}" data-col="ajustements">{{ $l['ajustements'] == 0 ? '—' : $signe($l['ajustements']) }}</td>
                            <td class="px-md py-sm text-right {{ $l['achetes'] == 0 ? 'text-outline' : '' }}" data-col="achetes">{{ $l['achetes'] == 0 ? '—' : Inv::qte($l['achetes']) }}</td>
                            <td class="px-md py-sm text-caption text-outline" data-col="postes">{{ $l['postes'] === [] ? '—' : implode(', ', $l['postes']) }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucun intrant ne correspond à ces filtres.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>

        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes-intrants">
            @forelse ($intrants as $l)
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-intrant="{{ $l['code'] }}">
                    <p class="font-bold">{{ $l['article'] }}</p>
                    <p class="text-caption text-outline">{{ $l['categorie'] }} · {{ $l['unite'] }} · {{ $l['code'] }}</p>
                    <p class="text-xs">Entrées : <span class="font-bold text-success-deep">{{ $l['entrees'] == 0 ? '—' : '+ '.Inv::qte($l['entrees']) }}</span>
                        · Sorties : <span class="font-bold text-error-deep">{{ $l['sorties'] == 0 ? '—' : '− '.Inv::qte($l['sorties']) }}</span></p>
                    <p class="text-xs">Dont ajustements : <span class="font-bold">{{ $l['ajustements'] == 0 ? '—' : $signe($l['ajustements']) }}</span>
                        · Achats livrés : <span class="font-bold">{{ $l['achetes'] == 0 ? '—' : Inv::qte($l['achetes']) }}</span></p>
                    <p class="text-caption text-outline">Postes : {{ $l['postes'] === [] ? '—' : implode(', ', $l['postes']) }}</p>
                </article>
            @empty
                <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun intrant ne correspond à ces filtres.</p>
            @endforelse
        </div>
    </section>

    {{-- ===== Produits ===== --}}
    <section class="mb-lg" data-section="produits">
        <h2 class="mb-sm text-section-title font-bold">Produits finis — ventes et corrections de la période</h2>
        <div class="mb-sm rounded-lg border border-dashed border-outline-variant bg-surface-zebra p-sm text-outline" data-carte-poste="produits">
            <p class="text-caption"><span class="font-semibold">Disponible sur le poste :</span> stocks de début et de fin, valeur au coût de revient et total des produits finis.</p>
        </div>

        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Produit</th>
                        <th class="px-md py-sm">Catégorie</th>
                        <th class="px-md py-sm text-right">Sorties (ventes)</th>
                        <th class="px-md py-sm text-right">Corrections</th>
                        <th class="px-md py-sm text-right">Coût de revient</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse ($produits as $l)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-produit="{{ $l['sku'] }}">
                            <td class="px-md py-sm"><span class="font-bold">{{ $l['produit'] }}</span>@if ($l['archive']) <span class="text-caption text-outline">(archivé)</span>@endif<br><span class="text-caption text-outline">{{ $l['sku'] }}</span></td>
                            <td class="px-md py-sm">{{ $l['categorie'] }}</td>
                            <td class="px-md py-sm text-right {{ $l['vendu'] == 0 ? 'text-outline' : 'text-error-deep' }}" data-col="vendu">{{ $l['vendu'] == 0 ? '—' : '− '.Inv::qte($l['vendu']) }}</td>
                            <td class="px-md py-sm text-right {{ $l['nombreCorrections'] === 0 ? 'text-outline' : '' }}" data-col="corrections">{{ $l['nombreCorrections'] === 0 ? '—' : ($l['corrections'] == 0 ? '0' : $signe($l['corrections'])) }}</td>
                            <td class="px-md py-sm text-right {{ $l['coutRevient'] === null ? 'text-outline' : '' }}" data-col="cout">{{ $l['coutRevient'] === null ? 'Non renseigné' : number_format($l['coutRevient'], 0, ',', ' ').' FCFA' }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun produit ne correspond à ces filtres.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>

        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes-produits">
            @forelse ($produits as $l)
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-produit="{{ $l['sku'] }}">
                    <p class="font-bold">{{ $l['produit'] }}@if ($l['archive']) <span class="text-caption font-normal text-outline">(archivé)</span>@endif</p>
                    <p class="text-caption text-outline">{{ $l['categorie'] }} · {{ $l['unite'] }} · {{ $l['sku'] }}</p>
                    <p class="text-xs">Sorties (ventes) : <span class="font-bold text-error-deep">{{ $l['vendu'] == 0 ? '—' : '− '.Inv::qte($l['vendu']) }}</span>
                        · Corrections : <span class="font-bold">{{ $l['nombreCorrections'] === 0 ? '—' : ($l['corrections'] == 0 ? '0' : $signe($l['corrections'])) }}</span></p>
                    <p class="text-caption text-outline">Coût de revient : {{ $l['coutRevient'] === null ? 'Non renseigné' : number_format($l['coutRevient'], 0, ',', ' ').' FCFA' }}</p>
                </article>
            @empty
                <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun produit ne correspond à ces filtres.</p>
            @endforelse
        </div>
    </section>

    {{-- ===== Animaux sur pied ===== --}}
    <section class="mb-lg" data-section="effectifs">
        <h2 class="mb-sm text-section-title font-bold">Animaux sur pied — comptés, non valorisés</h2>
        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Filière</th>
                        <th class="px-md py-sm text-right">Effectif</th>
                        <th class="px-md py-sm text-right">Dernière saisie</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach ($effectifs as $l)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-effectif="{{ $l['espece'] }}">
                            <td class="px-md py-sm">{{ $l['libelle'] }}</td>
                            <td class="px-md py-sm text-right font-bold" data-col="effectif">{{ $l['effectif'] }}</td>
                            <td class="px-md py-sm text-right {{ $l['dateSaisie'] === null ? 'text-outline' : '' }}" data-col="saisie">{{ $l['dateSaisie'] ?? 'Jamais saisie' }}</td>
                        </tr>
                    @endforeach
                    <tr class="bg-surface-zebra font-bold">
                        <td class="px-md py-sm">TOTAL ANIMAUX SUR PIED</td>
                        <td class="px-md py-sm text-right" data-col="total-effectif">{{ $effectifTotal }}</td>
                        <td class="px-md py-sm text-right">sujets</td>
                    </tr>
                </tbody>
            </table>
        </div>
        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes-effectifs">
            @foreach ($effectifs as $l)
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-effectif="{{ $l['espece'] }}">
                    <p class="font-bold">{{ $l['libelle'] }} : {{ $l['effectif'] }}</p>
                    <p class="text-caption text-outline">Dernière saisie : {{ $l['dateSaisie'] ?? 'Jamais saisie' }}</p>
                </article>
            @endforeach
            <p class="rounded-lg bg-surface-zebra p-md text-xs font-bold">Total : {{ $effectifTotal }} sujets</p>
        </div>
        <p class="mt-sm text-xs text-outline" data-oeufs>Œufs en incubation à la fin de la période : <span class="font-bold">{{ $oeufs }}</span></p>
    </section>

    {{-- ===== Journaux ===== --}}
    <section class="mb-lg" data-section="journal-intrants">
        <h2 class="mb-sm text-section-title font-bold">Journal des mouvements d'intrants de la période</h2>
        <p class="mb-sm text-xs text-outline">
            Tous les postes, avec le poste d'origine : un mouvement d'un autre poste ne change jamais le stock d'un poste.
            @if ($totalJournalIntrants > \App\Livewire\Inventaire::LIMITE_JOURNAL)
                <span data-troncature>Les {{ \App\Livewire\Inventaire::LIMITE_JOURNAL }} plus récents sur {{ $totalJournalIntrants }}.</span>
            @endif
            Heures de Porto-Novo.
        </p>
        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Date / Heure</th>
                        <th class="px-md py-sm">Référence</th>
                        <th class="px-md py-sm">Article</th>
                        <th class="px-md py-sm">Type</th>
                        <th class="px-md py-sm">Motif</th>
                        <th class="px-md py-sm">Poste</th>
                        <th class="px-md py-sm text-right">Quantité</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse ($journalIntrants as $j)
                        @php($m = $j['m'])
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-mouvement="{{ $m->id }}">
                            <td class="px-md py-sm">{{ $j['quand']->format('d/m/Y H:i') }}</td>
                            <td class="px-md py-sm text-outline">{{ $m->reference ?? '—' }}</td>
                            <td class="px-md py-sm font-bold">{{ $m->article }}</td>
                            <td class="px-md py-sm">{{ $m->type }}</td>
                            <td class="px-md py-sm">{{ $m->motif }}</td>
                            <td class="px-md py-sm" data-poste>{{ $j['poste'] }}</td>
                            <td class="px-md py-sm text-right font-bold {{ $m->quantite >= 0 ? 'text-success-deep' : 'text-error-deep' }}">{{ $signe($m->quantite) }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucun mouvement d'intrant sur cette période.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes-journal-intrants">
            @forelse ($journalIntrants as $j)
                @php($m = $j['m'])
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-mouvement="{{ $m->id }}">
                    <p class="font-bold">{{ $m->article }}</p>
                    <p class="text-caption text-outline">{{ $j['quand']->format('d/m/Y H:i') }} · {{ $m->type }} · {{ $j['poste'] }}@if ($m->reference) · {{ $m->reference }}@endif</p>
                    <p class="text-xs">{{ $m->motif }}</p>
                    <p class="font-bold {{ $m->quantite >= 0 ? 'text-success-deep' : 'text-error-deep' }}">{{ $signe($m->quantite) }}</p>
                </article>
            @empty
                <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun mouvement d'intrant sur cette période.</p>
            @endforelse
        </div>
    </section>

    <section class="mb-lg" data-section="journal-produits">
        <h2 class="mb-sm text-section-title font-bold">Corrections de stock des produits de la période</h2>
        <p class="mb-sm text-xs text-outline">
            Variations saisies sur les postes (formulaire du catalogue), avec le poste d'origine. Les ventes figurent dans « Sorties (ventes) ».
            @if ($totalJournalProduits > \App\Livewire\Inventaire::LIMITE_JOURNAL)
                <span data-troncature>Les {{ \App\Livewire\Inventaire::LIMITE_JOURNAL }} plus récentes sur {{ $totalJournalProduits }}.</span>
            @endif
        </p>
        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Date / Heure</th>
                        <th class="px-md py-sm">Produit</th>
                        <th class="px-md py-sm">Motif</th>
                        <th class="px-md py-sm">Poste</th>
                        <th class="px-md py-sm text-right">Variation</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse ($journalProduits as $j)
                        @php($m = $j['m'])
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-correction="{{ $m->id }}">
                            <td class="px-md py-sm">{{ $j['quand']->format('d/m/Y H:i') }}</td>
                            <td class="px-md py-sm font-bold">{{ $m->article }}</td>
                            <td class="px-md py-sm">{{ $m->motif }}</td>
                            <td class="px-md py-sm" data-poste>{{ $j['poste'] }}</td>
                            <td class="px-md py-sm text-right font-bold {{ $m->quantite >= 0 ? 'text-success-deep' : 'text-error-deep' }}">{{ $signe($m->quantite) }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucune correction de stock sur cette période.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes-journal-produits">
            @forelse ($journalProduits as $j)
                @php($m = $j['m'])
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-correction="{{ $m->id }}">
                    <p class="font-bold">{{ $m->article }}</p>
                    <p class="text-caption text-outline">{{ $j['quand']->format('d/m/Y H:i') }} · {{ $j['poste'] }}</p>
                    <p class="text-xs">{{ $m->motif }}</p>
                    <p class="font-bold {{ $m->quantite >= 0 ? 'text-success-deep' : 'text-error-deep' }}">{{ $signe($m->quantite) }}</p>
                </article>
            @empty
                <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucune correction de stock sur cette période.</p>
            @endforelse
        </div>
    </section>

    <section class="rounded-lg border border-dashed border-outline-variant bg-surface-zebra p-md" data-bloc="ecarts">
        <h2 class="mb-xs text-section-title font-bold">Écarts avec le poste</h2>
        <ul class="list-disc space-y-xs pl-lg text-xs text-outline">
            <li><strong>Disponible sur le poste</strong> : stocks de début et de fin, PMP, valeur des stocks, totaux valorisés et contrôle d'équilibre — jamais estimés ici (décision du client : stock propre à chaque poste, journal partagé).</li>
            <li><strong>Export PDF</strong> : au poste uniquement, pas de bouton d'export ici.</li>
            <li>Les mouvements d'intrants viennent de <strong>tous les postes</strong> (le poste ne lit que les siens) ; la colonne « Postes » et le journal disent d'où ils viennent. Entrées et sorties se séparent par le <strong>signe</strong> de la quantité, comme au poste ; « Dont ajustements » (type Ajustement) est ajouté.</li>
            <li>Quantités affichées avec leurs <strong>décimales</strong> (le poste arrondit à l'entier). Les quantités de plusieurs unités ne sont jamais additionnées.</li>
            <li><strong>Ajouts du web</strong> : « Achats livrés » (achats au statut Livré, selon la date de commande : la réception réelle figure au journal) et « Corrections » de stock des produits (journal des postes).</li>
            <li>Les sorties de produits sont les lignes des ventes <strong>non annulées</strong>. Un produit archivé n'apparaît que s'il a bougé sur la période. Le coût de revient est celui du catalogue.</li>
            <li>Période : jours de <strong>Porto-Novo</strong>, fin <strong>incluse</strong> (de 00:00 du premier jour à 00:00 du lendemain de la fin, exclu), comme au poste. Dates saisies au clavier ou au sélecteur du navigateur.</li>
            <li>Animaux sur pied : dernier effectif <strong>réellement saisi</strong> jusqu'à la fin de la période, par filière. Œufs en incubation : lots <em>En Incubation</em> (statut actuel) à cette date, moins mirages ; le poste compare le statut avec une casse différente (« En incubation ») qui n'existe pas en base — le web utilise le statut réel.</li>
        </ul>
    </section>
</div>
