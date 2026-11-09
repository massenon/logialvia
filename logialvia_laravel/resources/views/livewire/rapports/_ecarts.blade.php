{{-- Écarts avec le poste (Dart) : déclarés à l'écran, onglet par onglet. --}}
<aside class="rounded-lg bg-surface-zebra p-md text-xs text-outline" data-ecart="{{ $onglet }}" aria-label="Écarts avec le poste">
    <p class="mb-xs font-bold text-on-surface">Écarts avec le poste</p>
    <ul class="list-disc space-y-xs pl-md">
        <li data-ecart-point="lecture">Lecture seule : somme des données de tous les postes. L'export est un classeur XLSX de l'onglet affiché (le poste produit un PDF).</li>
        @switch ($onglet)
            @case ('recettes')
                <li data-ecart-point="piece">« N° Pièce » : première pièce de la période pour le compte (au poste, la première enregistrée localement).</li>
                @break
            @case ('tresorerie')
                <li data-ecart-point="ordre">Mouvements d'un même jour : ordre déterministe (instant de saisie de la pièce, puis numéro de pièce, entrée avant sortie). Au poste, l'ordre suivait l'identifiant numérique, devenu un UUID.</li>
                @break
            @case ('creances')
                <li data-ecart-point="code">« Code » : « CLI- » suivi des 8 premiers caractères de l'identifiant du client (le poste numérote CLI-001, CLI-002… dans l'ordre de création local, non reproductible ici).</li>
                <li data-ecart-point="relance">La lettre de relance PDF reste au poste ; « Saisir l'encaissement » mène à Clients &amp; Créances.</li>
                @break
            @case ('dettes')
                <li data-ecart-point="code">« Code » : « FRN- » suivi des 8 premiers caractères de l'identifiant du fournisseur (le poste affiche l'identifiant complet depuis le passage aux UUID).</li>
                <li data-ecart-point="annules">Les achats annulés (statut « Annulé ») sont exclus. Le poste comparait « Annulée » et les comptait encore : correction à faire au poste.</li>
                @break
            @case ('elevage')
                <li data-ecart-point="statuts">Statuts lus tels que le serveur les porte : soin « Effectué » (le poste cherchait « Réalisé » et n'affichait jamais de traitement), sujets malades = infirmerie « En cours » (le poste comptait aussi réintégrés et décédés), cycles en cours = « En Incubation » (le poste en comptait toujours 0), statut vert = « Éclosion Effectuée ».</li>
                <li data-ecart-point="pintade">Éclosion attendue d'une pintade : 28 jours, comme l'écran Couveuse (le rapport du poste comptait encore 27 jours).</li>
                <li data-ecart-point="fiches">Fiches, soins, infirmerie et couvoir : seules les données déjà reçues par le serveur sont comptées. Les cycles supprimés sont ignorés.</li>
                @break
            @case ('stocks')
                <li data-ecart-point="stock">Aucun rapport de stock au web : le stock et le PMP sont propres à chaque poste.</li>
                @break
        @endswitch
    </ul>
</aside>
