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
        <aside class="bg-brand-navy text-white md:w-64 md:shrink-0" aria-label="Navigation">
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
                @endcan
            </nav>
        </aside>

        <div class="flex min-w-0 flex-1 flex-col">
            <header class="flex items-center justify-between border-b border-outline-variant bg-surface-card px-md py-sm">
                <span class="text-sm text-outline">{{ $titre }}</span>
                @auth
                    <div class="flex items-center gap-md text-xs">
                        <span>{{ auth()->user()->name }}</span>
                        <form method="POST" action="{{ route('deconnexion') }}">
                            @csrf
                            <button type="submit" class="rounded-lg border border-outline-variant px-sm py-xs hover:bg-surface-zebra">
                                Se déconnecter
                            </button>
                        </form>
                    </div>
                @endauth
            </header>
            <main class="min-w-0 flex-1 p-md md:p-lg">
                {{ $slot }}
            </main>
        </div>
    </div>
</body>
</html>
