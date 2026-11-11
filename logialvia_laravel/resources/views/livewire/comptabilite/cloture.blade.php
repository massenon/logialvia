<div>
    @php($f = \App\Support\FormatComptable::class)
    @include('livewire.comptabilite._entete')

    @if ($message)
        <p class="mb-md rounded-lg bg-success-container p-sm text-xs font-bold text-success-deep" data-message>{{ $message }}</p>
    @endif
    @if ($erreur)
        <p class="mb-md rounded-lg bg-error-container p-sm text-xs font-bold text-error-deep" role="alert" data-erreur>{{ $erreur }}</p>
    @endif

    {{-- Frise des exercices, du plus ancien au plus recent. --}}
    <div class="mb-md flex flex-wrap items-center justify-center gap-sm rounded-lg border border-outline-variant bg-surface-card p-md" data-frise>
        @foreach ($frise as $a)
            @if (! $loop->first)<span class="text-outline" aria-hidden="true">→</span>@endif
            <span class="rounded-lg border px-md py-sm text-center text-xs {{ $a === $annee ? 'border-brand-navy bg-brand-navy/10 font-bold' : 'border-outline-variant' }}" data-jeton="{{ $a }}">
                <span class="block font-bold">{{ $a }}</span>
                <span class="text-caption text-outline">{{ $a === $annee ? ($cloture ? 'Clôturé' : 'En cours') : 'Exercice' }}</span>
            </span>
        @endforeach
    </div>

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-3">
        <div class="rounded-lg border-l-4 {{ $resultat < 0 ? 'border-error-deep' : 'border-success-deep' }} bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Résultat Provisoire</p>
            <p class="text-page-title font-bold" data-kpi="resultat">{{ $f::montant($resultat) }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-info-blue bg-white p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Comptes de Gestion à Solder</p>
            <p class="text-page-title font-bold" data-kpi="comptes-gestion">{{ $comptesDeGestion }}</p>
        </div>
        <div class="rounded-lg border-l-4 {{ $equilibree ? 'border-success-deep' : 'border-error-deep' }} bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Balance</p>
            <p class="text-page-title font-bold" data-kpi="balance">{{ $equilibree ? 'Équilibrée' : 'Écart '.$f::nombre(abs($ecart)) }}</p>
        </div>
    </div>

    <h2 class="mb-sm text-section-title font-bold">Clôture Périodique — exercice {{ $annee }}</h2>
    <p class="mb-sm text-xs text-outline">Un mois clôturé refuse toute nouvelle écriture à sa date, y compris celles générées automatiquement par une vente ou un achat antidaté. Seule une administratrice peut le déclôturer, et le déblocage est tracé dans le journal d'audit (BR-CPT-006).</p>
    <div class="mb-lg grid grid-cols-2 gap-sm sm:grid-cols-3 lg:grid-cols-4" data-grille="mois">
        @foreach ($noms as $i => $nom)
            @php($m = $i + 1)
            @php($clos = (bool) ($moisClos[$m] ?? false))
            <div class="flex items-center justify-between gap-sm rounded-lg border p-sm text-xs {{ $clos ? 'border-outline bg-surface-zebra' : 'border-outline-variant bg-surface-card' }}" data-mois="{{ $m }}" data-clos="{{ $clos ? '1' : '0' }}">
                <span class="font-bold">{{ $clos ? '🔒' : '🔓' }} {{ $nom }}</span>
                @if ($peutGerer && ! $cloture && (! $clos || $peutClore))
                    <button type="button" wire:click="basculerMois({{ $m }})" data-action="{{ $clos ? 'decloturer' : 'cloturer' }}"
                            title="{{ $clos ? 'Déclôturer '.$nom : 'Clôturer '.$nom }}"
                            class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">{{ $clos ? 'Déclôturer' : 'Clôturer' }}</button>
                @elseif ($clos)
                    <span class="text-caption text-outline" title="Déclôture réservée à l'administratrice">Déclôture réservée</span>
                @endif
            </div>
        @endforeach
    </div>

    <h2 class="mb-sm text-section-title font-bold">Assistant de Clôture d'Exercice ({{ $annee }} → {{ $annee + 1 }})</h2>
    <ol class="mb-lg flex flex-col gap-sm" data-assistant>
        <li class="rounded-lg border border-outline-variant bg-surface-card p-md" data-etape="1">
            <p class="font-bold">1. Travaux d'Inventaire &amp; Régularisation</p>
            <p class="text-xs text-outline">Rapprochements Espèces/Mobile Money, inventaire physique des stocks (Gestion Stocks), vérification des soldes clients et fournisseurs.</p>
            <p class="mt-sm text-xs font-bold {{ $tousMoisClos ? 'text-success-deep' : 'text-outline' }}" data-statut>
                {{ $tousMoisClos ? 'Les 12 mois de l\'exercice sont clôturés.' : 'Étape manuelle : clôturez les mois traités dans la grille ci-dessus au fur et à mesure.' }}</p>
        </li>
        <li class="rounded-lg border border-outline-variant bg-surface-card p-md" data-etape="2">
            <p class="font-bold">2. Solde des Comptes de Gestion (Classes 6, 7 &amp; 8)</p>
            <p class="text-xs text-outline">Calcul du résultat net (Produits − Charges) et écriture de solde vers le compte 131 (Bénéfice) ou 139 (Perte), journal CL au 31/12/{{ $annee }}. Les états de l'exercice se lisent « avant affectation » : cette écriture ne les modifie pas.</p>
            <p class="mt-sm text-xs font-bold {{ $equilibree ? 'text-success-deep' : 'text-outline' }}" data-statut>
                @if ($equilibree)
                    Résultat net calculé : {{ $f::montant($resultat) }} (Produits {{ $f::montant($produits) }} − Charges {{ $f::montant($charges) }}).
                @else
                    Balance déséquilibrée de {{ $f::montant(abs($ecart)) }} : le résultat ne peut pas être arrêté (BR-CPT-004).
                @endif
            </p>
        </li>
        <li class="rounded-lg border border-outline-variant bg-surface-card p-md" data-etape="3">
            <p class="font-bold">3. Affectation du Résultat</p>
            <p class="text-xs text-outline">Bénéfice : réserves (111 légale, 118 autres), dividendes à payer (465), le reste en report à nouveau créditeur (121). Perte : report à nouveau débiteur (129). Décision de l'Assemblée, saisie dans la fenêtre de clôture.</p>
            <p class="mt-sm text-xs font-bold {{ $cloture ? 'text-success-deep' : 'text-outline' }}" data-statut>
                @if ($cloture && $resultat < 0)
                    Perte de {{ $f::montant(-$resultat) }} portée au report à nouveau débiteur (129).
                @elseif ($cloture)
                    Bénéfice de {{ $f::montant($resultat) }} affecté : réserve légale {{ $f::montant($affectationCloture['reserve_legale']) }}, autres réserves {{ $f::montant($affectationCloture['autres_reserves']) }}, dividendes {{ $f::montant($affectationCloture['dividendes']) }}, report à nouveau {{ $f::montant($resultat - array_sum($affectationCloture)) }}.
                @else
                    Par défaut, tout le résultat est reporté à nouveau ({{ $resultat < 0 ? \App\Support\PlanSyscohada::REPORT_DEBITEUR : \App\Support\PlanSyscohada::REPORT_CREDITEUR }}).
                @endif
            </p>
        </li>
        <li class="rounded-lg border border-outline-variant bg-surface-card p-md" data-etape="4">
            <p class="font-bold">4. Génération des Écritures d'À-Nouveaux (RAN)</p>
            <p class="text-xs text-outline">Création de l'exercice {{ $annee + 1 }} et report des soldes de bilan (Classes 1 à 5) au 1ᵉʳ janvier {{ $annee + 1 }}, journal AN. Les classes 6, 7 et 8 ne sont jamais reportées. Verrouillage définitif de l'exercice {{ $annee }}.</p>
            @if ($cloture)
                <p class="mt-sm text-xs font-bold text-success-deep" data-statut>Exercice {{ $annee }} clôturé et verrouillé.</p>
                <p class="mt-xs text-xs text-outline" data-ouverture>{{ $ouvertureParANouveaux ? 'À-nouveaux de l\'exercice '.$annee.' écrits (journal AN).' : 'Cet exercice a été clôturé avant la génération des à-nouveaux : son ouverture est reconstituée par une clôture virtuelle de l\'exercice précédent.' }}</p>
                @if ($peutClore)
                    <button type="button" wire:click="demanderReouverture" data-action="rouvrir-exercice"
                            class="mt-sm rounded-lg border border-outline-variant px-md py-sm text-xs font-bold hover:bg-surface-zebra">Rouvrir l'Exercice {{ $annee }}</button>
                @endif
            @elseif ($peutClore)
                <button type="button" wire:click="demanderCloture" @disabled(! $equilibree) data-action="cloturer-exercice"
                        class="mt-sm rounded-lg bg-brand-navy px-md py-sm text-xs font-bold text-white disabled:opacity-50">Clôturer l'Exercice {{ $annee }}</button>
            @else
                <p class="mt-sm text-xs text-outline" data-statut>La clôture annuelle est réservée à l'administratrice.</p>
            @endif
        </li>
    </ol>

    @if ($confirmation)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-cloture" data-modale="cloture">
            <div class="max-h-full w-full max-w-lg overflow-y-auto rounded-lg bg-surface-card p-lg shadow-lg">
                <h2 id="titre-cloture" class="mb-md text-modal-title font-bold">Clôturer définitivement l'exercice {{ $annee }} ?</h2>
                <p class="mb-sm text-xs font-bold">La clôture annuelle est définitive (BR-CPT-001) :</p>
                <ul class="mb-md list-disc pl-lg text-xs">
                    <li>toutes les écritures de {{ $annee }} sont verrouillées — plus aucune vente, dépense ou correction ne pourra y être imputée ;</li>
                    <li>l'exercice {{ $annee + 1 }} est ouvert automatiquement ; les ventes et achats postérieurs s'y enregistreront ;</li>
                    <li>le résultat net arrêté est de {{ $f::montant($resultat) }} ;</li>
                    <li>une écriture saisie hors ligne sur un poste pour {{ $annee }} sera refusée, avec son motif, quand ce poste se reconnectera.</li>
                </ul>
                <p class="mb-sm text-xs">Les comptes de gestion sont soldés vers le compte {{ $resultat < 0 ? '139 (perte)' : '131 (bénéfice)' }} ; l'exercice {{ $annee + 1 }} s'ouvre avec ses à-nouveaux ({{ count($apercu['reportes']) }} compte(s) de bilan reporté(s)).</p>
                @if ($resultat > 0.01)
                    <p class="mb-sm text-xs font-bold">Affectation du bénéfice (décision de l'Assemblée)</p>
                    <div class="mb-sm grid grid-cols-1 gap-sm sm:grid-cols-3">
                        @foreach (['reserveLegale' => 'Réserve légale (111)', 'autresReserves' => 'Autres réserves (118)', 'dividendes' => 'Dividendes à payer (465)'] as $champ => $libelle)
                            <label class="text-xs">{{ $libelle }}
                                <input type="text" inputmode="numeric" wire:model.live="{{ $champ }}" data-champ="{{ $champ }}"
                                       class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-xs text-xs">
                            </label>
                        @endforeach
                    </div>
                    <p class="mb-sm text-xs font-bold" data-report>Report à nouveau créditeur (121) : {{ $f::montant($resultat - array_sum($affectationSaisie)) }}</p>
                @elseif ($resultat < -0.01)
                    <p class="mb-sm text-xs">Perte : aucun dividende ; elle est portée au report à nouveau débiteur (129).</p>
                @endif
                @if ($apercu['anomalies'] !== [])
                    <p class="mb-sm rounded-lg bg-error-container p-sm text-xs font-bold text-error-deep" role="alert" data-anomalies>{{ implode(' ', $apercu['anomalies']) }}</p>
                @endif
                <p class="mb-md rounded-lg bg-error-container p-sm text-xs font-bold text-error-deep">Cette action ne peut pas être annulée depuis l'application.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-bold">Annuler</button>
                    <button type="button" wire:click="cloturerExercice" data-action="confirmer-cloture-exercice" class="rounded-lg bg-error-deep px-md py-sm text-xs font-bold text-white">Clôturer l'exercice {{ $annee }}</button>
                </div>
            </div>
        </div>
    @endif

    @if ($confirmationReouverture)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md" role="dialog" aria-modal="true" data-modale="reouverture">
            <div class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-lg">
                <h2 class="mb-md text-modal-title font-bold">Rouvrir l'exercice {{ $annee }} ?</h2>
                <p class="mb-md text-xs">Les écritures de clôture (journal CL) de {{ $annee }} et les à-nouveaux (journal AN) de {{ $annee + 1 }} seront retirés, et l'exercice {{ $annee }} redeviendra modifiable. Vous pourrez le clôturer de nouveau : les à-nouveaux seront régénérés. L'action est tracée dans le journal d'audit.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annulerReouverture" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-bold">Annuler</button>
                    <button type="button" wire:click="rouvrirExercice" data-action="confirmer-reouverture" class="rounded-lg bg-error-deep px-md py-sm text-xs font-bold text-white">Rouvrir l'exercice {{ $annee }}</button>
                </div>
            </div>
        </div>
    @endif
</div>
