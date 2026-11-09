<div>
    <div class="mb-md">
        <h1 class="text-page-title font-bold">Paramètres Élevage</h1>
        <p class="text-xs text-outline">Configuration des barèmes utilisés automatiquement dans les fiches de saisie journalière.</p>
    </div>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    <div class="mb-md flex gap-xs overflow-x-auto border-b border-outline-variant" role="tablist">
        @foreach (['rationnement' => 'Rationnement', 'prophylaxie' => 'Calendriers Prophylaxie', 'provende' => 'Intrants de Provende', 'numerotation' => 'Numérotation Bandes & Sujets'] as $cle => $libelle)
            <button type="button" role="tab" wire:click="choisirOnglet('{{ $cle }}')" aria-selected="{{ $onglet === $cle ? 'true' : 'false' }}"
                    class="whitespace-nowrap border-b-2 px-md py-sm text-xs font-bold {{ $onglet === $cle ? 'border-brand-navy text-brand-navy' : 'border-transparent text-outline' }}">
                {{ $libelle }}
            </button>
        @endforeach
    </div>

    {{-- ------------------------------------------------------ Rationnement --}}
    @if ($onglet === 'rationnement')
        <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
            <p class="text-xs text-outline">Ration normative en grammes/tête/jour — utilisée pour le calcul automatique dans les fiches journalières.</p>
            @if ($peutGerer)
                <button type="button" wire:click="nouveauBareme" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Ajouter</button>
            @endif
        </div>

        <div class="mb-md flex flex-col gap-sm sm:flex-row">
            <input type="search" wire:model.live.debounce.300ms="rechercheRation" placeholder="Rechercher un stade physiologique…" aria-label="Rechercher un stade"
                   class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">
            <select wire:model.live="especeRation" aria-label="Espèce" class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
                <option value="">Toutes espèces</option>
                @foreach ($toutesEspeces as $id => $libelle)
                    @if (in_array($id, \App\Support\FilieresElevage::PARAMETRABLES, true))<option value="{{ $id }}">{{ $libelle }}</option>@endif
                @endforeach
            </select>
        </div>

        <p class="mb-sm text-xs font-bold" data-kpi="baremes">{{ $baremes->count() }} barème(s)</p>
        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block" data-section="baremes">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Espèce</th>
                        <th class="px-md py-sm">Stade physiologique</th>
                        <th class="px-md py-sm text-right">Ration (g/tête/j)</th>
                        <th class="px-md py-sm">Confirmé ?</th>
                        @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                    </tr>
                </thead>
                <tbody>
                    @forelse ($baremes as $b)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-bareme="{{ $b->espece }}/{{ $b->stade }}">
                            <td class="px-md py-sm">{{ $toutesEspeces[$b->espece] ?? $b->espece }}</td>
                            <td class="px-md py-sm">{{ $b->stade }}</td>
                            <td class="px-md py-sm text-right font-bold">{{ $b->ration_grammes_par_jour }} g/j</td>
                            <td class="px-md py-sm">
                                @if ($b->confirme)
                                    <span class="font-bold text-success-deep">{{ $b->espece === 'lapins' ? 'Confirmé (Référence Cuniculture)' : 'Validé' }}</span>
                                @elseif (in_array($b->espece, ['escargots', 'bovins'], true))
                                    <span class="font-bold text-brand-gold">Repère à valider</span>
                                @else
                                    <span class="font-bold text-brand-gold">Générique (Aviculture, à confirmer)</span>
                                @endif
                            </td>
                            @if ($peutGerer)
                                <td class="px-md py-sm text-right">
                                    <button type="button" wire:click="modifierBareme('{{ $b->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier la ration</button>
                                    @if ($peutArchiver)
                                        <button type="button" wire:click="demanderSuppression('bareme', '{{ $b->id }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer</button>
                                    @endif
                                </td>
                            @endif
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun barème ne correspond à ces filtres.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @forelse ($baremes as $b)
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-bareme="{{ $b->espece }}/{{ $b->stade }}">
                    <p class="font-bold">{{ $toutesEspeces[$b->espece] ?? $b->espece }} — {{ $b->stade }}</p>
                    <p class="text-xs">{{ $b->ration_grammes_par_jour }} g/j · {{ $b->confirme ? 'Validé' : 'Repère à valider' }}</p>
                    @if ($peutGerer)
                        <div class="mt-sm flex gap-sm">
                            <button type="button" wire:click="modifierBareme('{{ $b->id }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Modifier la ration</button>
                            @if ($peutArchiver)<button type="button" wire:click="demanderSuppression('bareme', '{{ $b->id }}')" class="flex-1 rounded-lg border border-error-deep px-sm py-sm text-xs font-semibold text-error-deep">Supprimer</button>@endif
                        </div>
                    @endif
                </article>
            @empty
                <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun barème ne correspond à ces filtres.</p>
            @endforelse
        </div>

        @if ($afficherTaux)
            <div class="mb-md mt-lg flex flex-wrap items-center justify-between gap-sm">
                <h2 class="text-section-title font-bold">Taux de ration par classe de poids</h2>
                @if ($peutGerer)
                    <button type="button" wire:click="nouveauTaux" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Ajouter une classe</button>
                @endif
            </div>
            <p class="mb-sm text-xs text-outline">
                Pour les filières rationnées sur le poids vif (bovins, en matière sèche ; poissons-chats, en biomasse) : la provende du jour = pesée totale du lot × taux de la classe du poids moyen. Sans pesée, la fiche retombe sur la ration par tête du tableau ci-dessus.
            </p>
            @if ($tauxClasses->isEmpty())
                <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucune classe de poids : la provende se calcule par tête.</p>
            @else
                <div class="overflow-x-auto rounded-lg border border-outline-variant bg-surface-card" data-section="taux">
                    <table class="w-full text-left text-xs">
                        <thead class="bg-surface-zebra text-caption uppercase text-outline">
                            <tr>
                                <th class="px-md py-sm">Espèce</th>
                                <th class="px-md py-sm">Classe de poids vif</th>
                                <th class="px-md py-sm text-right">Taux (% du poids vif / j, en MS)</th>
                                <th class="px-md py-sm">Confirmé ?</th>
                                @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                            </tr>
                        </thead>
                        <tbody>
                            @foreach ($tauxClasses as $t)
                                <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-taux="{{ $t->espece }}/{{ $t->poids_min_g }}">
                                    <td class="px-md py-sm">{{ $toutesEspeces[$t->espece] ?? $t->espece }}</td>
                                    <td class="px-md py-sm">{{ $t->libelleClasse() }}</td>
                                    <td class="px-md py-sm text-right font-bold">{{ str_replace('.', ',', (string) $t->taux_pourcent) }} %</td>
                                    <td class="px-md py-sm"><span class="font-bold {{ $t->confirme ? 'text-success-deep' : 'text-brand-gold' }}">{{ $t->confirme ? 'Validé' : 'Repère à valider' }}</span></td>
                                    @if ($peutGerer)
                                        <td class="px-md py-sm text-right">
                                            <button type="button" wire:click="modifierTaux('{{ $t->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier la classe</button>
                                            @if ($peutArchiver)
                                                <button type="button" wire:click="demanderSuppression('taux', '{{ $t->id }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer la classe</button>
                                            @endif
                                        </td>
                                    @endif
                                </tr>
                            @endforeach
                        </tbody>
                    </table>
                </div>
            @endif
        @endif
    @endif

    {{-- ------------------------------------------------------ Prophylaxie --}}
    @if ($onglet === 'prophylaxie')
        <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
            <p class="text-xs text-outline">Calendrier daté depuis la mise en bande, puis affiché dans « Traitements &amp; Prophylaxie » des fiches journalières.</p>
            @if ($peutGerer)
                <button type="button" wire:click="nouvelleEcheance" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Ajouter une Échéance</button>
            @endif
        </div>

        <div class="mb-md flex flex-col gap-sm sm:flex-row">
            <select wire:model.live="especeProphylaxie" aria-label="Espèce" class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
                @foreach ($especes as $id => $libelle)<option value="{{ $id }}">{{ $libelle }}</option>@endforeach
            </select>
            <input type="search" wire:model.live.debounce.300ms="rechercheProphylaxie" placeholder="Rechercher un traitement, un produit…" aria-label="Rechercher une échéance"
                   class="w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">
        </div>

        <h2 class="mb-sm text-section-title font-bold">Calendrier — {{ $toutesEspeces[$especeProphylaxie] ?? $especeProphylaxie }}</h2>
        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block" data-section="echeances">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm text-center">Jour du cycle</th>
                        <th class="px-md py-sm">Traitement</th>
                        <th class="px-md py-sm">Produit</th>
                        <th class="px-md py-sm">Dose</th>
                        <th class="px-md py-sm text-center">Rémanence</th>
                        @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                    </tr>
                </thead>
                <tbody>
                    @forelse ($echeances as $e)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-echeance="{{ $e->id }}">
                            <td class="px-md py-sm text-center font-bold">J{{ $e->jour_cycle }}</td>
                            <td class="px-md py-sm">{{ $e->traitement }}</td>
                            <td class="px-md py-sm">{{ $e->produit }}</td>
                            <td class="px-md py-sm {{ $e->dose === null ? 'text-outline' : '' }}">{{ $e->dose ?? 'Dose non renseignée' }}</td>
                            <td class="px-md py-sm text-center">{{ $e->remanence_jours > 0 ? $e->remanence_jours.'j' : '—' }}</td>
                            @if ($peutGerer)
                                <td class="px-md py-sm text-right">
                                    <button type="button" wire:click="modifierEcheance('{{ $e->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Éditer</button>
                                    @if ($peutArchiver)
                                        <button type="button" wire:click="demanderSuppression('echeance', '{{ $e->id }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer</button>
                                    @endif
                                </td>
                            @endif
                        </tr>
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucune échéance ne correspond à ces filtres.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @forelse ($echeances as $e)
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-echeance="{{ $e->id }}">
                    <p class="font-bold">J{{ $e->jour_cycle }} — {{ $e->traitement }}</p>
                    <p class="text-xs">{{ $e->produit }} · {{ $e->dose ?? 'Dose non renseignée' }} · {{ $e->remanence_jours > 0 ? $e->remanence_jours.'j' : '—' }}</p>
                    @if ($peutGerer)
                        <div class="mt-sm flex gap-sm">
                            <button type="button" wire:click="modifierEcheance('{{ $e->id }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Éditer</button>
                            @if ($peutArchiver)<button type="button" wire:click="demanderSuppression('echeance', '{{ $e->id }}')" class="flex-1 rounded-lg border border-error-deep px-sm py-sm text-xs font-semibold text-error-deep">Supprimer</button>@endif
                        </div>
                    @endif
                </article>
            @empty
                <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucune échéance ne correspond à ces filtres.</p>
            @endforelse
        </div>
        <p class="mt-md text-xs text-outline">
            Ce calendrier est le référentiel des soins à programmer. Ses échéances sont indexées sur le jour du cycle : elles se datent depuis la mise en bande, déclarée sur chaque fiche d'élevage.
        </p>
    @endif

    {{-- ------------------------------------------------------- Provende --}}
    @if ($onglet === 'provende')
        <p class="mb-md text-xs text-outline">Intrants entrant dans la composition de la provende — synchronisés avec Gestion Stocks et la Fabrication de Provende.</p>
        <input type="search" wire:model.live.debounce.300ms="rechercheProvende" placeholder="Rechercher un intrant…" aria-label="Rechercher un intrant"
               class="mb-md w-full rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs sm:max-w-sm">
        <p class="mb-sm text-xs font-bold" data-kpi="provendes">{{ $provendes->count() }} intrant(s) de provende</p>
        @if ($provendes->isEmpty())
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun intrant de provende enregistré.</p>
        @else
            <div class="overflow-x-auto rounded-lg border border-outline-variant bg-surface-card" data-section="provendes">
                <table class="w-full text-left text-xs">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-md py-sm">Code</th>
                            <th class="px-md py-sm">Intrant</th>
                            <th class="px-md py-sm text-right">Seuil d'alerte</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($provendes as $i)
                            <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-intrant="{{ $i->code }}">
                                <td class="px-md py-sm">{{ $i->code }}</td>
                                <td class="px-md py-sm font-bold">{{ $i->name }}</td>
                                <td class="px-md py-sm text-right">{{ $i->threshold }} {{ $i->unit }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
        <p class="mt-md text-xs text-outline">
            Le <strong>stock</strong> et le <strong>prix indicatif</strong> restent propres à chaque poste : ils se lisent sur le poste. Un intrant se crée ou se modifie dans Gestion Stocks.
        </p>
    @endif

    {{-- ---------------------------------------------------- Numérotation --}}
    @if ($onglet === 'numerotation')
        <h2 class="mb-xs text-section-title font-bold">Numérotation des Bandes &amp; Sujets Par Espèce</h2>
        <p class="mb-md text-xs text-outline">Formatage des identifiants générés sur le terrain, avec aperçu en temps réel.</p>
        @unless ($peutNumeroter)
            <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-section="lecture-seule">
                Les formats de numérotation se modifient avec le droit « paramètres » (administrateur).
            </p>
        @endunless
        <form wire:submit="enregistrerNumerotation" class="rounded-lg border border-outline-variant bg-surface-card p-md" data-section="numerotation">
            <h3 class="mb-sm text-xs font-bold uppercase text-outline">Conventions par filière</h3>
            @php($groupes = [
                'Aviculture (Goliaths & Pintades)' => [['enclos', 'Préfixe Enclos', 'enclos']],
                'Cuniculture (Lapins)' => [['cage', 'Préfixe Cage', 'cage'], ['bande', 'Préfixe Bande', 'bande']],
                'Pisciculture (Poissons-Chats)' => [['bassin', 'Préfixe Bassin', 'bassin']],
                'Héliciculture (Escargots)' => [['bac', 'Préfixe Bac', 'bac']],
                'Élevage bovin (Bovins)' => [['parc', 'Préfixe Parc', 'parc']],
            ])
            <div class="grid grid-cols-1 gap-md sm:grid-cols-2">
                @foreach ($groupes as $titre => $champs)
                    <fieldset class="rounded-lg border border-outline-variant p-sm">
                        <legend class="px-xs text-xs font-bold text-brand-navy">{{ $titre }}</legend>
                        @foreach ($champs as [$cle, $libelle])
                            <label class="block text-xs">{{ $libelle }}
                                <input type="text" maxlength="4" wire:model.live="formats.{{ $cle }}" @disabled(! $peutNumeroter)
                                       class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                            <p class="mb-sm text-caption text-outline" data-apercu="{{ $cle }}">
                                Aperçu : {{ trim($formats[$cle]) }}1, {{ trim($formats[$cle]) }}2, {{ trim($formats[$cle]) }}3
                            </p>
                        @endforeach
                    </fieldset>
                @endforeach
            </div>
            @if ($erreur && $onglet === 'numerotation')
                <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
            @endif
            @if ($peutNumeroter)
                <div class="mt-md flex justify-end">
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Enregistrer Tous les Formats de Numérotation</button>
                </div>
            @endif
        </form>
    @endif

    {{-- ----------------------------------------------------------- Modales --}}
    @if ($formulaire === 'bareme-ajout' || $formulaire === 'bareme-edition')
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-modale">
            <form wire:submit="enregistrerBareme(false)" class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl">
                @if ($formulaire === 'bareme-ajout')
                    <h2 id="titre-modale" class="mb-md text-modal-title font-bold">Ajouter une Ration</h2>
                    <label class="mb-sm block text-xs">Espèce
                        <select wire:model="espece" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            @foreach ($especes as $id => $libelle)<option value="{{ $id }}">{{ $libelle }}</option>@endforeach
                        </select></label>
                    <label class="mb-sm block text-xs">Stade physiologique
                        <input type="text" wire:model="stade" placeholder="Ex. Adulte" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="mb-sm block text-xs">Ration (g/tête/j)
                        <input type="text" inputmode="numeric" wire:model="ration" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <p class="text-caption text-outline">Pour que ce barème pilote réellement le calcul de provende, le stade doit porter le libellé exact d'une catégorie de la fiche de l'espèce (par exemple « Poussins », « Goliathau », « Mature »). Un autre libellé reste documentaire.</p>
                @else
                    <h2 id="titre-modale" class="mb-md text-modal-title font-bold">Modifier — {{ $toutesEspeces[$espece] ?? $espece }} / {{ $stade }}</h2>
                    <label class="mb-sm block text-xs">Nouvelle ration (g/tête/j)
                        <input type="text" inputmode="numeric" wire:model="ration" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <p class="text-caption text-outline">La provende calculée sur la fiche {{ $toutesEspeces[$espece] ?? $espece }} sera recalculée avec cette valeur dès le prochain affichage.</p>
                @endif
                @if ($erreur)<p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>@endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    @if ($formulaire === 'bareme-edition')
                        <button type="button" wire:click="enregistrerBareme(true)" class="rounded-lg border border-success-deep px-md py-sm text-xs font-semibold text-success-deep">Valider</button>
                    @endif
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">{{ $formulaire === 'bareme-ajout' ? 'Ajouter' : 'Enregistrer' }}</button>
                </div>
            </form>
        </div>
    @endif

    @if ($formulaire === 'taux')
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-modale">
            <form wire:submit="enregistrerTaux(false)" class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-modale" class="mb-md text-modal-title font-bold">{{ $cibleId ? 'Modifier la classe de poids' : 'Ajouter une Classe de Poids' }}</h2>
                <label class="mb-sm block text-xs">Espèce
                    <select wire:model.live="espece" @disabled($cibleId !== null) class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                        @foreach ($especesPoidsVif as $id => $libelle)<option value="{{ $id }}">{{ $libelle }}</option>@endforeach
                    </select></label>
                <label class="mb-sm block text-xs">Poids minimum ({{ $unitePoids }}, compris)
                    <input type="text" inputmode="decimal" wire:model="poidsMin" placeholder="{{ $unitePoids === 'g' ? 'Ex. 20 (0 = sans minimum)' : 'Ex. 150 (0 = sans minimum)' }}" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Poids maximum ({{ $unitePoids }}, exclu) — vide = sans limite
                    <input type="text" inputmode="decimal" wire:model="poidsMax" placeholder="{{ $unitePoids === 'g' ? 'Ex. 100' : 'Ex. 300' }}" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Taux (% du poids vif ou de la biomasse par jour)
                    <input type="text" inputmode="decimal" wire:model="taux" placeholder="Ex. 3,0" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <p class="text-caption text-outline">La classe retenue est celle du poids moyen du jour (pesée totale ÷ effectif). Deux classes d'une même espèce ne peuvent pas se chevaucher. Un taux modifié reste un repère jusqu'à validation par l'animalier.</p>
                @if ($erreur)<p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>@endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    @if ($cibleId)
                        <button type="button" wire:click="enregistrerTaux(true)" class="rounded-lg border border-success-deep px-md py-sm text-xs font-semibold text-success-deep">Valider</button>
                    @endif
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">{{ $cibleId ? 'Enregistrer' : 'Ajouter' }}</button>
                </div>
            </form>
        </div>
    @endif

    @if ($formulaire === 'echeance')
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-modale">
            <form wire:submit="enregistrerEcheance" class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-modale" class="mb-xs text-modal-title font-bold">{{ $cibleId ? 'Éditer l\'Échéance de Prophylaxie' : 'Ajouter une Échéance de Prophylaxie' }}</h2>
                <p class="mb-md text-xs text-outline">Espèce : {{ $toutesEspeces[$espece] ?? $espece }}</p>
                <label class="mb-sm block text-xs">Jour du cycle *
                    <input type="text" inputmode="numeric" wire:model="jour" placeholder="Ex. 5" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Traitement *
                    <input type="text" wire:model="traitement" placeholder="Ex. Anti-coccidien" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Produit *
                    <input type="text" wire:model="produit" placeholder="Ex. Amprolium" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Dose
                    <input type="text" wire:model="dose" placeholder="Ex. 1 mL pour 50 kg, voie sous-cutanée (la notice prévaut)" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs">Rémanence (jours)
                    <input type="text" inputmode="numeric" wire:model="remanence" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @if ($erreur)<p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>@endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Enregistrer</button>
                </div>
            </form>
        </div>
    @endif

    @if ($aConfirmer)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-suppression">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-suppression" class="mb-sm text-modal-title font-bold">Confirmer la Suppression ?</h2>
                <p class="mb-md text-xs">
                    @if ($suppression['type'] === 'bareme')
                        Le barème « {{ $aConfirmer->stade }} » de {{ $toutesEspeces[$aConfirmer->espece] ?? $aConfirmer->espece }} sera supprimé.
                        La fiche journalière retombera alors sur la ration de référence de l'espèce pour cette catégorie.
                    @elseif ($suppression['type'] === 'taux')
                        La classe « {{ $aConfirmer->libelleClasse() }} » ({{ $toutesEspeces[$aConfirmer->espece] ?? $aConfirmer->espece }}, {{ str_replace('.', ',', (string) $aConfirmer->taux_pourcent) }} %) sera supprimée.
                        Un animal de ce poids n'aura plus de taux : la fiche calculera sa provende par tête.
                    @else
                        L'échéance « {{ $aConfirmer->traitement }} » (J{{ $aConfirmer->jour_cycle }}) sera retirée du calendrier de {{ $toutesEspeces[$aConfirmer->espece] ?? $aConfirmer->espece }}.
                    @endif
                    Elle quittera tous les postes ; elle se restaure depuis la corbeille d'un poste.
                </p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerSuppression" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Supprimer</button>
                </div>
            </div>
        </div>
    @endif
</div>
