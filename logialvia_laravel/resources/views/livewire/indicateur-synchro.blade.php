{{-- Icône de synchronisation + modal : état réel des postes (rafraîchi toutes les 30 s). --}}
<div wire:poll.30s x-data="{ ouvert: false }" @keydown.escape.window="ouvert = false" data-synchro>
    <button type="button" @click="ouvert = true" title="{{ $texte }} — cliquer pour le détail" aria-label="État de la synchronisation : {{ $texte }}"
            class="hidden items-center gap-xs rounded-full border border-brand-gold bg-brand-gold/20 px-sm py-xs text-brand-navy hover:bg-brand-gold/30 lg:flex" data-indicateur-synchro>
        <x-icone :nom="$icone" :class="'text-[16px] '.$couleur" />
        <span class="text-caption font-bold">{{ $texte }}</span>
    </button>
    <button type="button" @click="ouvert = true" aria-label="État de la synchronisation : {{ $texte }}" class="flex lg:hidden {{ $couleur }}">
        <x-icone :nom="$icone" class="text-[22px]" />
    </button>

    <div x-show="ouvert" x-cloak class="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 p-4" @click.self="ouvert = false" x-bind:role="ouvert ? 'dialog' : false" x-bind:aria-modal="ouvert ? 'true' : false" aria-labelledby="titre-synchro">
        <div class="w-full max-w-lg rounded-lg bg-white p-6 shadow-xl">
            <div class="mb-4 flex items-center justify-between">
                <h3 id="titre-synchro" class="flex items-center gap-xs text-section-title font-bold text-brand-navy"><x-icone nom="cloud_sync" class="text-[22px]" />Synchronisation des postes</h3>
                <button type="button" @click="ouvert = false" aria-label="Fermer" class="text-outline hover:text-error-deep"><x-icone nom="close" /></button>
            </div>
            <p class="mb-3 text-xs text-outline">Le web est le serveur : les postes envoient leurs saisies et reçoivent celles des autres toutes les 5 minutes, et interrogent le serveur toutes les 30 secondes.</p>
            <div class="mb-3 rounded-lg border border-outline-variant bg-surface-zebra p-sm text-xs font-semibold {{ $couleur }}" data-synchro-resume>{{ $texte }}</div>
            <div class="max-h-72 overflow-y-auto rounded-lg border border-outline-variant">
                @forelse ($postes as $p)
                    <div class="flex items-center justify-between gap-sm border-b border-outline-variant px-md py-sm text-xs last:border-b-0" data-synchro-poste="{{ $p['code'] }}">
                        <div>
                            <p class="font-bold text-brand-navy">Poste {{ $p['code'] }}</p>
                            <p class="text-outline">{{ $p['contact'] ? 'Dernier contact '.$p['contact'] : 'Aucun contact' }}@if ($p['utilisateur']) · {{ $p['utilisateur'] }}@endif</p>
                        </div>
                        <span class="rounded-full border px-sm py-0.5 text-caption font-bold
                            {{ match ($p['etat']) {
                                'en_ligne' => 'border-success-deep bg-success-container text-success-deep',
                                'recent' => 'border-brand-gold bg-brand-gold/30 text-brand-navy',
                                'silencieux', 'jamais' => 'border-error-deep/30 bg-error-container text-error-deep',
                                default => 'border-outline-variant bg-surface-zebra text-outline',
                            } }}">{{ $p['libelle'] }}</span>
                    </div>
                @empty
                    <p class="px-md py-lg text-center text-xs text-outline">Aucun poste n'est appairé à ce serveur.</p>
                @endforelse
            </div>
            <div class="mt-4 flex justify-between gap-sm">
                <a href="{{ route('postes') }}" class="flex h-11 items-center rounded-lg bg-brand-navy px-4 text-xs font-bold uppercase tracking-wider text-white hover:bg-brand-navy-dark">Postes &amp; Appairage</a>
                <button type="button" @click="ouvert = false" class="h-11 rounded-lg border border-outline-variant px-4 text-xs font-bold uppercase tracking-wider text-brand-navy hover:bg-surface-zebra">Fermer</button>
            </div>
        </div>
    </div>
</div>
