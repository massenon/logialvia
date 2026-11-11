@props(['titre' => null])
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $titre ?? 'Connexion' }} — LogiALVIA</title>
    <x-pwa-tete />
    {{-- Premier affichage < 2 s (47x_) : CSS critique precharge ; Livewire/Alpine sont dans le build Vite (module differe). --}}
    <link rel="preload" href="{{ Vite::asset('resources/css/app.css') }}" as="style">
    @livewireStyles
    @livewireScriptConfig
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="bg-white text-on-surface antialiased">
    {{-- Connexion en deux volets (maquette « login », poste et web) : visuel de marque a gauche (grands ecrans seulement), formulaire a droite. --}}
    <div class="flex min-h-screen w-full">
        {{-- Largeur = min(moitie de l'ecran, hauteur de l'ecran) : le visuel (carre) s'affiche ENTIER, sans rogner ses textes ;
             si la moitie de l'ecran est plus etroite que sa hauteur, il est centre sur le fond marine. --}}
        <div class="relative hidden shrink-0 overflow-hidden bg-brand-navy-dark lg:block lg:w-[min(50vw,100vh)]" aria-hidden="true">
            {{-- Non charge sur telephone (conteneur masque + loading=lazy) : le LCP mobile n'en depend pas. --}}
            <img src="{{ asset('images/login-visuel.webp') }}" alt="" width="1000" height="1000" loading="lazy" decoding="async"
                 class="absolute inset-0 h-full w-full object-contain">
        </div>
        <main class="flex min-h-screen flex-1 items-center justify-center bg-white p-6 lg:p-12">
            <div class="w-full max-w-[560px]">
                {{ $slot }}
            </div>
        </main>
    </div>
</body>
</html>
