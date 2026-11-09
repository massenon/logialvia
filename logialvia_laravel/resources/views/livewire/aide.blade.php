<div>
    <div class="mb-lg border-b border-outline-variant pb-md">
        <h1 class="text-page-title font-bold">Aide &amp; À Propos</h1>
        <p class="text-xs text-outline">LogiALVIA {{ $version }} — Application de Gestion et de Suivi Avicole d'ALLMANY.</p>
    </div>

    <p class="mb-sm text-caption font-semibold uppercase text-outline">Modules du logiciel</p>
    <div class="mb-lg grid grid-cols-2 gap-md md:grid-cols-4" data-section="modules">
        @foreach ($vignettes as $v)
            <a href="{{ $v['route'] }}" class="rounded-lg border border-outline-variant bg-surface-card p-md text-center text-xs font-bold hover:bg-surface-zebra" data-vignette="{{ $v['route'] }}">
                {{ $v['libelle'] }}
            </a>
        @endforeach
    </div>

    <p class="mb-sm text-caption font-semibold uppercase text-outline">Foire aux questions</p>
    <input type="search" wire:model.live.debounce.300ms="recherche" aria-label="Rechercher dans l'aide"
           placeholder="Rechercher dans l'aide (ex : vente, stock, module...)"
           class="mb-md w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">

    @if ($questions->isEmpty())
        <p class="mb-lg rounded-lg border border-outline-variant bg-surface-card p-lg text-center text-xs text-outline">Aucun résultat pour cette recherche.</p>
    @else
        <div class="mb-lg rounded-lg border border-outline-variant bg-surface-card" data-section="faq">
            @foreach ($questions as $q)
                <details class="px-md {{ $loop->last ? '' : 'border-b border-outline-variant' }}" data-question>
                    <summary class="cursor-pointer py-md text-section-title font-bold">{{ $q['question'] }}</summary>
                    <p class="pb-md text-xs leading-relaxed text-outline">{{ $q['reponse'] }}</p>
                </details>
            @endforeach
        </div>
    @endif

    <section class="rounded-lg border border-outline-variant bg-surface-card p-md text-center" data-section="a-propos">
        <h2 class="mb-sm text-section-title font-bold">À propos</h2>
        <p class="text-xs text-outline">{{ $description }}</p>
        <p class="mt-xs text-caption text-outline">{{ $mention }}</p>
        <p class="mt-xs text-xs font-bold text-brand-navy">Version {{ $version }}</p>
        <p class="mt-sm text-caption text-outline">Éditeur : FAGUEZ SARL — <a href="/contact" class="font-semibold text-brand-navy underline">Contactez l'éditeur</a></p>
    </section>
</div>
