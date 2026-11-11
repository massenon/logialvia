{{-- Ecran de connexion : transcrit de login.html et de login_screen.dart (memes tailles, memes icones). --}}
<div x-data="{ voir: false, oubli: false }" @keydown.escape.window="oubli = false">
    {{-- Langue + version (login.html l.31-34) : informatifs, comme au poste. --}}
    <div class="mb-4 flex items-center justify-end gap-2 text-xs text-outline">
        <span class="flex items-center gap-1 rounded-full border border-outline-variant px-3 py-1.5">
            <span class="icone text-[16px]">&#xe8e2;</span><span class="hidden sm:inline">Français</span>
        </span>
        <span class="px-2 font-bold tracking-wider">{{ $version }}</span>
    </div>

    <div class="space-y-5">
        {{-- Marque --}}
        <div class="flex flex-col items-center gap-1 text-center">
            <div class="flex items-center gap-2">
                <span class="icone text-[38px] text-brand-navy">&#xeacc;</span>
                <div class="flex flex-col items-start leading-none">
                    <span class="text-[22px] font-black tracking-tight text-brand-navy">Logi<span class="text-brand-gold">ALVIA</span></span>
                    <span class="mt-0.5 text-[9px] font-extrabold uppercase tracking-widest text-brand-navy">ALLMANY ET COMPAGNIE</span>
                </div>
            </div>
            <p class="w-full border-t border-brand-navy/10 pt-1 text-[12px] font-bold uppercase tracking-[0.15em] text-brand-navy">Gestion et Suivi Avicole Intégré</p>
        </div>

        {{-- Bandeau des 7 modules (login.html l.62-70, ordre exact) --}}
        <div class="grid grid-cols-7 gap-1 border-y border-outline-variant py-3 text-center text-outline" aria-hidden="true">
            @foreach (['&#xeacc;', '&#xe1a1;', '&#xf17e;', '&#xe8b0;', '&#xe138;', '&#xef49;', '&#xe84f;'] as $icone)
                <div><span class="icone text-[16px]">{!! $icone !!}</span></div>
            @endforeach
        </div>

        <div>
            <h2 class="text-xl font-bold leading-tight text-brand-navy">Bienvenue !</h2>
            <p class="text-xs text-outline">Connectez-vous à votre espace LogiALVIA.</p>
        </div>

        @if ($erreur)
            <div role="alert" class="flex items-center gap-2 rounded-lg border border-error-deep/30 bg-error-container px-4 py-2 text-xs text-error-deep">
                <span class="icone text-[18px]">{!! str_starts_with($erreur, 'Trop de tentatives') ? '&#xef57;' : '&#xe899;' !!}</span>
                <span>{{ $erreur }}</span>
            </div>
        @endif

        <form wire:submit="connecter" class="space-y-4" novalidate>
            <div>
                <label for="identifiant" class="mb-1 block text-[12px] font-bold tracking-wider text-brand-navy">NOM D'UTILISATEUR OU EMAIL</label>
                <div class="relative">
                    <span class="icone absolute left-4 top-1/2 -translate-y-1/2 text-[18px] text-outline">&#xf0d3;</span>
                    <input id="identifiant" type="text" wire:model="identifiant" autocomplete="username" autofocus placeholder="admin"
                           class="h-11 w-full rounded-lg border border-outline-variant py-2.5 pl-11 pr-4 text-xs outline-none focus:border-brand-navy focus:ring-2 focus:ring-brand-navy @error('identifiant') border-error-deep bg-error-container @enderror">
                </div>
                @error('identifiant') <p class="mt-0.5 text-invalid text-error-deep">{{ $message }}</p> @enderror
            </div>

            <div>
                <label for="password" class="mb-1 block text-[12px] font-bold tracking-wider text-brand-navy">MOT DE PASSE</label>
                <div class="relative">
                    <span class="icone absolute left-4 top-1/2 -translate-y-1/2 text-[18px] text-outline">&#xe899;</span>
                    <input id="password" wire:model="password" autocomplete="current-password" x-bind:type="voir ? 'text' : 'password'" type="password"
                           class="h-11 w-full rounded-lg border border-outline-variant py-2.5 pl-11 pr-11 text-xs outline-none focus:border-brand-navy focus:ring-2 focus:ring-brand-navy @error('password') border-error-deep bg-error-container @enderror">
                    <button type="button" @click="voir = !voir" x-bind:aria-label="voir ? 'Masquer le mot de passe' : 'Afficher le mot de passe'"
                            class="absolute right-4 top-1/2 -translate-y-1/2 text-outline hover:text-brand-navy">
                        <span class="icone text-[18px]" x-text="voir ? '' : ''">&#xe8f4;</span>
                    </button>
                </div>
                @error('password') <p class="mt-0.5 text-invalid text-error-deep">{{ $message }}</p> @enderror
            </div>

            <div class="flex items-center justify-between text-xs">
                <label class="flex cursor-pointer items-center">
                    <input type="checkbox" wire:model="souvenir" class="h-4 w-4 rounded border-outline-variant text-brand-navy focus:ring-brand-navy">
                    <span class="ml-2 text-outline">Se souvenir de moi</span>
                </label>
                <button type="button" @click="oubli = true" class="font-semibold text-brand-navy hover:underline">Mot de passe oublié ?</button>
            </div>

            <button type="submit" wire:loading.attr="disabled"
                    class="flex h-11 w-full items-center justify-center gap-2 rounded-lg bg-brand-navy text-xs font-bold uppercase tracking-wider text-white shadow-sm transition-all hover:bg-brand-navy-dark active:scale-[0.98] disabled:opacity-50">
                <span class="icone text-[16px]">&#xe898;</span><span>Se connecter</span>
            </button>
        </form>
    </div>

    <div class="mt-6 flex items-center justify-center border-t border-outline-variant pt-4 text-center text-[12px] text-outline">
        <span>© 2026 LogiALVIA — Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB) — FAGUEZ SARL</span>
    </div>

    {{-- Modale « Mot de passe oublié » : meme texte que le poste (aucun envoi d'e-mail n'existe). --}}
    <div x-show="oubli" x-cloak class="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 p-4" @click.self="oubli = false" role="dialog" aria-modal="true" aria-labelledby="titre-oubli">
        <div class="w-full max-w-sm rounded-lg bg-white p-6 shadow-xl">
            <div class="mb-4 flex items-center justify-between">
                <h3 id="titre-oubli" class="text-lg font-bold text-brand-navy">Mot de passe oublié</h3>
                <button type="button" @click="oubli = false" aria-label="Fermer" class="text-outline hover:text-error-deep"><span class="icone">&#xe5cd;</span></button>
            </div>
            <div class="rounded-lg border border-outline-variant bg-surface-zebra p-3 text-xs leading-normal text-outline">
                <p>La réinitialisation d'un mot de passe se fait auprès de l'administratrice, depuis la gestion des utilisateurs.</p>
                <p class="mt-3">Aucun envoi d'e-mail de réinitialisation n'est disponible.</p>
            </div>
            <div class="mt-4 flex justify-end">
                <button type="button" @click="oubli = false" class="h-11 rounded-lg border border-outline-variant px-4 text-xs font-bold uppercase tracking-wider text-brand-navy hover:bg-surface-zebra">Fermer</button>
            </div>
        </div>
    </div>
</div>
