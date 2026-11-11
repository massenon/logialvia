<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <div>
            <h1 class="flex items-center gap-xs text-page-title font-bold text-brand-navy"><x-icone nom="vaccines" class="text-[24px]" />Soins &amp; Calendrier</h1>
            <p class="mt-xs text-xs text-outline">Registre des soins, calendrier de prophylaxie et suivi des sujets isolés. Le stock vétérinaire se décrémente sur le poste.</p>
        </div>
        @if ($peutGerer)
            <button type="button" wire:click="nouveauSoin"
                    class="flex items-center gap-xs rounded-full bg-brand-navy px-md py-sm text-xs font-bold text-white shadow-sm hover:bg-brand-navy-dark">
                <x-icone nom="add_circle" class="text-[18px]" />Nouveau Soin
            </button>
        @endif
    </div>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-navy bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Doses Administrées (Mois)</span><x-icone nom="vaccines" class="text-[18px] text-brand-navy" /></div>
            <p class="text-page-title font-bold" data-kpi="doses">{{ $kpi['doses'] }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-brand-gold bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Planifiées à Venir</span><x-icone nom="event_upcoming" class="text-[18px] text-brand-gold" /></div>
            <p class="text-page-title font-bold" data-kpi="planifiees">{{ $kpi['planifiees'] }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-info-blue bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">En Quarantaine / Traitement</span><x-icone nom="medication" class="text-[18px] text-info-blue" /></div>
            <p class="text-page-title font-bold" data-kpi="quarantaine">{{ $kpi['quarantaine'] }}</p>
        </div>
        <div class="rounded-lg border border-outline-variant border-l-4 border-l-success-deep bg-white p-md shadow-sm">
            <div class="flex items-start justify-between"><span class="text-caption font-bold uppercase text-outline">Coût Vétérinaire (Mois)</span><x-icone nom="payments" class="text-[18px] text-success-deep" /></div>
            <p class="text-page-title font-bold" data-kpi="cout">{{ number_format($kpi['cout'], 0, ',', ' ') }} <span class="text-xs font-normal text-outline">FCFA</span></p>
        </div>
    </div>

    @if ($remanences->isNotEmpty())
        <div class="mb-md rounded-lg border border-error-deep/30 bg-error-container p-sm text-xs text-error-deep" data-section="remanences">
            <p class="font-bold">{{ $remanences->count() }} délai(s) d'attente en cours — produits non commercialisables</p>
            @foreach ($remanences as $r)
                <p>{{ $toutesEspeces[$r->espece] ?? $r->espece }} · {{ $r->type_soin }}@if ($r->produit) ({{ $r->produit }})@endif —
                    jusqu'au {{ $r->date_prevue->copy()->addDays($r->remanence_jours)->format('d/m/Y') }}</p>
            @endforeach
        </div>
    @endif

    <div class="mb-md flex gap-xs overflow-x-auto border-b border-outline-variant" role="tablist">
        @foreach (['registre' => ['Registre des Soins', 'medical_information'], 'calendrier' => ['Calendrier des Doses', 'event_repeat'], 'infirmerie' => ['Suivi Infirmerie', 'monitor_heart']] as $cle => [$libelle, $iconeOnglet])
            <button type="button" role="tab" wire:click="choisirOnglet('{{ $cle }}')" aria-selected="{{ $onglet === $cle ? 'true' : 'false' }}"
                    class="flex items-center gap-1 whitespace-nowrap border-b-2 px-md py-2.5 text-xs font-bold {{ $onglet === $cle ? 'border-brand-navy text-brand-navy' : 'border-transparent text-outline' }}">
                <x-icone :nom="$iconeOnglet" class="text-[16px]" />{{ $libelle }}
            </button>
        @endforeach
    </div>

    {{-- ------------------------------------------------------- Registre --}}
    @if ($onglet === 'registre')
        <div class="mb-md flex flex-col gap-sm rounded-lg border border-outline-variant bg-white p-md sm:flex-row sm:items-center">
            <select wire:model.live="filtreType" aria-label="Catégorie" class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
                <option value="">Toutes catégories</option>
                @foreach ($types as $t)<option value="{{ $t }}">{{ $t }}</option>@endforeach
            </select>
            <select wire:model.live="filtreEspece" aria-label="Espèce" class="rounded-lg border border-outline-variant bg-surface-card px-md py-sm text-xs">
                <option value="">Toutes espèces</option>
                @foreach ($toutesEspeces as $id => $libelle)<option value="{{ $id }}">{{ $libelle }}</option>@endforeach
            </select>
        </div>

        <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block" data-section="registre">
            <table class="w-full text-left text-xs">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Date</th>
                        <th class="px-md py-sm">Lot / Espèce</th>
                        <th class="px-md py-sm">Type d'action</th>
                        <th class="px-md py-sm">Produit</th>
                        <th class="px-md py-sm">Dose</th>
                        <th class="px-md py-sm text-center">Statut</th>
                        @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                    </tr>
                </thead>
                <tbody>
                    @forelse ($soins as $s)
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-soin="{{ $s->id }}">
                            <td class="px-md py-sm">{{ $s->date_prevue->format('d/m/Y') }}</td>
                            <td class="px-md py-sm">{{ $toutesEspeces[$s->espece] ?? $s->espece }}@if ($s->bande_id && isset($codesBande[$s->bande_id])) <span class="text-caption text-outline" data-bande-soin>· {{ $codesBande[$s->bande_id] }}</span>@endif</td>
                            <td class="px-md py-sm">{{ $s->type_soin }}</td>
                            <td class="px-md py-sm">{{ $s->produit ?? '—' }}</td>
                            <td class="px-md py-sm">{{ $s->dose ?? '—' }}</td>
                            <td class="px-md py-sm text-center">
                                @if ($s->statut === 'Effectué')
                                    <span class="font-bold text-success-deep">Administré</span>
                                @else
                                    <span class="font-bold {{ $s->statut === 'En retard' ? 'text-error-deep' : ($s->statut === 'Traitement en cours' ? 'text-info-blue' : 'text-brand-gold') }}">{{ $s->statut }}</span>
                                @endif
                            </td>
                            @if ($peutGerer)
                                <td class="px-md py-sm text-right">
                                    @if ($s->statut !== 'Effectué')
                                        <button type="button" wire:click="confirmerAdministration('{{ $s->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Confirmer</button>
                                    @endif
                                </td>
                            @endif
                        </tr>
                    @empty
                        <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucun soin enregistré. Utilisez « Nouveau Soin » pour en consigner un, ou planifiez une intervention à venir.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>

        <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @forelse ($soins as $s)
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-soin="{{ $s->id }}">
                    <p class="font-bold">{{ $s->type_soin }}</p>
                    <p class="mb-xs text-caption text-outline">{{ $s->date_prevue->format('d/m/Y') }} · {{ $toutesEspeces[$s->espece] ?? $s->espece }}@if ($s->produit) · {{ $s->produit }}@endif</p>
                    <p class="text-xs font-bold">{{ $s->statut === 'Effectué' ? 'Administré' : $s->statut }}</p>
                    @if ($peutGerer && $s->statut !== 'Effectué')
                        <button type="button" wire:click="confirmerAdministration('{{ $s->id }}')" class="mt-sm w-full rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Confirmer</button>
                    @endif
                </article>
            @empty
                <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun soin enregistré.</p>
            @endforelse
        </div>
    @endif

    {{-- ----------------------------------------------------- Calendrier --}}
    @if ($onglet === 'calendrier')
        <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
            <h2 class="text-section-title font-bold">Calendrier des Doses — {{ $moisLibelle }}</h2>
            @if ($peutGerer)
                <button type="button" wire:click="nouvelleIntervention"
                        class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Planifier une Intervention</button>
            @endif
        </div>

        <div class="mb-md flex flex-wrap items-center gap-lg text-caption" data-legende>
            @foreach ([['Effectué', 'bg-success-deep'], ['Planifié', 'bg-brand-gold'], ['En retard', 'bg-error-deep'], ['Traitement en cours', 'bg-info-blue']] as [$lib, $coul])
                <span class="flex items-center gap-xs"><span class="inline-block h-3 w-3 rounded-full {{ $coul }}"></span>{{ $lib }}</span>
            @endforeach
        </div>

        @if ($lignes->isEmpty())
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucune intervention programmée ce mois-ci. Le calendrier se remplira dès la première planification.</p>
        @else
            <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block" data-section="calendrier">
                <table class="text-xs">
                    <thead class="bg-surface-zebra text-caption text-outline">
                        <tr>
                            <th class="w-40 px-md py-sm text-left font-bold uppercase">Lot / Bande</th>
                            @for ($j = 1; $j <= $nombreJours; $j++)
                                <th class="w-10 py-sm text-center font-bold {{ $j === $jourCourant ? 'bg-brand-navy/10 text-brand-navy' : '' }}">{{ $j }}</th>
                            @endfor
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($lignes as $espece => $parJour)
                            <tr class="border-t border-outline-variant" data-ligne-espece="{{ $espece }}">
                                <td class="px-md py-sm font-bold text-brand-navy">{{ $toutesEspeces[$espece] ?? $espece }}</td>
                                @for ($j = 1; $j <= $nombreJours; $j++)
                                    <td class="border-l border-outline-variant py-sm text-center">
                                        @if (isset($parJour[$j]))
                                            @php($s = $parJour[$j]->first())
                                            <span title="{{ $s->type_soin }} — {{ $s->statut }}" data-jour="{{ $j }}"
                                                  class="mx-auto flex h-7 w-7 items-center justify-center rounded-full text-white shadow-sm {{ match ($s->statut) { 'Effectué' => 'bg-success-deep', 'En retard' => 'bg-error-deep', 'Traitement en cours' => 'bg-info-blue', default => 'bg-brand-gold' } }}"><x-icone nom="vaccines" class="text-[16px]" /></span>
                                        @endif
                                    </td>
                                @endfor
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>

            <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($lignes as $espece => $parJour)
                    <article class="rounded-lg border border-outline-variant bg-surface-card p-md">
                        <p class="mb-xs font-bold text-brand-navy">{{ $toutesEspeces[$espece] ?? $espece }}</p>
                        @foreach ($parJour->sortKeys() as $j => $liste)
                            @foreach ($liste as $s)
                                <p class="text-xs">{{ str_pad((string) $j, 2, '0', STR_PAD_LEFT) }}/{{ $moisLibelle }} — {{ $s->type_soin }} ({{ $s->statut }})</p>
                            @endforeach
                        @endforeach
                    </article>
                @endforeach
            </div>
        @endif
    @endif

    {{-- ------------------------------------------------------ Infirmerie --}}
    @if ($onglet === 'infirmerie')
        <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
            <h2 class="text-section-title font-bold">Suivi Infirmerie</h2>
            @if ($peutGerer)
                <button type="button" wire:click="nouvelleEntree"
                        class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">Nouvelle Entrée</button>
            @endif
        </div>
        <p class="mb-md text-xs text-outline">
            Le <strong>décès</strong> d'un sujet se déclare ici : choisissez la catégorie d'effectif pour porter la perte sur la fiche d'élevage du jour (sans catégorie, la fiche n'est pas touchée).
        </p>

        @if ($entrees->isEmpty())
            <p class="rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun sujet en infirmerie. Les entrées apparaîtront ici avec leur niveau d'isolement et leur statut.</p>
        @else
            <div class="hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block" data-section="infirmerie">
                <table class="w-full text-left text-xs">
                    <thead class="bg-surface-zebra text-caption uppercase text-outline">
                        <tr>
                            <th class="px-md py-sm">Date d'Entrée</th>
                            <th class="px-md py-sm">Lot / Sujet</th>
                            <th class="px-md py-sm">Motif</th>
                            <th class="px-md py-sm">Niveau d'Isolement</th>
                            <th class="px-md py-sm text-center">Statut</th>
                            <th class="px-md py-sm text-right">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($entrees as $e)
                            <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-entree="{{ $e->id }}">
                                <td class="px-md py-sm">{{ $e->date_entree->format('d/m/Y') }}</td>
                                <td class="px-md py-sm">{{ $e->sujet }}</td>
                                <td class="px-md py-sm">{{ $e->motif }}</td>
                                <td class="px-md py-sm">{{ $e->niveau_isolement }}</td>
                                <td class="px-md py-sm text-center font-bold">{{ $e->statut }}</td>
                                <td class="px-md py-sm text-right">
                                    @if ($e->statut === 'En cours')
                                        @if ($peutGerer)
                                            <button type="button" wire:click="reintegrer('{{ $e->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Réintégrer</button>
                                            <button type="button" wire:click="ouvrirDeces('{{ $e->id }}')" data-action="deces" class="rounded-lg border border-error-deep/40 px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Décès</button>
                                            @if ($decesEntreeId === $e->id)
                                                <div class="mt-xs flex flex-wrap items-center justify-end gap-xs text-left" data-deces-formulaire>
                                                    <select wire:model="decesCategorie" data-champ="deces-categorie" class="rounded-lg border border-outline-variant px-sm py-xs text-xs">
                                                        <option value="">Ne pas toucher la fiche d'élevage</option>
                                                        @if ($e->espece && \App\Support\FilieresElevage::existe($e->espece))
                                                            @foreach (\App\Support\FilieresElevage::configuration($e->espece)['categories'] as $i => $categorie)
                                                                <option value="{{ $i }}">Porter la perte sur : {{ $categorie[0] }}</option>
                                                            @endforeach
                                                        @endif
                                                    </select>
                                                    <button type="button" wire:click="declarerDeces" class="rounded-lg bg-error-deep px-sm py-xs font-semibold text-white">Confirmer le décès</button>
                                                    <button type="button" wire:click="annulerDeces" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold">Annuler</button>
                                                </div>
                                            @endif
                                        @endif
                                    @else
                                        <span class="text-outline">Clôturé le {{ $e->date_sortie?->format('d/m/Y') }}</span>
                                        @if ($e->statut === 'Décédé')
                                            <br><span class="text-caption {{ $e->categorie_mortalite !== null ? 'text-success-deep' : 'text-error-deep' }}">{{ $e->categorie_mortalite !== null ? 'Mortalité portée sur la fiche' : 'Mortalité non reportée' }}</span>
                                        @endif
                                    @endif
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>

            <div class="flex flex-col gap-sm sm:hidden" data-vue="cartes">
                @foreach ($entrees as $e)
                    <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-entree="{{ $e->id }}">
                        <p class="font-bold">{{ $e->sujet }}</p>
                        <p class="mb-xs text-caption text-outline">{{ $e->date_entree->format('d/m/Y') }} · {{ $e->niveau_isolement }}</p>
                        <p class="text-xs">{{ $e->motif }}</p>
                        <p class="text-xs font-bold">{{ $e->statut }}</p>
                        @if ($e->statut === 'En cours' && $peutGerer)
                            <button type="button" wire:click="reintegrer('{{ $e->id }}')" class="mt-sm w-full rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Réintégrer</button>
                        @endif
                    </article>
                @endforeach
            </div>
        @endif
    @endif

    {{-- ------------------------------------------------------------ Modales --}}
    @if ($modale === 'soin' || $modale === 'intervention')
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-modale">
            <form wire:submit="{{ $modale === 'soin' ? 'enregistrerSoin' : 'enregistrerIntervention' }}" class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-modale" class="mb-md text-modal-title font-bold">{{ $modale === 'soin' ? 'Nouveau Soin' : 'Planifier une Intervention' }}</h2>
                <div class="grid grid-cols-1 gap-sm sm:grid-cols-2">
                    <label class="text-xs sm:col-span-2">Lot / Bande *
                        <select wire:model.live="espece" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            <option value="">-- Sélectionner --</option>
                            @foreach ($especes as $id => $libelle)<option value="{{ $id }}">{{ $libelle }}</option>@endforeach
                        </select></label>
                    @if ($bandesDeLaFiliere->isNotEmpty())
                        <label class="text-xs sm:col-span-2">Bande concernée
                            <select wire:model="bandeId" data-champ="bande-soin" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                                <option value="">Aucune bande précise</option>
                                @foreach ($bandesDeLaFiliere as $b)<option value="{{ $b->id }}">{{ $b->code }}{{ $b->date_cloture ? ' (clôturée)' : '' }}</option>@endforeach
                            </select></label>
                    @endif
                    <label class="text-xs">{{ $modale === 'soin' ? 'Date du Soin *' : 'Date Prévue' }}
                        <input type="date" wire:model="dateSoin" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    @if ($modale === 'soin')
                        <label class="text-xs">Type d'Action *
                            <select wire:model="typeSoin" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                                <option value="">-- Sélectionner --</option>
                                @foreach ($types as $t)<option value="{{ $t }}">{{ $t }}</option>@endforeach
                            </select></label>
                        <label class="text-xs">Produit Utilisé
                            <input type="text" wire:model="produit" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                        <label class="text-xs">Dose
                            <input type="text" wire:model="dose" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                        <label class="text-xs">Délai d'Attente / Rémanence (jours)
                            <input type="text" inputmode="numeric" wire:model="remanence" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                        <label class="text-xs">Vétérinaire / Animalier
                            <input type="text" wire:model="veterinaire" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                        <label class="text-xs sm:col-span-2">Symptômes observés
                            <input type="text" wire:model="symptomes" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                        <label class="text-xs">Coût (FCFA)
                            <input type="text" inputmode="numeric" wire:model="cout" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                        <label class="flex items-center gap-sm text-xs sm:col-span-2">
                            <input type="checkbox" wire:model="dejaEffectue">
                            Soin déjà administré (sinon il sera enregistré comme planifié)</label>
                    @else
                        <label class="text-xs sm:col-span-2">Intervention *
                            <input type="text" wire:model="intervention" placeholder="ex : Vaccin Newcastle (Rappel)" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    @endif
                </div>
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">{{ $modale === 'soin' ? 'Enregistrer' : 'Planifier' }}</button>
                </div>
            </form>
        </div>
    @endif

    @if ($modale === 'entree')
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-modale">
            <form wire:submit="enregistrerEntree" class="w-full max-w-lg rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-modale" class="mb-md text-modal-title font-bold">Nouvelle Entrée Infirmerie</h2>
                <div class="grid grid-cols-1 gap-sm">
                    <label class="text-xs">Lot / Sujet
                        <input type="text" wire:model="sujet" placeholder="Ex. Goliath #G-014" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="text-xs">Motif
                        <input type="text" wire:model="motif" placeholder="Ex. Suspicion Newcastle" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    <label class="text-xs">Niveau d'Isolement
                        <select wire:model="niveau" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            @foreach ($niveaux as $n)<option value="{{ $n }}">{{ $n }}</option>@endforeach
                        </select></label>
                    <label class="text-xs">Filière concernée (facultatif)
                        <select wire:model="espece" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm">
                            <option value="">—</option>
                            @foreach ($especes as $id => $libelle)<option value="{{ $id }}">{{ $libelle }}</option>@endforeach
                        </select></label>
                </div>
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Enregistrer</button>
                </div>
            </form>
        </div>
    @endif
</div>
