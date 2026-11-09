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

    <p class="mt-md max-w-2xl rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="aucun-envoi">
        Cette page n'envoie aucun message : le serveur ne conserve pas de messages à l'éditeur et n'envoie pas d'e-mail.
        Écrivez directement à l'une des adresses ci-dessus, ou appelez le numéro indiqué, en précisant la version
        ({{ $version }}) et le module concerné. La rédaction et la conservation des messages se font sur le poste.
    </p>
</div>
