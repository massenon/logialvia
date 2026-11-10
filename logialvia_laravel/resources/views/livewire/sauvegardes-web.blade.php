<div data-onglet="sauvegardes">
    <section class="rounded-lg border border-outline-variant bg-surface-card p-md">
        <h2 class="mb-sm text-section-title font-bold">Sauvegardes</h2>
        <p class="mb-md text-xs text-outline">
            Sauvegarde <strong>logique</strong> des données du serveur : un fichier JSON qui reprend ligne à ligne les {{ $tables }} tables métier
            (clients, ventes, achats, élevage, comptabilité, paramètres, journal d'audit…). Elle ne contient aucun secret : ni mot de passe,
            ni jeton de poste, ni session.
        </p>

        @if ($peutTelecharger)
            <button type="button" wire:click="telecharger" data-action="telecharger-sauvegarde"
                    class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">
                Télécharger la sauvegarde logique (JSON)
            </button>
            <p class="mt-xs text-caption text-outline">Le téléchargement est inscrit au journal d'audit.</p>
        @else
            <p class="text-xs text-outline">Le téléchargement est réservé à l'administrateur.</p>
        @endif

        <p class="mt-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="sauvegardes">
            Ce fichier n'est pas une copie de la base et le web ne sait pas le restaurer : il garde une photo lisible des données.
            Les sauvegardes complètes (création, vérification, restauration d'une copie de la base) se font sur chaque poste, dans
            Paramètres Généraux &gt; Sauvegardes. La sauvegarde de la base du serveur elle-même relève de son hébergement.
        </p>
    </section>
</div>
