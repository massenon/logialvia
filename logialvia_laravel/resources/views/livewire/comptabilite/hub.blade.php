<div>
    @php($f = \App\Support\FormatComptable::class)
    @include('livewire.comptabilite._entete')

    <p class="mb-md rounded-lg bg-success-container p-md text-xs text-success-deep" data-bandeau="module">
        <span class="font-bold">Module Actif — Comptabilité SYSCOHADA Complète</span><br>
        Plan Comptable, Journal, Grand Livre, Balance Générale, États Financiers (Bilan, Compte de Résultat, Flux de
        Trésorerie, Notes Annexes), Clôture Périodique et Annuelle, Comptabilité Analytique par filière.
    </p>

    @if ($ifu !== '' && $rccm !== '')
        <p class="mb-md rounded-lg bg-success-container p-md text-xs text-success-deep" data-bandeau="mecef">
            <span class="font-bold">Conformité Fiscale Électronique (MeCeF/e-MECeF) — Activable</span><br>
            IFU ({{ $ifu }}) et RCCM ({{ $rccm }}) renseignés dans Paramètres Généraux. Le mécanisme MeCeF peut désormais être
            activé pour la facturation normalisée.
        </p>
    @else
        <p class="mb-md rounded-lg bg-error-container p-md text-xs text-error-deep" data-bandeau="mecef">
            <span class="font-bold">Conformité Fiscale Électronique (MeCeF/e-MECeF) — En Attente de Configuration</span><br>
            Renseignez l'IFU et le RCCM depuis
            <a href="/parametres/generaux" class="font-bold underline">Paramètres Généraux &gt; Données de l'Entreprise</a>.
        </p>
    @endif

    <div class="mb-lg grid grid-cols-2 gap-md lg:grid-cols-4">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Total Actif (Bilan)</p>
            <p class="text-page-title font-bold" data-kpi="total-actif">{{ $f::nombre($totalActif) }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Trésorerie (Journal)</p>
            <p class="text-page-title font-bold" data-kpi="tresorerie">{{ $f::nombre($tresorerie) }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-success-deep bg-white p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Résultat Cumulé</p>
            <p class="text-page-title font-bold {{ $resultat < 0 ? 'text-error-deep' : '' }}" data-kpi="resultat">{{ $f::nombre($resultat) }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Marge Nette (Analytique)</p>
            <p class="text-page-title font-bold" data-kpi="marge">
                @if ($margeNette === null) — @else {{ str_replace('-0', '0', number_format($margeNette, 0, ',', ' ')) }} <span class="text-xs font-normal">%</span> @endif
            </p>
        </div>
    </div>

    <div class="grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3" data-grille="tuiles">
        @foreach ($tuiles as [$titreTuile, $sousTitre, $route])
            <a href="{{ $route }}" data-tuile="{{ $route }}"
               class="block rounded-lg border border-outline-variant bg-surface-card p-md shadow-sm hover:bg-surface-zebra">
                <p class="font-bold text-brand-navy">{{ $titreTuile }}</p>
                <p class="text-xs text-outline">{{ $sousTitre }}</p>
            </a>
        @endforeach
    </div>
</div>
