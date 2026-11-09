@props(['titre' => null])
@php
    $groupes = auth()->check() ? \App\Support\Navigation::pourUtilisateur(auth()->user()) : [];
    $chemin = '/'.ltrim(request()->path(), '/');
@endphp
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $titre ?? 'LogiALVIA' }} — LogiALVIA</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="min-h-screen">
    <div class="flex min-h-screen flex-col md:flex-row">
        {{-- Barre laterale : transcrite du Dart (`navigation_model.dart`), filtree par droits et modules. --}}
        <aside class="bg-brand-navy text-white md:w-64 md:shrink-0 print:hidden" aria-label="Navigation">
            <div class="px-md py-md">
                <a href="/dashboard" class="text-section-title font-bold">Logi<span class="text-brand-gold-light">ALVIA</span></a>
                <p class="text-xs text-white/70">ALLMANY ET COMPAGNIE</p>
            </div>
            <nav class="px-sm pb-md">
                @foreach ($groupes as $groupe)
                    <p class="mt-md px-sm text-xs font-bold tracking-wide text-white/60">{{ $groupe['titre'] }}</p>
                    <ul>
                        @foreach ($groupe['entrees'] as $entree)
                            @php($actif = $chemin === $entree['route'])
                            <li>
                                <a href="{{ $entree['route'] }}"
                                   @if ($actif) aria-current="page" @endif
                                   class="block rounded-lg px-sm py-xs text-sm {{ $actif ? 'bg-brand-navy-dark font-bold text-brand-gold-light' : 'text-white/90 hover:bg-brand-navy-dark' }}">
                                    {{ $entree['libelle'] }}
                                </a>
                            </li>
                        @endforeach
                    </ul>
                @endforeach
                @can('manage-users')
                    <p class="mt-md px-sm text-xs font-bold tracking-wide text-white/60">SERVEUR</p>
                    <a href="{{ route('postes') }}"
                       class="block rounded-lg px-sm py-xs text-sm {{ $chemin === '/parametres/postes' ? 'bg-brand-navy-dark font-bold text-brand-gold-light' : 'text-white/90 hover:bg-brand-navy-dark' }}">
                        Postes &amp; Appairage
                    </a>
                    <a href="{{ route('audit') }}"
                       class="block rounded-lg px-sm py-xs text-sm {{ $chemin === '/parametres/audit' ? 'bg-brand-navy-dark font-bold text-brand-gold-light' : 'text-white/90 hover:bg-brand-navy-dark' }}">
                        Journal d'Audit
                    </a>
                @endcan
            </nav>
        </aside>

        <div class="flex min-w-0 flex-1 flex-col">
            <header class="flex items-center justify-between border-b border-outline-variant bg-surface-card px-md py-sm print:hidden">
                <span class="text-sm text-outline">{{ $titre }}</span>
                @auth
                    {{-- Menu du compte : Profil, Aide, Contact, deconnexion (sans JS : <details>). --}}
                    <details class="relative text-xs" data-menu="compte">
                        <summary class="flex cursor-pointer list-none items-center gap-sm rounded-lg border border-outline-variant px-sm py-xs hover:bg-surface-zebra">
                            <span class="font-semibold">{{ auth()->user()->name }}</span>
                            <span aria-hidden="true">▾</span>
                        </summary>
                        <div class="absolute right-0 z-40 mt-xs w-56 rounded-lg border border-outline-variant bg-surface-card py-xs shadow-lg">
                            <a href="/profil" class="block px-md py-sm hover:bg-surface-zebra">Mon Profil</a>
                            <a href="/aide" class="block px-md py-sm hover:bg-surface-zebra">Aide &amp; À Propos</a>
                            <a href="/contact" class="block px-md py-sm hover:bg-surface-zebra">Contact éditeur</a>
                            <form method="POST" action="{{ route('deconnexion') }}" class="border-t border-outline-variant">
                                @csrf
                                <button type="submit" class="block w-full px-md py-sm text-left text-error-deep hover:bg-error-container">Se déconnecter</button>
                            </form>
                        </div>
                    </details>
                @endauth
            </header>
            <main class="min-w-0 flex-1 p-md md:p-lg print:p-0">
                {{ $slot }}
            </main>
        </div>
    </div>
</body>
</html>
