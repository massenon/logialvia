<div>
    <div class="mb-md border-b border-outline-variant pb-md">
        <h1 class="text-page-title font-bold">Contactez l'Éditeur</h1>
        <p class="text-xs text-outline">{{ $societe }} — Question générale ou signalement d'un problème technique.</p>
    </div>

    <section class="max-w-2xl rounded-lg border border-outline-variant bg-surface-card p-lg" data-section="coordonnees">
        <h2 class="mb-sm text-section-title font-bold">{{ $societe }}</h2>
        <p class="text-xs text-outline">{{ $roleSociete }}</p>

        <dl class="mt-md grid grid-cols-1 gap-sm text-xs sm:grid-cols-[10rem_1fr]">
            <dt class="font-semibold text-outline">Contact</dt>
            <dd class="font-bold">{{ $contact }} — {{ $role }}<br><span class="font-normal text-outline">{{ $qualification }}</span></dd>

            <dt class="font-semibold text-outline">Téléphone</dt>
            <dd>
                @foreach ($telephones as $tel)
                    <a href="tel:{{ str_replace(' ', '', $tel) }}" class="font-semibold text-brand-navy underline">{{ $tel }}</a>@unless ($loop->last) / @endunless
                @endforeach
            </dd>

            <dt class="font-semibold text-outline">E-mail</dt>
            <dd>
                <a href="mailto:{{ $email }}" class="font-semibold text-brand-navy underline" data-email="personnel">{{ $email }}</a><br>
                <a href="mailto:{{ $emailProfessionnel }}" class="font-semibold text-brand-navy underline" data-email="professionnel">{{ $emailProfessionnel }}</a>
                <span class="text-caption text-outline">(adresse professionnelle, à privilégier pour un signalement)</span>
            </dd>
        </dl>
    </section>

    <section class="mt-md max-w-2xl rounded-lg border border-outline-variant bg-surface-card p-lg" data-section="formulaire">
        <div class="mb-md flex gap-sm" role="tablist" aria-label="Type de message">
            <button type="button" role="tab" wire:click="choisirType('question')" aria-selected="{{ $type === 'question' ? 'true' : 'false' }}"
                    class="rounded-lg px-md py-sm text-xs font-bold {{ $type === 'question' ? 'bg-brand-navy text-white' : 'border border-outline-variant text-outline' }}">Question générale</button>
            <button type="button" role="tab" wire:click="choisirType('bug')" aria-selected="{{ $type === 'bug' ? 'true' : 'false' }}"
                    class="rounded-lg px-md py-sm text-xs font-bold {{ $type === 'bug' ? 'bg-brand-navy text-white' : 'border border-outline-variant text-outline' }}">Problème technique</button>
        </div>
        <h2 class="mb-sm text-section-title font-bold">{{ $type === 'bug' ? 'Signaler un problème technique' : 'Poser une question générale' }}</h2>

        <form wire:submit="enregistrer" class="flex flex-col gap-sm" novalidate>
            @if ($type === 'bug')
                <label class="text-caption font-semibold uppercase text-outline">Module concerné *
                    <select wire:model="module" class="mt-xs w-full rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs normal-case">
                        <option value="">-- Sélectionner --</option>
                        @foreach ($modules as $m)<option value="{{ $m }}">{{ $m }}</option>@endforeach
                    </select></label>
                <label class="text-caption font-semibold uppercase text-outline">Description du problème *
                    <textarea wire:model="message" rows="4" maxlength="10000" placeholder="Que s'est-il passé ? Qu'attendiez-vous ?"
                              class="mt-xs w-full rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs normal-case"></textarea></label>
                <label class="text-caption font-semibold uppercase text-outline">Étapes pour reproduire
                    <textarea wire:model="etapes" rows="3" maxlength="10000" placeholder="1. Aller dans... 2. Cliquer sur..."
                              class="mt-xs w-full rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs normal-case"></textarea></label>
            @else
                <label class="text-caption font-semibold uppercase text-outline">Objet *
                    <input type="text" wire:model="objet" maxlength="255" placeholder="ex : Question sur le module Comptabilité"
                           class="mt-xs w-full rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs normal-case"></label>
                <label class="text-caption font-semibold uppercase text-outline">Message *
                    <textarea wire:model="message" rows="6" maxlength="10000" placeholder="Décrivez votre question ou suggestion..."
                              class="mt-xs w-full rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs normal-case"></textarea></label>
            @endif

            @if ($erreur)<p role="alert" class="rounded-lg bg-error-container p-sm text-xs text-error-deep" data-erreur>{{ $erreur }}</p>@endif
            @if ($information)<p role="status" class="rounded-lg bg-success-container p-sm text-xs text-success-deep" data-message>{{ $information }}</p>@endif

            <div>
                <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">
                    {{ $type === 'bug' ? 'Enregistrer le rapport' : 'Enregistrer le message' }}
                </button>
            </div>
        </form>
    </section>

    <p class="mt-md max-w-2xl rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="aucun-envoi">
        Cette page n'envoie aucun e-mail : le serveur n'a pas de transport de messagerie. Le message est enregistré (et visible sur les postes
        après leur synchronisation) ; copiez son texte et transmettez-le vous-même par WhatsApp ou par e-mail à l'éditeur, puis marquez-le
        « Transmis ». Précisez la version ({{ $version }}) et le module concerné. La capture d'écran de la maquette n'existe pas.
    </p>

    <section class="mt-md max-w-2xl rounded-lg border border-outline-variant bg-surface-card p-lg" data-section="messages">
        <h2 class="mb-sm text-section-title font-bold">Messages enregistrés ({{ $messages->count() }})</h2>

        @forelse ($messages as $m)
            <article class="mb-sm rounded-lg border border-outline-variant p-sm text-xs" data-message-id="{{ $m->id }}">
                <div class="flex flex-wrap items-center justify-between gap-sm">
                    <p class="font-bold">{{ $m->estBug() ? '🐞 ' : '' }}{{ $m->sujet }}</p>
                    <span class="rounded-full px-sm py-xs text-caption font-semibold {{ $m->statut === 'Transmis' ? 'bg-success-container text-success-deep' : 'bg-brand-gold/10 text-brand-navy' }}">{{ $m->statut }}</span>
                </div>
                <p class="text-caption text-outline">{{ $m->horodatage->timezone($fuseau)->format('d/m/Y H:i') }} · {{ $m->auteur ?: '—' }}</p>
                <p class="mt-xs whitespace-pre-line">{{ $m->message }}</p>
                @if (trim((string) $m->etapes) !== '')<p class="mt-xs whitespace-pre-line text-outline">Étapes : {{ $m->etapes }}</p>@endif
                <div class="mt-sm flex flex-wrap gap-sm">
                    <button type="button" wire:click="montrerTexte('{{ $m->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Voir le texte à copier</button>
                    @if ($m->statut !== 'Transmis')
                        <button type="button" wire:click="marquerTransmis('{{ $m->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Marquer comme transmis</button>
                    @endif
                    <button type="button" wire:click="demanderSuppression('{{ $m->id }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer</button>
                </div>
                @if ($messageAffiche && $messageAffiche->id === $m->id)
                    <textarea readonly rows="8" onfocus="this.select()" aria-label="Texte à copier" data-texte-a-copier
                              class="mt-sm w-full rounded-lg border border-outline-variant bg-surface-zebra px-sm py-sm font-mono text-xs">{{ $texteACopier }}</textarea>
                @endif
            </article>
        @empty
            <p class="text-xs text-outline">Aucun message enregistré. Ceux que vous rédigez ci-dessus apparaîtront ici.</p>
        @endforelse
    </section>

    @if ($aConfirmer)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-suppr-message">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-suppr-message" class="mb-sm text-modal-title font-bold">Supprimer ce message ?</h2>
                <p class="mb-md text-xs">« {{ $aConfirmer->sujet }} » sera supprimé. Si vous ne l'avez pas encore transmis à l'éditeur, copiez-le d'abord ; l'administrateur peut le restaurer depuis la Corbeille.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerSuppression" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Supprimer</button>
                </div>
            </div>
        </div>
    @endif
</div>
