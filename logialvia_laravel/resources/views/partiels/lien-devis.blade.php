{{-- Lien vers l'onglet « Devis Prestations » du web (`47a2_`). A inclure dans la page Ventes :
     @include('partiels.lien-devis')   (le composant Ventes n'est pas modifie par la tranche devis). --}}
@can('view-ventes')
    <a href="/ventes/devis" data-lien="devis-prestations"
       class="inline-block rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs font-semibold text-brand-navy hover:bg-surface-zebra">Devis Prestations</a>
@endcan
