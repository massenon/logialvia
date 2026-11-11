<div>
    @php($f = \App\Support\FormatComptable::class)
    @include('livewire.comptabilite._entete')

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="lecture">
        Lecture : somme des écritures de tous les postes ; seules les notes 1 et 5 sont rédigées ici. Export : XLSX (bouton « Exporter ») et vue imprimable (« Imprimer / PDF ») ; le PDF généré du poste n'est pas reproduit.
    </p>

    @if ($message)
        <p class="mb-md rounded-lg bg-success-container p-sm text-xs font-bold text-success-deep" data-message>{{ $message }}</p>
    @endif
    @if ($erreur)
        <p class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep" role="alert" data-erreur>{{ $erreur }}</p>
    @endif

    <div class="mb-md flex flex-wrap gap-xs border-b border-outline-variant" role="tablist" data-onglets>
        @foreach ($onglets as $cle => $libelleOnglet)
            <button type="button" role="tab" wire:click="choisir('{{ $cle }}')" aria-selected="{{ $onglet === $cle ? 'true' : 'false' }}" data-onglet="{{ $cle }}"
                    class="px-md py-2.5 text-xs font-bold {{ $onglet === $cle ? 'border-b-2 border-brand-navy text-brand-navy' : 'text-outline' }}">{{ $libelleOnglet }}</button>
        @endforeach
    </div>

    {{-- ------------------------------------------------------------- Bilan --}}
    @if ($onglet === 'bilan')
        <div data-contenu="bilan">
            <div class="mb-md flex flex-wrap items-center justify-between gap-sm rounded-lg border border-outline-variant bg-surface-card p-md text-xs">
                <span class="text-outline">Situation au <span class="font-bold text-brand-navy">{{ $aujourdhui }}</span>
                    — Exercice {{ $annee }} ({{ $cloture ? 'clôturé' : 'non clôturé' }})</span>
                <span class="rounded-full px-sm py-xs text-caption font-bold {{ $bilan['equilibre'] ? 'bg-success-container text-success-deep' : 'bg-error-container text-error-deep' }}" data-equilibre>
                    {{ $bilan['equilibre'] ? 'Actif = Passif' : 'Déséquilibre de '.$f::montant(abs($bilan['total_actif'] - $bilan['total_passif'])) }}</span>
            </div>
            <div class="grid grid-cols-1 gap-md lg:grid-cols-2">
                @foreach ([['ACTIF', '(Emplois)', $bilan['actif'], $bilan['total_actif'], 'TOTAL GÉNÉRAL ACTIF', 'actif'], ['PASSIF', '(Ressources)', $bilan['passif'], $bilan['total_passif'], 'TOTAL GÉNÉRAL PASSIF', 'passif']] as [$titreColonne, $sousTitre, $postes, $total, $libelleTotal, $cle])
                    <section class="overflow-hidden rounded-lg border border-outline-variant bg-surface-card shadow-sm" data-colonne="{{ $cle }}">
                        <header class="bg-brand-navy px-md py-sm text-white"><span class="font-bold">{{ $titreColonne }}</span> <span class="text-xs text-white/70">{{ $sousTitre }}</span></header>
                        @include('livewire.comptabilite._postes', ['postes' => $postes, 'sansTotal' => true])
                        <footer class="flex justify-between border-t-2 border-brand-navy bg-brand-gold/10 px-md py-sm text-xs font-bold" data-total="{{ $cle }}">
                            <span>{{ $libelleTotal }}</span><span>{{ $f::nombre($total) }}</span>
                        </footer>
                    </section>
                @endforeach
            </div>
        </div>
    @endif

    {{-- ------------------------------------------------ Compte de Resultat --}}
    @if ($onglet === 'resultat')
        <div data-contenu="resultat" class="max-w-3xl">
            <section class="overflow-hidden rounded-lg border border-outline-variant bg-surface-card shadow-sm">
                <header class="bg-brand-navy px-md py-sm font-bold text-white">COMPTE DE RÉSULTAT — Structure en Cascade SYSCOHADA</header>
                @include('livewire.comptabilite._postes', ['postes' => $resultat['postes']])
            </section>
            <p class="mt-sm text-caption text-outline">Le Résultat Net de l'Exercice ci-dessus est calculé depuis la même source que celui affiché au Bilan (BR-CPT-005) — les deux valeurs sont toujours strictement identiques.</p>
        </div>
    @endif

    {{-- ---------------------------------------------------------- TAFIRE --}}
    @if ($onglet === 'flux')
        <div data-contenu="flux" class="max-w-3xl">
            <section class="overflow-hidden rounded-lg border border-outline-variant bg-surface-card shadow-sm">
                <header class="bg-brand-navy px-md py-sm font-bold text-white">TABLEAU DES FLUX DE TRÉSORERIE (TAFIRE simplifié)</header>
                @include('livewire.comptabilite._postes', ['postes' => $tafire['postes']])
            </section>
            <p class="my-sm text-caption text-outline">La Trésorerie à la Clôture doit être égale à la Trésorerie nette du Bilan (Trésorerie-Actif − Trésorerie-Passif) — vérification automatique ci-dessous. Elle part de la trésorerie d'ouverture : les soldes 5xx reportés par la clôture de l'exercice précédent.</p>
            <p class="rounded-lg border p-md text-xs font-bold {{ $tafireCoherent ? 'border-success-deep bg-success-container text-success-deep' : 'border-error-deep bg-error-container text-error-deep' }}" data-coherence>
                @if ($tafireCoherent)
                    Trésorerie de clôture (TAFIRE) = Trésorerie nette (Bilan) = {{ $f::montant($tresorerieBilan) }}.
                @else
                    Incohérence de {{ $f::montant(abs($ecartTafire)) }} entre la Trésorerie de clôture du TAFIRE ({{ $f::montant($tafire['tresorerie_cloture']) }}) et la Trésorerie nette du Bilan ({{ $f::montant($tresorerieBilan) }}).
                @endif
            </p>
        </div>
    @endif

    {{-- ------------------------------------------------------------ Notes --}}
    @if ($onglet === 'notes')
        <div data-contenu="notes" class="flex max-w-3xl flex-col gap-md">
            @foreach ([1, 5] as $n)
                @if ($n === 5)
                    {{-- Notes 2, 3 et 4 entre les deux redactionnelles, dans l'ordre du Dart. --}}
                    <section class="rounded-lg border border-outline-variant bg-surface-card p-md shadow-sm" data-note="2">
                        <h2 class="mb-sm text-section-title font-bold">Note 2 — {{ $titresNotes[2] }}</h2>
                        @if (count($immobilisations) === 0)
                            <p class="text-xs text-outline" data-vide>Aucune immobilisation enregistrée. Le plan comptable ne comporte aujourd'hui aucun compte de classe 2 mouvementé — les bâtiments d'élevage et le matériel doivent y être saisis pour apparaître ici.</p>
                        @else
                            <table class="w-full text-left text-xs">
                                <thead class="text-caption uppercase text-outline"><tr><th class="py-xs">Nature</th><th class="py-xs text-right">Valeur brute</th><th class="py-xs text-right">Amort. cumulés</th><th class="py-xs text-right">Valeur nette</th></tr></thead>
                                <tbody>
                                    @foreach ($immobilisations as $i)
                                        <tr><td class="py-xs">{{ $i['libelle'] }}</td><td class="py-xs text-right">{{ $f::ouTiret($i['brut']) }}</td><td class="py-xs text-right">{{ $f::ouTiret($i['amort']) }}</td><td class="py-xs text-right font-bold">{{ $f::ouTiret($i['net']) }}</td></tr>
                                    @endforeach
                                    <tr class="font-bold" data-total-note="2"><td class="py-xs">Total Immobilisations</td><td class="py-xs text-right">{{ $f::ouTiret($totalBrut) }}</td><td class="py-xs text-right">{{ $f::ouTiret($totalAmort) }}</td><td class="py-xs text-right">{{ $f::ouTiret($totalBrut - $totalAmort) }}</td></tr>
                                </tbody>
                            </table>
                        @endif
                    </section>
                    <section class="rounded-lg border border-outline-variant bg-surface-card p-md shadow-sm" data-note="3">
                        <h2 class="mb-sm text-section-title font-bold">Note 3 — {{ $titresNotes[3] }}</h2>
                        @if (count($stocks) === 0)
                            <p class="text-xs text-outline" data-vide>Aucun compte de stock (classe 3) n'est mouvementé. La valorisation des intrants est tenue par le module Stocks &amp; Achats ; sa reprise en comptabilité suppose une écriture d'inventaire, non encore automatisée.</p>
                        @else
                            <table class="w-full text-left text-xs">
                                <thead class="text-caption uppercase text-outline"><tr><th class="py-xs">Catégorie</th><th class="py-xs text-right">Valeur (FCFA)</th></tr></thead>
                                <tbody>
                                    @foreach ($stocks as $s)
                                        <tr><td class="py-xs">{{ $s['libelle'] }}</td><td class="py-xs text-right">{{ $f::ouTiret($s['final_debit'] - $s['final_credit']) }}</td></tr>
                                    @endforeach
                                    <tr class="font-bold" data-total-note="3"><td class="py-xs">Total Stocks</td><td class="py-xs text-right">{{ $f::ouTiret($totalStocks) }}</td></tr>
                                </tbody>
                            </table>
                        @endif
                    </section>
                    <section class="rounded-lg border border-outline-variant bg-surface-card p-md shadow-sm" data-note="4">
                        <h2 class="mb-sm text-section-title font-bold">Note 4 — {{ $titresNotes[4] }}</h2>
                        @if (count($tiers) === 0)
                            <p class="text-xs text-outline" data-vide>Aucune créance client ni dette fournisseur à la date de clôture : tout a été réglé comptant.</p>
                        @else
                            <table class="w-full text-left text-xs">
                                <thead class="text-caption uppercase text-outline"><tr><th class="py-xs">Compte</th><th class="py-xs">Intitulé</th><th class="py-xs">Nature</th><th class="py-xs text-right">Montant</th></tr></thead>
                                <tbody>
                                    @foreach ($tiers as $t)
                                        @php($creance = abs($t['final_debit']) >= 0.01)
                                        <tr data-tiers="{{ $t['numero'] }}"><td class="py-xs font-mono font-bold">{{ $t['numero'] }}</td><td class="py-xs">{{ $t['libelle'] }}</td><td class="py-xs text-outline">{{ $creance ? 'Créance' : 'Dette' }}</td><td class="py-xs text-right font-bold text-error-deep">{{ $f::nombre($creance ? $t['final_debit'] : $t['final_credit']) }}</td></tr>
                                    @endforeach
                                </tbody>
                            </table>
                            <p class="mt-sm text-caption text-outline">L'ancienneté des créances n'est pas reprise ici : elle se calcule sur les échéances client du module Ventes. Le suivi client par client est disponible sur l'écran Clients &amp; Créances.</p>
                        @endif
                    </section>
                @endif
                <section class="rounded-lg border border-outline-variant bg-surface-card p-md shadow-sm" data-note="{{ $n }}">
                    <div class="mb-sm flex items-center justify-between gap-sm">
                        <h2 class="text-section-title font-bold">Note {{ $n }} — {{ $titresNotes[$n] }}</h2>
                        @if ($peutGerer)
                            <button type="button" wire:click="enregistrerNote({{ $n }})" data-action="enregistrer-note-{{ $n }}"
                                    class="rounded-lg bg-brand-navy px-md py-xs text-xs font-bold text-white">Enregistrer</button>
                        @endif
                    </div>
                    <textarea wire:model="notes.{{ $n }}" rows="4" @disabled(! $peutGerer) aria-label="Note {{ $n }}"
                              class="w-full rounded-lg border border-outline-variant px-md py-sm text-xs"></textarea>
                </section>
            @endforeach
        </div>
    @endif
</div>
