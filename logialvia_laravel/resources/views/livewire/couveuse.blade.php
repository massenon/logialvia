<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <h1 class="text-page-title font-bold">Cycle Couveuse</h1>
        <div class="flex flex-wrap items-center gap-sm">
            <label class="text-xs text-outline" for="reference-couveuse">Situation au</label>
            <input id="reference-couveuse" type="date" wire:model.live="reference"
                   class="rounded-lg border {{ $estAujourdhui ? 'border-outline-variant' : 'border-brand-gold' }} bg-surface-card px-sm py-sm text-xs">
            @unless ($estAujourdhui)
                <button type="button" wire:click="aujourdhui" class="rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">
                    Revenir à aujourd'hui
                </button>
            @endunless
            @if ($peutGerer)
                <button type="button" wire:click="nouveauLot"
                        class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">
                    Déclarer un Nouveau Cycle
                </button>
            @endif
        </div>
    </div>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif

    <div class="mb-md grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-5">
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Cycles en Cours</p>
            <p class="text-page-title font-bold" data-kpi="en-cours">{{ $cyclesEnCours }}</p>
        </div>
        <div class="rounded-lg border-l-4 border-brand-navy bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Poussins Attendus</p>
            <p class="text-page-title font-bold" data-kpi="attendus">{{ $tauxBrut === null ? '—' : $poussinsAttendus }}</p>
            @if ($tauxBrut === null)
                <p class="text-caption text-outline">Nécessite au moins une éclosion enregistrée</p>
            @endif
        </div>
        <div class="rounded-lg border-l-4 border-brand-navy bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Œufs en Incubation</p>
            <p class="text-page-title font-bold" data-kpi="oeufs">{{ $oeufsEnIncubation }}</p>
            @if ($machines->isNotEmpty())
                <p class="text-caption text-outline">{{ $machines->count() }} incubateur(s)</p>
            @endif
        </div>
        <div class="rounded-lg border-l-4 border-success-deep bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Taux d'Éclosion Réel</p>
            <p class="text-page-title font-bold" data-kpi="reel">{{ \App\Support\SuiviIncubation::pourcentage($tauxReel) }}</p>
            <p class="text-caption text-outline">Après retrait des œufs clairs et gâtés</p>
        </div>
        <div class="rounded-lg border-l-4 border-brand-gold bg-surface-card p-md shadow-sm">
            <p class="text-caption uppercase text-outline">Taux Brut Moyen</p>
            <p class="text-page-title font-bold" data-kpi="brut">{{ \App\Support\SuiviIncubation::pourcentage($tauxBrut) }}</p>
            <p class="text-caption text-outline">Rapporté aux œufs chargés</p>
        </div>
    </div>

    @if (count($alertes) > 0)
        <div class="mb-md rounded-lg p-md {{ $enRetard > 0 ? 'bg-error-container' : 'bg-surface-zebra' }}" data-bloc="alertes">
            <p class="mb-sm text-xs font-bold {{ $enRetard > 0 ? 'text-error-deep' : 'text-brand-navy' }}">
                @if ($enRetard > 0)
                    {{ count($alertes) }} échéance(s) du couvoir, dont {{ $enRetard }} en retard
                @else
                    {{ count($alertes) }} échéance(s) du couvoir aujourd'hui
                @endif
            </p>
            <ul class="flex flex-col gap-xs text-xs">
                @foreach (array_slice($alertes, 0, 6) as $a)
                    <?php [$libelle, $detail] = \App\Support\SuiviIncubation::libelleEcheance($a['type']); ?>
                    <li class="flex flex-wrap justify-between gap-sm" data-alerte="{{ $a['lot']->code_incubation }}">
                        <span>{{ $a['lot']->code_incubation }} · {{ $libelle }} — {{ $detail }}{{ $a['lot']->machine_id && isset($codesMachines[$a['lot']->machine_id]) ? ' · '.$codesMachines[$a['lot']->machine_id] : '' }}</span>
                        <span class="font-bold {{ $a['ecart'] > 0 ? 'text-error-deep' : 'text-outline' }}">{{ $a['ecart'] === 0 ? "aujourd'hui" : 'depuis '.$a['ecart'].' j' }}</span>
                    </li>
                @endforeach
            </ul>
            @if (count($alertes) > 6)
                <p class="mt-xs text-caption text-outline">et {{ count($alertes) - 6 }} autre(s) — voir le tableau ci-dessous.</p>
            @endif
        </div>
    @endif

    @if (count($aVenir) > 0)
        <div class="mb-md rounded-lg border border-outline-variant bg-surface-card p-md" data-bloc="a-venir">
            <p class="mb-sm text-xs font-bold text-brand-navy">{{ count($aVenir) }} échéance(s) dans les 3 prochains jours</p>
            <ul class="flex flex-col gap-xs text-xs">
                @foreach ($aVenir as $e)
                    <?php [$libelle, $detail] = \App\Support\SuiviIncubation::libelleEcheance($e['type']); ?>
                    <li class="flex flex-wrap justify-between gap-sm">
                        <span>{{ $e['lot']->code_incubation }} · {{ $libelle }} — {{ $detail }}</span>
                        <span class="font-bold text-outline">{{ $e['date']->format('d/m/Y') }}</span>
                    </li>
                @endforeach
            </ul>
        </div>
    @endif

    <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
        <h2 class="text-section-title font-bold">Parc d'Incubateurs</h2>
        @if ($peutGerer)
            <button type="button" wire:click="nouvelIncubateur"
                    class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">
                Ajouter un Incubateur
            </button>
        @endif
    </div>
    @if ($machines->isEmpty())
        <p class="mb-lg rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun incubateur déclaré. Les lots peuvent être suivis sans machine, mais aucune occupation ne sera calculée.</p>
    @else
        <div class="mb-lg grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3" data-bloc="parc">
            @foreach ($machines as $m)
                @php
                    $occupation = \App\Support\SuiviIncubation::occupation($tous, $m->id);
                    $nbLots = $tous->filter(fn ($l) => $l->machine_id === $m->id && \App\Support\SuiviIncubation::enCours($l))->count();
                    $remplissage = $m->capacite_oeufs ? $occupation / $m->capacite_oeufs : null;
                    $surcharge = $remplissage !== null && $remplissage > 1;
                @endphp
                <article class="rounded-lg border {{ $surcharge ? 'border-error-deep' : 'border-outline-variant' }} bg-surface-card p-md" data-machine="{{ $m->code }}">
                    <div class="flex items-center justify-between">
                        <p class="text-xs font-bold text-brand-navy">{{ $m->code }}</p>
                        <p class="text-caption text-outline">{{ $nbLots }} lot(s)</p>
                    </div>
                    <p class="text-caption text-outline">{{ $m->libelle }}</p>
                    <p class="mt-sm font-bold {{ $surcharge ? 'text-error-deep' : '' }}" data-occupation>
                        {{ $m->capacite_oeufs ? $occupation.' / '.$m->capacite_oeufs.' œufs' : $occupation.' œufs en incubation' }}
                    </p>
                    @if ($remplissage !== null)
                        <p class="text-caption {{ $surcharge ? 'text-error-deep' : 'text-outline' }}">
                            {{ $surcharge ? 'Capacité annoncée dépassée' : \App\Support\SuiviIncubation::pourcentage($remplissage * 100).' de la capacité' }}</p>
                    @else
                        <p class="text-caption text-outline">Capacité non renseignée — aucun taux de remplissage</p>
                    @endif
                </article>
            @endforeach
        </div>
    @endif

    <div class="mb-sm flex flex-wrap items-center justify-between gap-sm">
        <h2 class="text-section-title font-bold">Lots d'Incubation</h2>
        <div class="flex flex-wrap gap-sm">
            <select wire:model.live="filtreStatut" aria-label="Filtrer par statut" class="rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs">
                <option value="">Tous les statuts</option>
                <option value="en_cours">En cours</option>
                <option value="eclos">Éclos</option>
            </select>
            <select wire:model.live="filtreEspece" aria-label="Filtrer par espèce" class="rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs">
                <option value="">Toutes espèces</option>
                @foreach ($especes as $cle => $e)
                    <option value="{{ $cle }}">{{ $e['libelle'] }}</option>
                @endforeach
            </select>
            <select wire:model.live="filtreMachine" aria-label="Filtrer par incubateur" class="rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs">
                <option value="">Tous incubateurs</option>
                @foreach ($machines as $m)
                    <option value="{{ $m->id }}">{{ $m->code }}</option>
                @endforeach
            </select>
        </div>
    </div>

    @if ($lots->isEmpty())
        <p class="mb-lg rounded-lg bg-surface-card p-md text-center text-xs text-outline">Aucun cycle d'incubation enregistré. Utilisez « Déclarer un Nouveau Cycle » pour en créer un.</p>
    @else
        @php
            $mirage = function ($lot, int $jour) use ($jourRef, $peutGerer) {
                $premier = $jour === 7;
                $valeur = $premier ? $lot->oeufs_blancs_j7 : $lot->oeufs_gates_j14;
                $echeance = $premier ? \App\Support\SuiviIncubation::dateMirage1($lot) : \App\Support\SuiviIncubation::dateMirage2($lot);
                $saisi = $valeur !== null;
                $du = \App\Support\SuiviIncubation::enCours($lot) && ! $saisi && ! $jourRef->lt($echeance);

                return [
                    'libelle' => $premier ? 'MIRAGE 1' : 'MIRAGE 2',
                    'texte' => $saisi ? $valeur.' retiré'.($valeur > 1 ? 's' : '') : ($du ? 'À saisir' : $echeance->format('d/m/Y')),
                    'classe' => $saisi ? 'border-success-deep bg-success-container text-success-deep' : ($du ? 'border-error-deep bg-error-container text-error-deep' : 'border-outline-variant bg-surface-card text-outline'),
                    'titre' => $premier
                        ? 'Mirage 1 (J+7) — œufs clairs, jamais fécondés. Prévu le '.$echeance->format('d/m/Y').'.'
                        : 'Mirage 2 (J+14) — œufs gâtés, embryon arrêté. Prévu le '.$echeance->format('d/m/Y').'.',
                ];
            };
        @endphp
        <div class="mb-lg hidden overflow-x-auto rounded-lg border border-outline-variant bg-surface-card sm:block">
            <table class="w-full text-left text-xs" data-table="lots">
                <thead class="bg-surface-zebra text-caption uppercase text-outline">
                    <tr>
                        <th class="px-md py-sm">Lot</th>
                        <th class="px-md py-sm">Espèce</th>
                        <th class="px-md py-sm">Machine</th>
                        <th class="px-md py-sm text-right">Chargés</th>
                        <th class="px-md py-sm text-center">Âge</th>
                        <th class="px-md py-sm text-center">Mirages</th>
                        <th class="px-md py-sm">Éclosion Prévue</th>
                        <th class="px-md py-sm text-right">TER</th>
                        <th class="px-md py-sm text-center">Statut</th>
                        @if ($peutGerer)<th class="px-md py-sm text-right">Actions</th>@endif
                    </tr>
                </thead>
                <tbody>
                    @foreach ($lots as $l)
                        @php
                            $enCours = \App\Support\SuiviIncubation::enCours($l);
                            $restants = (int) $jourRef->diffInDays(\App\Support\SuiviIncubation::dateEclosionPrevue($l), false);
                            $imminente = $enCours && $restants >= 0 && $restants <= 3;
                            $ter = \App\Support\SuiviIncubation::ter($l);
                        @endphp
                        <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-lot="{{ $l->code_incubation }}">
                            <td class="px-md py-sm">
                                <p class="font-bold text-brand-navy">{{ $l->code_incubation }}</p>
                                @if ($l->lot_parent_id)
                                    <p class="text-caption text-outline">↳ remplace {{ $codes[$l->lot_parent_id] ?? '—' }}</p>
                                @endif
                            </td>
                            <td class="px-md py-sm">{{ \App\Support\SuiviIncubation::libelleEspece($l->espece) }}</td>
                            <td class="px-md py-sm {{ $l->machine_id ? '' : 'text-outline' }}">{{ $codesMachines[$l->machine_id] ?? '—' }}</td>
                            <td class="px-md py-sm text-right">{{ $l->oeufs_couves }}</td>
                            <td class="px-md py-sm text-center">{{ $enCours ? 'J+'.\App\Support\SuiviIncubation::age($l, $jourRef) : \App\Support\SuiviIncubation::dateChargement($l)->format('d/m/Y') }}</td>
                            <td class="px-md py-sm">
                                <div class="flex justify-center gap-xs">
                                    @foreach ([7, 14] as $jour)
                                        <?php $m = $mirage($l, $jour); ?>
                                        @if ($enCours && $peutGerer)
                                            <button type="button" wire:click="ouvrirMirage('{{ $l->id }}', {{ $jour }})" title="{{ $m['titre'] }}"
                                                    class="rounded-lg border px-xs py-xs text-center {{ $m['classe'] }}" data-mirage="{{ $jour }}">
                                                <span class="block text-caption font-bold">{{ $m['libelle'] }}</span><span class="block">{{ $m['texte'] }}</span>
                                            </button>
                                        @else
                                            <span title="{{ $m['titre'] }}" class="rounded-lg border px-xs py-xs text-center {{ $m['classe'] }}" data-mirage="{{ $jour }}">
                                                <span class="block text-caption font-bold">{{ $m['libelle'] }}</span><span class="block">{{ $m['texte'] }}</span>
                                            </span>
                                        @endif
                                    @endforeach
                                </div>
                            </td>
                            <td class="px-md py-sm {{ $imminente ? 'font-bold text-error-deep' : '' }}">{{ \App\Support\SuiviIncubation::dateEclosionPrevue($l)->format('d/m/Y') }}</td>
                            <td class="px-md py-sm text-right font-bold">{{ \App\Support\SuiviIncubation::pourcentage($ter) }}</td>
                            <td class="px-md py-sm text-center">
                                <span class="rounded-full px-sm py-xs font-semibold {{ $enCours ? 'bg-surface-zebra text-brand-navy' : 'bg-success-container text-success-deep' }}">{{ $l->statut }}</span>
                            </td>
                            @if ($peutGerer)
                                <td class="px-md py-sm text-right">
                                    @if ($enCours)
                                        <button type="button" wire:click="ouvrirEclosion('{{ $l->id }}')" class="rounded-lg bg-brand-navy px-sm py-xs font-semibold text-white">Éclosion</button>
                                        <button type="button" wire:click="modifierLot('{{ $l->id }}')" class="rounded-lg border border-outline-variant px-sm py-xs font-semibold hover:bg-surface-zebra">Modifier</button>
                                        <button type="button" wire:click="demanderSuppression('{{ $l->id }}')" class="rounded-lg border border-error-deep px-sm py-xs font-semibold text-error-deep hover:bg-error-container">Supprimer</button>
                                    @else
                                        <span class="text-outline" title="Un cycle éclos ne se modifie plus : ses poussins sont entrés dans les effectifs et son taux d'éclosion dans les statistiques.">{{ $l->poussins_nes ?? 0 }} poussins · verrouillé</span>
                                    @endif
                                </td>
                            @endif
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </div>

        <div class="mb-lg flex flex-col gap-sm sm:hidden" data-vue="cartes">
            @foreach ($lots as $l)
                <?php $enCours = \App\Support\SuiviIncubation::enCours($l); ?>
                <article class="rounded-lg border border-outline-variant bg-surface-card p-md" data-carte-lot="{{ $l->code_incubation }}">
                    <div class="flex items-center justify-between">
                        <p class="font-bold text-brand-navy">{{ $l->code_incubation }}</p>
                        <span class="rounded-full px-sm py-xs text-caption font-semibold {{ $enCours ? 'bg-surface-zebra text-brand-navy' : 'bg-success-container text-success-deep' }}">{{ $l->statut }}</span>
                    </div>
                    @if ($l->lot_parent_id)
                        <p class="text-caption text-outline">↳ remplace {{ $codes[$l->lot_parent_id] ?? '—' }}</p>
                    @endif
                    <p class="text-caption text-outline">{{ \App\Support\SuiviIncubation::libelleEspece($l->espece) }} · {{ $codesMachines[$l->machine_id] ?? 'sans machine' }} · {{ $l->oeufs_couves }} œufs · {{ $enCours ? 'J+'.\App\Support\SuiviIncubation::age($l, $jourRef) : \App\Support\SuiviIncubation::dateChargement($l)->format('d/m/Y') }}</p>
                    <div class="mt-sm flex gap-xs">
                        @foreach ([7, 14] as $jour)
                            <?php $m = $mirage($l, $jour); ?>
                            <span title="{{ $m['titre'] }}" class="flex-1 rounded-lg border px-xs py-xs text-center {{ $m['classe'] }}">
                                <span class="block text-caption font-bold">{{ $m['libelle'] }}</span><span class="block text-xs">{{ $m['texte'] }}</span>
                            </span>
                        @endforeach
                    </div>
                    <p class="mt-sm text-xs">Éclosion prévue le {{ \App\Support\SuiviIncubation::dateEclosionPrevue($l)->format('d/m/Y') }} · TER {{ \App\Support\SuiviIncubation::pourcentage(\App\Support\SuiviIncubation::ter($l)) }}</p>
                    @if ($peutGerer && $enCours)
                        <div class="mt-sm flex flex-wrap gap-sm">
                            <button type="button" wire:click="ouvrirMirage('{{ $l->id }}', 7)" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Mirage 1</button>
                            <button type="button" wire:click="ouvrirMirage('{{ $l->id }}', 14)" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Mirage 2</button>
                            <button type="button" wire:click="ouvrirEclosion('{{ $l->id }}')" class="flex-1 rounded-lg bg-brand-navy px-sm py-sm text-xs font-semibold text-white">Éclosion</button>
                            <button type="button" wire:click="modifierLot('{{ $l->id }}')" class="flex-1 rounded-lg border border-outline-variant px-sm py-sm text-xs font-semibold">Modifier</button>
                            <button type="button" wire:click="demanderSuppression('{{ $l->id }}')" class="flex-1 rounded-lg border border-error-deep px-sm py-sm text-xs font-semibold text-error-deep">Supprimer</button>
                        </div>
                    @endif
                </article>
            @endforeach
        </div>
    @endif

    {{-- Declarer / modifier un cycle --}}
    @if ($formulaireLot)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-lot">
            <form wire:submit="enregistrerLot" class="w-full max-w-sm rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-lot" class="mb-md text-modal-title font-bold">{{ $lotId ? 'Modifier le Cycle' : 'Déclarer un Nouveau Cycle' }}</h2>
                <label class="mb-sm block text-xs uppercase">Espèce
                    <select wire:model.live="espece" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm normal-case">
                        <option value="">-- Choisir --</option>
                        @foreach ($especes as $cle => $e)
                            <option value="{{ $cle }}">{{ $e['libelle'] }} ({{ $e['duree'] }} j)</option>
                        @endforeach
                    </select></label>
                <label class="mb-sm block text-xs uppercase">Date de Chargement
                    <input type="date" wire:model.live="dateChargement" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs uppercase">Incubateur
                    <select wire:model="machineId" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm normal-case">
                        <option value="">{{ $machines->isEmpty() ? '-- aucun incubateur déclaré --' : 'Non précisé' }}</option>
                        @foreach ($machines as $m)
                            <option value="{{ $m->id }}">{{ $m->code }} — {{ $m->libelle }}{{ $m->capacite_oeufs ? ' ('.$m->capacite_oeufs.' œufs)' : '' }}</option>
                        @endforeach
                    </select></label>
                <label class="block text-xs uppercase">Nombre d'Œufs Chargés
                    <input type="text" inputmode="numeric" wire:model="oeufs" placeholder="Ex. 200" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @if ($espece !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $dateChargement) === 1)
                    <?php $charge = \App\Support\SuiviIncubation::jour($dateChargement); ?>
                    <p class="mt-sm text-caption text-outline" data-calendrier>
                        Mirage 1 le {{ $charge->addDays(7)->format('d/m/Y') }} · Mirage 2 le {{ $charge->addDays(14)->format('d/m/Y') }} ·
                        Éclosion prévue le {{ $charge->addDays(\App\Support\SuiviIncubation::duree($espece))->format('d/m/Y') }}</p>
                @endif
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">{{ $lotId ? 'Enregistrer' : 'Créer le Cycle' }}</button>
                </div>
            </form>
        </div>
    @endif

    {{-- Mirage --}}
    @if ($lotMirage)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-mirage">
            <form wire:submit="enregistrerMirage" class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-mirage" class="mb-xs text-modal-title font-bold">{{ $mirageJour === 7 ? 'Mirage 1 (J+7)' : 'Mirage 2 (J+14)' }} — {{ $lotMirage->code_incubation }}</h2>
                <p class="mb-md text-xs text-outline">{{ \App\Support\SuiviIncubation::libelleEspece($lotMirage->espece) }} · {{ $lotMirage->oeufs_couves }} œufs chargés le {{ \App\Support\SuiviIncubation::dateChargement($lotMirage)->format('d/m/Y') }} · échéance le {{ ($mirageJour === 7 ? \App\Support\SuiviIncubation::dateMirage1($lotMirage) : \App\Support\SuiviIncubation::dateMirage2($lotMirage))->format('d/m/Y') }}</p>
                <label class="block text-xs uppercase">{{ $mirageJour === 7 ? 'Œufs clairs retirés (non fécondés)' : 'Œufs gâtés retirés (embryon mort)' }}
                    <input type="text" inputmode="numeric" wire:model="mirageRetires" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">Enregistrer le Mirage</button>
                </div>
            </form>
        </div>
    @endif

    {{-- Eclosion --}}
    @if ($lotEclosion)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-eclosion">
            <form wire:submit="enregistrerEclosion" class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-eclosion" class="mb-xs text-modal-title font-bold">Enregistrer l'Éclosion — {{ $lotEclosion->code_incubation }}</h2>
                <p class="mb-sm text-xs text-outline">{{ \App\Support\SuiviIncubation::libelleEspece($lotEclosion->espece) }} · {{ $lotEclosion->oeufs_couves }} œufs chargés le {{ \App\Support\SuiviIncubation::dateChargement($lotEclosion)->format('d/m/Y') }}{{ $lotEclosion->machine_id && isset($codesMachines[$lotEclosion->machine_id]) ? ' · '.$codesMachines[$lotEclosion->machine_id] : '' }}</p>
                <p class="mb-md text-xs text-outline">Œufs retirés aux mirages : {{ ($lotEclosion->oeufs_blancs_j7 ?? 0) + ($lotEclosion->oeufs_gates_j14 ?? 0) }} · encore en incubation : {{ \App\Support\SuiviIncubation::retenus($lotEclosion) }}</p>
                <label class="mb-sm block text-xs uppercase">Nombre de Poussins Éclos
                    <input type="text" inputmode="numeric" wire:model="poussins" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs uppercase">Nombre d'Œufs Non Éclos / Cassés
                    <input type="text" inputmode="numeric" wire:model="perdus" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <div class="mb-sm rounded-lg bg-surface-zebra p-sm">
                    <label class="flex items-center gap-sm text-xs font-semibold">
                        <input type="checkbox" wire:model.live="remplacer"> Recharger la machine immédiatement</label>
                    <p class="mt-xs text-caption text-outline">Un sous-lot est créé, rattaché à celui-ci pour la traçabilité, mais avec son propre calendrier de mirages et d'éclosion.</p>
                    @if ($remplacer)
                        <label class="mt-sm block text-xs uppercase">Œufs insérés
                            <input type="text" inputmode="numeric" wire:model="remplacementOeufs" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                        <label class="mt-sm block text-xs uppercase">Espèce
                            <select wire:model="remplacementEspece" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm normal-case">
                                @foreach ($especes as $cle => $e)
                                    <option value="{{ $cle }}">{{ $e['libelle'] }} ({{ $e['duree'] }} j)</option>
                                @endforeach
                            </select></label>
                        <label class="mt-sm block text-xs uppercase">Date d'insertion
                            <input type="date" wire:model="remplacementDate" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                    @endif
                </div>
                @if ($erreur)
                    <p role="alert" class="mt-sm text-xs text-error-deep">{{ $erreur }}</p>
                @endif
                <div class="mt-md flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white">{{ $remplacer ? 'Enregistrer et Remplacer' : "Enregistrer l'Éclosion" }}</button>
                </div>
            </form>
        </div>
    @endif

    {{-- Suppression --}}
    @if ($lotASupprimer)
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-suppression">
            <div class="w-full max-w-md rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-suppression" class="mb-sm text-modal-title font-bold">Supprimer le cycle {{ $lotASupprimer->code_incubation }} ?</h2>
                <p class="mb-sm rounded-lg bg-error-container p-sm text-xs font-bold text-error-deep">Le lot disparaît du couvoir de tous les postes.</p>
                <p class="mb-sm text-xs">Les {{ $lotASupprimer->oeufs_couves }} œufs de ce lot, chargés le {{ \App\Support\SuiviIncubation::dateChargement($lotASupprimer)->format('d/m/Y') }}, disparaîtront du couvoir et des rapports d'élevage. L'éclosion prévue le {{ \App\Support\SuiviIncubation::dateEclosionPrevue($lotASupprimer)->format('d/m/Y') }} ne sera plus annoncée.</p>
                <p class="mb-md text-xs text-outline">Ne supprimez un lot que s'il a été déclaré par erreur. Un lot réellement mis en couveuse puis perdu doit être enregistré comme éclosion avec 0 poussin — la perte reste ainsi visible dans le taux d'éclosion moyen, ce qui est le but du suivi.</p>
                <div class="flex justify-end gap-sm">
                    <button type="button" wire:click="annuler" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold">Annuler</button>
                    <button type="button" wire:click="confirmerSuppression" class="rounded-lg bg-error-deep px-md py-sm text-xs font-semibold text-white">Supprimer</button>
                </div>
            </div>
        </div>
    @endif

    {{-- Incubateur --}}
    @if ($formulaireMachine)
        <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 p-md" role="dialog" aria-modal="true" aria-labelledby="titre-machine">
            <form wire:submit="enregistrerIncubateur" class="w-full max-w-sm rounded-lg bg-surface-card p-lg shadow-xl">
                <h2 id="titre-machine" class="mb-md text-modal-title font-bold">Ajouter un Incubateur</h2>
                <label class="mb-sm block text-xs uppercase">Code *
                    <input type="text" wire:model="machineCode" placeholder="Ex. INC-01" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="mb-sm block text-xs uppercase">Libellé *
                    <input type="text" wire:model="machineLibelle" placeholder="Ex. Couveuse 528 œufs — atelier" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
                <label class="block text-xs uppercase">Capacité (œufs)
                    <input type="text" inputmode="numeric" wire:model="machineCapacite" placeholder="Facultatif" class="mt-xs w-full rounded-lg border border-outline-variant px-sm py-sm"></label>
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
