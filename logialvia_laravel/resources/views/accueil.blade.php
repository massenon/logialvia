<x-layouts.app titre="Accueil">
    <h1 class="mb-sm text-page-title font-bold">Bonjour {{ auth()->user()->name }}</h1>
    <p class="mb-md text-xs text-outline">
        Le web de LogiALVIA est en construction : les écrans arrivent module par module, conformes au poste.
    </p>
    @can('manage-users')
        <a href="{{ route('postes') }}" class="text-brand-navy underline">Postes &amp; Appairage</a>
    @endcan
</x-layouts.app>
