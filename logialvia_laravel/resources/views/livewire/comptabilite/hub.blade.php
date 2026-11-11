<div>
    @php($f = \App\Support\FormatComptable::class)
    @include('livewire.comptabilite._entete')

    <div class="mb-lg flex items-start gap-sm rounded-lg border border-success-deep/30 bg-success-container p-md" data-bandeau="module">
        <x-icone nom="check_circle" class="text-[20px] text-success-deep" />
        <p class="text-xs text-success-deep"><span class="font-bold">Module Actif — Comptabilité SYSCOHADA Complète</span><br>
        <span class="text-caption text-outline">Plan Comptable, Journal, Grand Livre, Balance Générale, États Financiers (Bilan, Compte de Résultat, Flux de
        Trésorerie, Notes Annexes), Clôture Périodique et Annuelle, Comptabilité Analytique par filière.</span></p>
    </div>

    @if ($ifu !== '' && $rccm !== '')
        <div class="mb-lg flex items-start gap-sm rounded-lg border border-success-deep/30 bg-success-container p-md" data-bandeau="mecef">
            <x-icone nom="verified" class="text-[20px] text-success-deep" />
            <p class="text-xs text-success-deep"><span class="font-bold">Conformité Fiscale Électronique (MeCeF/e-MECeF) — Activable</span><br>
            <span class="text-caption text-outline">IFU ({{ $ifu }}) et RCCM ({{ $rccm }}) renseignés dans Paramètres Généraux. Le mécanisme MeCeF peut désormais être
            activé pour la facturation normalisée.</span></p>
        </div>
    @else
        <div class="mb-lg flex items-start gap-sm rounded-lg border border-error-deep/30 bg-error-container p-md" data-bandeau="mecef">
            <x-icone nom="block" class="text-[20px] text-error-deep" />
            <p class="text-xs text-error-deep"><span class="font-bold">Conformité Fiscale Électronique (MeCeF/e-MECeF) — En Attente de Configuration</span><br>
            <span class="text-caption">Renseignez l'IFU et le RCCM depuis
            <a href="/parametres/generaux" class="font-bold underline">Paramètres Généraux &gt; Données de l'Entreprise</a>.</span></p>
        </div>
    @endif

    <div class="mb-lg grid grid-cols-2 gap-md lg:grid-cols-4">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <p class="text-caption font-bold uppercase text-outline">Total Actif (Bilan)</p>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="total-actif">{{ $f::nombre($totalActif) }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <p class="text-caption font-bold uppercase text-outline">Trésorerie (Journal)</p>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="tresorerie">{{ $f::nombre($tresorerie) }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-success-deep bg-white p-md shadow-sm">
            <p class="text-caption font-bold uppercase text-outline">Résultat Cumulé</p>
            <p class="mt-xs text-kpi-value font-extrabold {{ $resultat < 0 ? 'text-error-deep' : '' }}" data-kpi="resultat">{{ $f::nombre($resultat) }} <span class="text-xs font-normal">FCFA</span></p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <p class="text-caption font-bold uppercase text-outline">Marge Nette (Analytique)</p>
            <p class="mt-xs text-kpi-value font-extrabold" data-kpi="marge">
                @if ($margeNette === null) — @else {{ str_replace('-0', '0', number_format($margeNette, 0, ',', ' ')) }} <span class="text-xs font-normal">%</span> @endif
            </p>
        </div>
    </div>

    <div class="grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3" data-grille="tuiles">
        @php($iconesTuiles = ['/comptabilite/plan' => 'list_alt', '/comptabilite/journal' => 'menu_book', '/comptabilite/grand-livre' => 'import_contacts', '/comptabilite/balance' => 'balance', '/comptabilite/etats-financiers' => 'description', '/comptabilite/bilan' => 'account_balance', '/comptabilite/cloture' => 'event_repeat', '/comptabilite/analytique' => 'insights', '/parametres/generaux' => 'toggle_on'])
        @foreach ($tuiles as [$titreTuile, $sousTitre, $route])
            @php($derniere = $route === '/parametres/generaux')
            <a href="{{ $route }}" data-tuile="{{ $route }}"
               class="flex items-center gap-sm rounded-lg p-md shadow-sm transition-all {{ $derniere ? 'bg-brand-navy hover:bg-brand-navy-dark' : 'border border-outline-variant bg-white hover:border-brand-navy hover:shadow-md' }}">
                <x-icone :nom="$iconesTuiles[$route] ?? 'description'" class="text-[28px] {{ $derniere ? 'text-brand-gold-light' : 'text-brand-navy' }}" />
                <span><span class="block text-xs font-bold {{ $derniere ? 'text-white' : 'text-brand-navy' }}">{{ $titreTuile }}</span>
                <span class="block text-caption {{ $derniere ? 'text-white/70' : 'text-outline' }}">{{ $sousTitre }}</span></span>
            </a>
        @endforeach
    </div>
</div>
