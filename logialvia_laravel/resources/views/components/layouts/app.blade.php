@props(['titre' => null])
@php
    use App\Support\Navigation;

    $utilisateur = auth()->user();
    $groupes = $utilisateur ? Navigation::pourUtilisateur($utilisateur) : [];
    $chemin = '/'.ltrim(request()->path(), '/');
    $segments = Navigation::filDAriane($chemin) ?: array_filter([$titre]);
    $role = $utilisateur ? (config('logialvia.roles')[$utilisateur->roles->first()?->name] ?? '—') : '';
    $recherche = $utilisateur ? Navigation::entreesAccessibles($utilisateur) : [];
    $alertesBarre = $alertesBarre ?? [];

    /* Acces rapide (Dart `AccesRapide`) : [libelle, icone, route] ; `null` = separateur. Filtre par droit et module. */
    $acces = [
        ['Cycle Couveuse', 'egg', '/elevage/couveuse'], ['Fiche Goliaths', 'pets', '/elevage/goliaths'],
        ['Fiche Pintades', 'pets', '/elevage/pintades'], ['Fiche Poissons-Chats', 'set_meal', '/elevage/poissons-chats'], null,
        ['Soins & Calendrier', 'vaccines', '/elevage/soins'], null,
        ['Point de Vente', 'point_of_sale', '/ventes'], ['Gestion Stocks', 'inventory_2', '/stocks'],
        ['Tableau de Bord', 'dashboard', '/dashboard'], ['Comptabilité', 'account_balance', '/comptabilite'],
        ['Grand Livre', 'import_contacts', '/comptabilite/grand-livre'], ['États Financiers', 'description', '/comptabilite/etats-financiers'],
        ['Bilan de l\'Entreprise', 'account_balance_wallet', '/comptabilite/bilan'], ['Rapports & États', 'picture_as_pdf', '/rapports'],
    ];
    $acces = array_values(array_filter($acces, fn ($a) => $a === null || ($utilisateur && Navigation::accessible($utilisateur, $a[2]))));

    /* Barre du bas (telephone, `lg:hidden`) : les 4 raccourcis du prototype que le compte peut ouvrir. */
    $barreBas = array_values(array_filter([
        ['Tableau de Bord', 'dashboard', '/dashboard'], ['Vente', 'point_of_sale', '/ventes'],
        ['Couveuse', 'egg', '/elevage/couveuse'], ['Stock', 'inventory_2', '/stocks'],
    ], fn ($a) => $utilisateur && Navigation::accessible($utilisateur, $a[2])));
@endphp
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $titre ?? 'LogiALVIA' }} — LogiALVIA</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="bg-surface-bg text-on-surface antialiased">
    {{-- Coque de dashboard.html : barre laterale (tiroir sur telephone), barre du haut, contenu qui defile. --}}
    <div class="flex h-screen w-full overflow-hidden"
         x-data="{ menu: false, masque: false, acces: false }"
         @keydown.escape.window="menu = false; acces = false">

        {{-- Barre laterale : `w-72`, degrade, en-tete de marque, groupes, pied de compte. --}}
        <aside id="sidebar" aria-label="Navigation"
               class="sidebar-gradient fixed inset-y-0 left-0 z-50 flex h-full w-72 flex-shrink-0 flex-col overflow-hidden transition-all duration-300 lg:static print:hidden"
               x-bind:class="[menu ? 'translate-x-0' : '-translate-x-full lg:translate-x-0', masque ? 'lg:hidden' : '']">
            <div class="border-b border-white/10 px-md py-lg">
                <div class="flex items-center gap-xs">
                    <x-icone nom="egg" class="text-[26px] text-brand-gold" />
                    <a href="/dashboard" class="text-lg font-extrabold text-white">Logi<span class="text-brand-gold">ALVIA</span></a>
                </div>
                <p class="mt-xs text-[12px] uppercase tracking-wider text-white/50">ALLMANY ET COMPAGNIE</p>
            </div>

            <nav id="menu-principal" class="custom-scrollbar flex-1 overflow-y-auto px-md py-md">
                @foreach ($groupes as $groupe)
                    <p class="px-xs pt-sm text-[12px] font-bold uppercase tracking-wider text-white/40">{{ $groupe['titre'] }}</p>
                    <div class="mb-sm space-y-xs">
                        @foreach ($groupe['entrees'] as $entree)
                            @php($actif = $chemin === $entree['route'])
                            <a href="{{ $entree['route'] }}" @if ($actif) aria-current="page" @endif
                               class="flex items-center gap-sm rounded-lg px-sm py-xs transition-colors {{ $actif ? 'bg-white/[0.12] text-white' : 'text-white/90 hover:bg-white/10' }}">
                                <x-icone :nom="$entree['icone']" :class="$actif ? 'text-[20px] text-brand-gold' : 'text-[20px]'" />
                                <span class="text-[15px] {{ $actif ? 'font-bold' : '' }}">{{ $entree['libelle'] }}</span>
                            </a>
                        @endforeach
                    </div>
                @endforeach
                @can('manage-users')
                    <p class="px-xs pt-sm text-[12px] font-bold uppercase tracking-wider text-white/40">SERVEUR</p>
                    <div class="mb-sm space-y-xs">
                        @foreach ([['postes', '/parametres/postes', 'devices', 'Postes & Appairage'], ['audit', '/parametres/audit', 'history', 'Journal d\'Audit']] as [$nom, $route, $icone, $libelle])
                            @php($actif = $chemin === $route)
                            <a href="{{ route($nom) }}" @if ($actif) aria-current="page" @endif
                               class="flex items-center gap-sm rounded-lg px-sm py-xs transition-colors {{ $actif ? 'bg-white/[0.12] text-white' : 'text-white/90 hover:bg-white/10' }}">
                                <x-icone :nom="$icone" :class="$actif ? 'text-[20px] text-brand-gold' : 'text-[20px]'" />
                                <span class="text-[15px] {{ $actif ? 'font-bold' : '' }}">{{ $libelle }}</span>
                            </a>
                        @endforeach
                    </div>
                @endcan
            </nav>

            @if ($utilisateur)
                <div class="space-y-sm border-t border-white/10 p-md">
                    <div class="flex items-center gap-sm px-xs py-xs">
                        <span class="flex h-8 w-8 items-center justify-center rounded-full bg-white/10 text-white"><x-icone nom="account_circle" class="text-[18px]" /></span>
                        <div class="flex min-w-0 flex-col leading-tight">
                            <span class="truncate text-xs font-semibold text-white">{{ $utilisateur->name }}</span>
                            <span class="text-[9px] uppercase tracking-wider text-white/50">{{ $role }}</span>
                        </div>
                    </div>
                </div>
            @endif
        </aside>
        <div x-show="menu" x-cloak @click="menu = false" class="fixed inset-0 z-40 bg-black/40 lg:hidden print:hidden"></div>

        <div class="flex min-w-0 flex-1 flex-col">
            <header class="sticky top-0 z-30 flex h-16 flex-shrink-0 items-center justify-between border-b border-outline-variant bg-white px-md lg:px-lg print:hidden">
                <div class="flex min-w-0 items-center gap-md">
                    {{-- Telephone : ouvre le tiroir. --}}
                    <button type="button" data-menu-bascule aria-controls="sidebar" aria-expanded="false" aria-label="Menu"
                            x-on:click="menu = !menu; $el.setAttribute('aria-expanded', menu)" class="text-brand-navy lg:hidden">
                        <x-icone nom="menu" class="text-[26px]" />
                    </button>
                    {{-- Bureau : masque / affiche la barre laterale. --}}
                    <button type="button" x-on:click="masque = !masque" title="Afficher/Masquer la barre latérale" aria-label="Afficher ou masquer la barre latérale"
                            class="hidden text-outline hover:text-brand-navy lg:flex">
                        <x-icone nom="menu_open" class="text-[22px]" />
                    </button>
                    <nav aria-label="Fil d'Ariane" class="hidden min-w-0 items-center gap-xs text-xs text-outline sm:flex">
                        @foreach ($segments as $i => $segment)
                            @if ($i > 0)<x-icone nom="chevron_right" class="text-[15px]" />@endif
                            <span class="truncate {{ $loop->last ? 'font-bold text-brand-navy' : '' }}">{{ $segment }}</span>
                        @endforeach
                    </nav>
                </div>

                @auth
                    <div class="flex items-center gap-sm md:gap-md">
                        {{-- Recherche globale (Dart `RechercheGlobale`) : filtre les ecrans que le compte peut ouvrir. --}}
                        <div class="relative hidden w-64 md:block"
                             x-data="{ q: '', entrees: @js($recherche),
                                       plat(s) { return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase() },
                                       get resultats() { const t = this.plat(this.q.trim()); return t === '' ? [] : this.entrees.filter(e => this.plat(e.libelle).includes(t)).slice(0, 8) } }"
                             @click.outside="q = ''">
                            <div class="flex items-center gap-xs rounded-full border border-outline-variant bg-surface-zebra px-md py-xs">
                                <x-icone nom="search" class="text-[16px] text-outline" />
                                <input type="text" x-model="q" placeholder="Recherche globale…" aria-label="Recherche globale"
                                       @keydown.enter.prevent="resultats.length && (window.location.href = resultats[0].route)"
                                       @keydown.escape="q = ''"
                                       class="w-full border-0 bg-transparent p-0 text-xs outline-none placeholder:text-outline focus:ring-0">
                            </div>
                            <div x-show="resultats.length" x-cloak class="absolute right-0 z-50 mt-sm w-full overflow-hidden rounded-lg border border-outline-variant bg-white shadow-lg">
                                <template x-for="e in resultats" :key="e.route">
                                    <a :href="e.route" class="flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><span x-text="e.libelle"></span></a>
                                </template>
                            </div>
                        </div>

                        {{-- Synchronisation : état réel des postes appairés (réservé à qui gère les postes). --}}
                        @can('manage-users')
                            <livewire:indicateur-synchro />
                        @endcan

                        {{-- Notifications : les alertes critiques du tableau de bord. --}}
                        <details class="relative" data-menu="notifications">
                            <summary class="relative flex cursor-pointer list-none text-outline hover:text-brand-navy" aria-label="Notifications">
                                <x-icone nom="notifications" class="text-[24px]" />
                                @if (count($alertesBarre) > 0)
                                    <span class="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-error-deep text-[9px] font-bold text-white">{{ count($alertesBarre) }}</span>
                                @endif
                            </summary>
                            <div class="absolute right-0 z-50 mt-sm w-80 overflow-hidden rounded-lg border border-outline-variant bg-white shadow-lg">
                                <div class="border-b border-outline-variant px-md py-sm text-xs font-bold text-brand-navy">Notifications</div>
                                <div class="max-h-64 overflow-y-auto">
                                    @forelse ($alertesBarre as $alerte)
                                        <a href="{{ $alerte['route'] ?? '/dashboard' }}" class="block border-b border-outline-variant px-md py-sm last:border-b-0 hover:bg-surface-zebra">
                                            <p class="text-xs font-semibold {{ ($alerte['niveau'] ?? '') === 'critique' ? 'text-error-deep' : 'text-brand-navy' }}">{{ $alerte['texte'] }}</p>
                                        </a>
                                    @empty
                                        <p class="px-md py-sm text-xs text-outline">Aucune alerte en cours.</p>
                                    @endforelse
                                </div>
                            </div>
                        </details>

                        {{-- Menu du compte : Profil, Aide, Contact, Parametres, deconnexion (sans JS : <details>). --}}
                        <details class="relative" data-menu="compte">
                            <summary class="flex cursor-pointer list-none items-center gap-xs text-xs font-semibold text-brand-navy">
                                <x-icone nom="account_circle" class="text-[24px]" /><span class="hidden md:inline">{{ $utilisateur->name }}</span><x-icone nom="expand_more" class="text-[16px]" />
                            </summary>
                            <div class="absolute right-0 z-50 mt-sm w-52 overflow-hidden rounded-lg border border-outline-variant bg-white shadow-lg">
                                <a href="/profil" class="flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><x-icone nom="person" class="text-[16px]" />Mon Profil</a>
                                <a href="/aide" class="flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><x-icone nom="help" class="text-[16px]" />Aide &amp; À Propos</a>
                                <a href="/contact" class="flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><x-icone nom="support_agent" class="text-[16px]" />Contactez l'Éditeur</a>
                                @if (Navigation::droitPour($utilisateur, '/parametres/generaux'))
                                    <a href="/parametres/generaux" class="flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><x-icone nom="settings" class="text-[16px]" />Paramètres</a>
                                @endif
                                <form method="POST" action="{{ route('deconnexion') }}" class="border-t border-outline-variant">
                                    @csrf
                                    <button type="submit" class="flex w-full items-center gap-xs px-md py-sm text-left text-xs text-error-deep hover:bg-error-container"><x-icone nom="logout" class="text-[16px]" />Déconnexion</button>
                                </form>
                            </div>
                        </details>
                    </div>
                @endauth
            </header>

            <main class="min-w-0 flex-1 overflow-y-auto p-md pb-24 lg:p-lg lg:pb-lg print:p-0">
                {{ $slot }}
            </main>
        </div>

        {{-- Barre du bas (telephone). --}}
        @if (count($barreBas))
            <nav aria-label="Raccourcis" class="fixed bottom-0 left-0 right-0 z-40 flex h-16 items-stretch border-t border-outline-variant bg-white shadow-[0_-2px_8px_rgba(0,0,0,0.06)] lg:hidden print:hidden">
                @foreach ($barreBas as [$libelle, $icone, $route])
                    <a href="{{ $route }}" class="flex flex-1 flex-col items-center justify-center gap-0.5 {{ $chemin === $route ? 'text-brand-navy' : 'text-outline' }}">
                        <x-icone :nom="$icone" class="text-[22px]" />
                        <span class="text-[9px] font-bold">{{ $libelle }}</span>
                    </a>
                @endforeach
            </nav>
        @endif

        {{-- Acces rapide : bouton rond + panneau a droite (Dart `AccesRapide`). --}}
        @if (count($acces))
            <button type="button" @click="acces = true" title="Accès rapide Élevage & Modules" aria-label="Accès rapide"
                    class="fixed right-4 z-[60] flex h-12 w-12 items-center justify-center rounded-full bg-brand-navy text-white shadow-lg hover:bg-brand-navy-dark print:hidden" style="bottom: 88px;">
                <x-icone nom="apps" class="text-[24px]" />
            </button>
            <div x-show="acces" x-cloak @click="acces = false" class="fixed inset-0 z-[65] bg-black/40 print:hidden"></div>
            <div x-show="acces" x-cloak x-transition:enter="transition-transform duration-300" x-transition:enter-start="translate-x-full" x-transition:enter-end="translate-x-0"
                 class="fixed right-0 top-0 z-[70] flex h-full w-72 max-w-[85vw] flex-col bg-white shadow-2xl print:hidden" x-bind:role="acces ? 'dialog' : false" x-bind:aria-modal="acces ? 'true' : false" aria-label="Accès rapide">
                <div class="flex items-center justify-between border-b border-outline-variant bg-brand-navy px-md py-md">
                    <span class="flex items-center gap-xs text-sm font-bold text-white"><x-icone nom="apps" class="text-[20px] text-brand-gold" />Accès Rapide</span>
                    <button type="button" @click="acces = false" aria-label="Fermer" class="text-white/80 hover:text-white"><x-icone nom="close" /></button>
                </div>
                <div class="flex-1 space-y-xs overflow-y-auto p-sm">
                    @foreach ($acces as $a)
                        @if ($a === null)
                            <div class="my-xs border-t border-outline-variant"></div>
                        @else
                            <a href="{{ $a[2] }}" class="flex items-center gap-sm rounded-lg px-sm py-sm text-on-surface transition-colors hover:bg-surface-zebra">
                                <x-icone :nom="$a[1]" class="text-[22px] text-brand-navy" /><span class="text-[15px] font-semibold">{{ $a[0] }}</span>
                            </a>
                        @endif
                    @endforeach
                </div>
            </div>
        @endif
    </div>
</body>
</html>
