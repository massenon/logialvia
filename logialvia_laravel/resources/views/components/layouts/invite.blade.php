@props(['titre' => null])
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $titre ?? 'Connexion' }} — LogiALVIA</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="flex min-h-screen items-center justify-center bg-brand-navy p-md">
    {{-- Carte de connexion : rounded-2xl (AppRadius.loginCard). --}}
    <div class="w-full max-w-md rounded-2xl bg-surface-card p-lg shadow-xl">
        <h1 class="mb-md text-center text-page-title font-bold text-brand-navy">LogiALVIA</h1>
        {{ $slot }}
    </div>
</body>
</html>
