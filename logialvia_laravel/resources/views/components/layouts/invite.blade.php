@props(['titre' => null, 'sansMarque' => false])
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $titre ?? 'Connexion' }} — LogiALVIA</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="bg-brand-navy-dark">
    {{-- Fond plein ecran : degrade + grain (login.html `.login-fullscreen-bg`). --}}
    <div class="fond-marque flex items-center justify-center p-lg">
        {{-- Carte : max-w 460, rounded-2xl (AppRadius.loginCard), shadow-2xl, p-8. --}}
        <div class="relative z-10 w-full max-w-[460px] rounded-2xl bg-surface-card p-6 shadow-2xl lg:p-8">
            @unless ($sansMarque)
                <h1 class="mb-md text-center text-page-title font-bold text-brand-navy">LogiALVIA</h1>
            @endunless
            {{ $slot }}
        </div>
    </div>
</body>
</html>
