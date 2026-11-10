<div data-onglet-actif="stocks">
    {{-- Le stock et le PMP sont propres à chaque poste (46_ §14-§15) : aucun chiffre n'est inventé. --}}
    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        @foreach (['Valeur Totale du Stock', 'Articles en Alerte', 'Références Actives'] as $libelle)
            <div class="rounded-lg border-l-4 border-outline-variant bg-surface-zebra p-md text-outline" data-carte-poste="{{ $libelle }}">
                <p class="text-caption uppercase">{{ $libelle }}</p>
                <p class="text-kpi-value font-bold">—</p>
                <p class="text-caption font-semibold">Disponible sur le poste</p>
            </div>
        @endforeach
    </div>
    <section class="mb-md rounded-lg border border-outline-variant bg-surface-zebra p-lg text-outline" data-encart="stocks">
        <h2 class="mb-sm text-section-title font-bold">Inventaire valorisé — Disponible sur le poste</h2>
        <p class="text-xs">Le stock de chaque poste (quantités, Prix Moyen Pondéré, valeur, seuils critiques) reste sur ce poste : le serveur ne le détient pas
            (décision du client : « stock propre à chaque poste + journal partagé »). Le rapport de stocks se consulte et s'exporte donc depuis le poste concerné ;
            le web n'affiche aucun chiffre de stock plutôt qu'un chiffre faux.</p>
    </section>
</div>
