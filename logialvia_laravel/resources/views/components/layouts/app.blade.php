@props(['titre' => null])
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $titre ?? 'LogiALVIA' }} — LogiALVIA</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="min-h-screen">
    {{-- Barre du haut PROVISOIRE : la coque complete (barre laterale, modules) est
         convertie du Dart avec le premier module (W4). --}}
    <header class="bg-brand-navy text-white">
        <div class="mx-auto flex max-w-screen-xl items-center justify-between px-md py-sm">
            <a href="/" class="text-section-title font-bold">LogiALVIA</a>
            @auth
                <div class="flex items-center gap-md text-xs">
                    <span>{{ auth()->user()->name }}</span>
                    <form method="POST" action="{{ route('deconnexion') }}">
                        @csrf
                        <button type="submit" class="rounded-lg border border-white/40 px-sm py-xs hover:bg-brand-navy-dark">
                            Se déconnecter
                        </button>
                    </form>
                </div>
            @endauth
        </div>
    </header>

    <main class="mx-auto max-w-screen-xl p-md md:p-lg">
        {{ $slot }}
    </main>
</body>
</html>
