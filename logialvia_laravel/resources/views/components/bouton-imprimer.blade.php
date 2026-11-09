@props(['libelle' => 'Imprimer / PDF'])
{{-- Vue imprimable (doc 47u §6) : la boite d'impression du navigateur propose aussi « Enregistrer en PDF ».
     Le menu, la barre du haut et tout ce qui porte `no-print` disparaissent a l'impression (resources/css/app.css). --}}
<button type="button" onclick="window.print()" data-action="imprimer"
        {{ $attributes->merge(['class' => 'no-print rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra']) }}>
    {{ $libelle }}
</button>
