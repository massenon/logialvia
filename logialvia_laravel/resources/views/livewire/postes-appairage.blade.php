<div>
    @can('view-parametres')
        <p class="mb-xs text-xs"><a wire:navigate.hover href="/parametres/generaux" class="font-semibold text-brand-navy underline">← Paramètres Généraux</a></p>
    @endcan
    <h1 class="mb-xs text-page-title font-bold">Postes &amp; Appairage</h1>
    <p class="mb-md text-xs text-outline">
        Un jeton par poste : le poste se reconnaît à son identifiant. Révoquer un poste coupe tous ses jetons ;
        il suspendra sa synchronisation et redemandera une connexion. Ses saisies non envoyées restent sur le poste.
    </p>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    {{-- >= 640 px : tableau. En dessous : cartes (rien ne doit se cacher derriere un defilement horizontal). --}}
    <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
        <table class="w-full text-left text-xs">
            <thead class="bg-surface-zebra text-caption uppercase text-outline">
                <tr>
                    <th class="px-md py-sm">Code</th>
                    <th class="px-md py-sm">Poste</th>
                    <th class="px-md py-sm">Dernier utilisateur</th>
                    <th class="px-md py-sm">Droits</th>
                    <th class="px-md py-sm">Appairé le</th>
                    <th class="px-md py-sm">Dernier contact</th>
                    <th class="px-md py-sm">État</th>
                    <th class="px-md py-sm text-right">Actions</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($postes as $poste)
                    @php($etat = $poste->etat())
                    <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-poste="{{ $poste->code }}">
                        <td class="px-md py-sm font-bold text-brand-navy">{{ $poste->code }}</td>
                        <td class="px-md py-sm font-mono" title="{{ $poste->device_id }}">{{ \Illuminate\Support\Str::substr($poste->device_id, 0, 8) }}…</td>
                        <td class="px-md py-sm">{{ $poste->dernierUtilisateur?->name ?? '—' }}</td>
                        <td class="px-md py-sm" data-droits="{{ $poste->code }}">
                            @if ($droits[$poste->id] ?? null)
                                @php($d = $droits[$poste->id])
                                <span class="font-semibold">{{ $d['compte'] }}</span> · {{ $d['roles'] }}
                                @if ($d['supprime'])
                                    <span class="font-semibold text-error-deep">(compte supprimé)</span>
                                @endif
                                <br><span class="text-outline">
                                    @if ($d['lecture_seule'])
                                        Lecture seule : rien à envoyer au serveur
                                    @else
                                        Envoie {{ $d['tables'] }} table(s) de saisies, propose {{ $d['demandes'] }} type(s) de réglages
                                    @endif
                                </span>
                            @else
                                —
                            @endif
                        </td>
                        <td class="px-md py-sm">{{ $poste->appaire_le?->timezone(config('logialvia.fuseau'))->translatedFormat('d/m/Y H:i') ?? '—' }}</td>
                        <td class="px-md py-sm">{{ $poste->dernier_contact_le?->diffForHumans() ?? 'jamais' }}</td>
                        <td class="px-md py-sm">
                            @if ($etat === 'appaire')
                                <span class="rounded-full bg-success-container px-sm py-xs font-semibold text-success-deep">Appairé</span>
                            @elseif ($etat === 'revoque')
                                <span class="rounded-full bg-error-container px-sm py-xs font-semibold text-error-deep">Révoqué</span>
                            @else
                                <span class="rounded-full bg-surface-zebra px-sm py-xs font-semibold text-outline">Sans jeton</span>
                            @endif
                        </td>
                        <td class="px-md py-sm text-right">
                            @if ($etat === 'appaire')
                                <button type="button" wire:click="demanderRevocation('{{ $poste->device_id }}')"
                                        class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">
                                    Révoquer l'appairage
                                </button>
                            @endif
                        </td>
                    </tr>
                @empty
                    <tr>
                        <td colspan="8" class="px-md py-lg text-center text-outline">
                            Aucun poste appairé. Un poste apparaît ici dès sa première connexion.
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>
    </div>

    <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
        @forelse ($postes as $poste)
            @php($etat = $poste->etat())
            <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-poste="{{ $poste->code }}">
                <div class="mb-sm flex items-center justify-between">
                    <span class="text-section-title font-bold text-brand-navy">{{ $poste->code }}</span>
                    @if ($etat === 'appaire')
                        <span class="rounded-full bg-success-container px-sm py-xs text-xs font-semibold text-success-deep">Appairé</span>
                    @elseif ($etat === 'revoque')
                        <span class="rounded-full bg-error-container px-sm py-xs text-xs font-semibold text-error-deep">Révoqué</span>
                    @else
                        <span class="rounded-full bg-surface-zebra px-sm py-xs text-xs font-semibold text-outline">Sans jeton</span>
                    @endif
                </div>
                <dl class="grid grid-cols-2 gap-xs text-xs">
                    <dt class="text-outline">Poste</dt>
                    <dd class="font-mono" title="{{ $poste->device_id }}">{{ \Illuminate\Support\Str::substr($poste->device_id, 0, 8) }}…</dd>
                    <dt class="text-outline">Dernier utilisateur</dt>
                    <dd>{{ $poste->dernierUtilisateur?->name ?? '—' }}</dd>
                    <dt class="text-outline">Droits</dt>
                    <dd data-droits-carte="{{ $poste->code }}">
                        @if ($droits[$poste->id] ?? null)
                            {{ $droits[$poste->id]['compte'] }} · {{ $droits[$poste->id]['roles'] }}
                            @if ($droits[$poste->id]['lecture_seule']) (lecture seule) @endif
                        @else
                            —
                        @endif
                    </dd>
                    <dt class="text-outline">Appairé le</dt>
                    <dd>{{ $poste->appaire_le?->timezone(config('logialvia.fuseau'))->translatedFormat('d/m/Y H:i') ?? '—' }}</dd>
                    <dt class="text-outline">Dernier contact</dt>
                    <dd>{{ $poste->dernier_contact_le?->diffForHumans() ?? 'jamais' }}</dd>
                </dl>
                @if ($etat === 'appaire')
                    <button type="button" wire:click="demanderRevocation('{{ $poste->device_id }}')"
                            class="mt-md w-full rounded-lg border border-error-deep px-sm py-sm text-xs font-semibold text-error-deep hover:bg-error-container">
                        Révoquer l'appairage
                    </button>
                @endif
            </article>
        @empty
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">
                Aucun poste appairé. Un poste apparaît ici dès sa première connexion.
            </p>
        @endforelse
    </div>

    @if ($aConfirmer)
        {{-- Modale de confirmation, pilotee par l'etat du composant (pas de @if cote JS). --}}
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true"
             aria-labelledby="titre-revocation">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-revocation" class="mb-sm text-modal-title font-bold">Révoquer l'appairage ?</h2>
                <p class="mb-md text-xs">
                    Le poste <strong>{{ $aConfirmer->code }}</strong> ne pourra plus synchroniser tant qu'il ne se sera pas
                    reconnecté. Ses saisies non envoyées restent sur le poste.
                </p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler"
                            class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerRevocation"
                            class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Révoquer l'appairage</button>
                </div>
            </div>
        </div>
    @endif
</div>
