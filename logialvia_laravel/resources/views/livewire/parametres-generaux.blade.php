<div>
    <div class="mb-md flex flex-wrap items-center justify-between gap-sm">
        <h1 class="text-page-title font-bold">Paramètres Généraux</h1>
        @can('manage-users')
            <a href="{{ route('postes') }}" class="rounded-lg border border-outline-variant px-md py-sm text-xs font-semibold hover:bg-surface-zebra">
                Postes &amp; Appairage
            </a>
        @endcan
    </div>

    @if ($message)
        <p role="status" class="mb-md rounded-lg bg-success-container p-sm text-xs text-success-deep">{{ $message }}</p>
    @endif
    @if ($erreur)
        <p role="alert" class="mb-md rounded-lg bg-error-container p-sm text-xs text-error-deep">{{ $erreur }}</p>
    @endif

    <div class="mb-md flex overflow-x-auto border-b border-outline-variant" role="tablist" aria-label="Sections des paramètres">
        @foreach ($onglets as $i => $libelle)
            <button type="button" role="tab" wire:click="choisirOnglet({{ $i }})" aria-selected="{{ $i === $onglet ? 'true' : 'false' }}"
                    class="whitespace-nowrap border-b-2 px-md py-sm text-xs font-bold {{ $i === $onglet ? 'border-brand-navy text-brand-navy' : 'border-transparent text-outline' }}">
                {{ $libelle }}
            </button>
        @endforeach
    </div>

    {{-- ============================================================ 0 · Modules actifs --}}
    @if ($onglet === 0)
        <section class="rounded-lg border border-outline-variant bg-surface-card p-md" data-onglet="modules">
            <h2 class="mb-sm text-section-title font-bold">Modules Actifs</h2>
            <p class="mb-md text-xs text-outline">
                Goliaths et Pintades sont l'activité principale confirmée d'ALLMANY et restent toujours actifs. Les filières ci-dessous
                sont désactivées par défaut — activez-les uniquement si l'activité démarre réellement.
            </p>

            @foreach (['Goliaths', 'Pintades'] as $fixe)
                <div class="flex items-center justify-between gap-md border-b border-outline-variant py-sm" data-module-fixe="{{ $fixe }}">
                    <div>
                        <p class="text-xs font-bold">{{ $fixe }}</p>
                        <p class="text-caption text-outline">Activité principale confirmée — toujours actif</p>
                    </div>
                    <span class="rounded-full bg-success-container px-sm py-xs text-caption font-semibold text-success-deep">Toujours actif</span>
                </div>
            @endforeach

            @foreach ($modulesEtat as $m)
                <div class="flex items-center justify-between gap-md border-b border-outline-variant py-sm" data-module="{{ $m['id'] }}">
                    <div>
                        <p class="text-xs font-bold">{{ $m['libelle'] }}</p>
                        <p class="text-caption text-outline">{{ $m['note'] }}</p>
                    </div>
                    @if ($peutModules)
                        <button type="button" role="switch" aria-checked="{{ $m['actif'] ? 'true' : 'false' }}"
                                aria-label="{{ $m['libelle'] }}"
                                wire:click="basculerModule('{{ $m['id'] }}', {{ $m['actif'] ? 'false' : 'true' }})"
                                class="rounded-full px-md py-xs text-caption font-semibold {{ $m['actif'] ? 'bg-brand-navy text-white' : 'border border-outline-variant text-outline' }}">
                            {{ $m['actif'] ? 'Actif' : 'Inactif' }}
                        </button>
                    @else
                        <span class="rounded-full px-sm py-xs text-caption font-semibold {{ $m['actif'] ? 'bg-success-container text-success-deep' : 'bg-surface-zebra text-outline' }}">
                            {{ $m['actif'] ? 'Actif' : 'Inactif' }}
                        </span>
                    @endif
                </div>
            @endforeach

            <p class="mt-sm text-caption italic text-outline">
                Activer un module affiche immédiatement sa fiche et son raccourci dans le menu latéral et le panneau d'accès rapide.
            </p>
            @unless ($peutModules)
                <p class="mt-sm text-caption text-outline">Lecture seule : seul l'administrateur peut activer ou désactiver un module.</p>
            @endunless

            <div class="mt-md rounded-lg p-sm {{ $modeDonneesTest ? 'bg-error-container' : 'bg-surface-zebra' }}" data-mode-donnees-test>
                <p class="text-xs font-bold">Mode « Données de Test »</p>
                <p class="text-caption {{ $modeDonneesTest ? 'text-error-deep' : 'text-outline' }}">
                    {{ $modeDonneesTest ? 'ACTIF — l\'onglet Données de Test autorise la remise à zéro' : 'Désactivé — l\'onglet Données de Test est verrouillé' }}
                </p>
                <p class="mt-xs text-caption text-outline">Ce mode se règle uniquement sur le poste : il n'est pas modifiable depuis le web.</p>
            </div>
        </section>
    @endif

    {{-- ============================================================ 1 · Entreprise --}}
    @if ($onglet === 1)
        <form wire:submit="enregistrer" class="flex flex-col gap-md" novalidate data-onglet="entreprise">
            @php($champ = 'mt-xs w-full rounded-lg border border-outline-variant bg-surface-card px-sm py-sm text-xs disabled:bg-surface-zebra')
            <fieldset @disabled(! $peutEcrire) class="flex flex-col gap-md">
                <section class="rounded-lg border border-outline-variant bg-surface-card p-md">
                    <h2 class="mb-sm text-section-title font-bold">Informations Générales</h2>
                    <div class="grid grid-cols-1 gap-sm sm:grid-cols-2">
                        <label class="text-caption font-semibold uppercase text-outline sm:col-span-2">Raison Sociale *
                            <input type="text" wire:model="raisonSociale" maxlength="255" class="{{ $champ }} normal-case"></label>
                        <label class="text-caption font-semibold uppercase text-outline">Nom du Promoteur
                            <input type="text" wire:model="nomPromoteur" maxlength="255" class="{{ $champ }} normal-case"></label>
                        <label class="text-caption font-semibold uppercase text-outline">Téléphone Principal
                            <input type="text" wire:model="telephone" maxlength="255" class="{{ $champ }} normal-case"></label>
                        <label class="text-caption font-semibold uppercase text-outline sm:col-span-2">Adresse du Siège d'Exploitation
                            <input type="text" wire:model="adresseSiege" maxlength="255" class="{{ $champ }} normal-case"></label>
                        <label class="text-caption font-semibold uppercase text-outline sm:col-span-2">Email de Contact
                            <input type="text" inputmode="email" wire:model="email" maxlength="255" class="{{ $champ }} normal-case"></label>
                    </div>
                </section>

                <section class="rounded-lg border border-outline-variant bg-surface-card p-md">
                    <h2 class="mb-sm text-section-title font-bold">Conditions de Vente</h2>
                    <label class="text-caption font-semibold uppercase text-outline">Délai de paiement par défaut (jours)
                        <input type="text" inputmode="numeric" wire:model="delaiPaiement" class="{{ $champ }} normal-case sm:max-w-xs"></label>
                    <p class="mt-xs text-caption text-outline">
                        Pré-remplit « Payable le » au point de vente. Laissé vide, aucune échéance n'est proposée et aucune créance
                        n'est signalée en retard.
                    </p>
                    @if (trim($delaiPaiement) === '')
                        <p class="mt-sm rounded-lg bg-brand-gold/10 p-sm text-xs text-brand-navy">
                            Aucun délai n'est fixé. Les ventes à crédit sont donc enregistrées « Sans échéance » : elles apparaissent dans
                            les créances, mais ne sont jamais déclarées en retard et ne déclenchent aucune lettre de relance pour retard.
                            Renseignez le délai réellement pratiqué pour activer ce suivi.
                        </p>
                    @endif
                </section>

                <section class="rounded-lg border border-outline-variant bg-surface-card p-md">
                    <h2 class="mb-sm text-section-title font-bold">Informations Légales &amp; Fiscales</h2>
                    <div class="grid grid-cols-1 gap-sm sm:grid-cols-2">
                        <label class="text-caption font-semibold uppercase text-outline">Identifiant Fiscal Unique (IFU) *
                            <input type="text" inputmode="numeric" wire:model.live.debounce.300ms="ifu" maxlength="255" class="{{ $champ }} normal-case">
                            <span class="text-caption font-normal normal-case text-outline">Chiffres uniquement</span></label>
                        <label class="text-caption font-semibold uppercase text-outline">Registre du Commerce (RCCM)
                            <input type="text" wire:model.live.debounce.300ms="rccm" maxlength="255" class="{{ $champ }} normal-case"></label>
                    </div>

                    <div class="mt-md flex items-center justify-between gap-md rounded-lg p-sm {{ $mecefActivable ? 'bg-success-container' : 'bg-surface-zebra' }}" data-mecef>
                        <div>
                            <p class="text-xs font-bold">Module de conformité fiscale MeCeF</p>
                            <p class="text-caption text-outline">
                                {{ $mecefActivable ? 'IFU et RCCM renseignés — activable.' : 'BR-ADM-004 : renseignez l\'IFU et le RCCM pour pouvoir l\'activer.' }}
                            </p>
                        </div>
                        <button type="button" role="switch" aria-checked="{{ $mecefActif ? 'true' : 'false' }}" aria-label="Module MeCeF"
                                wire:click="basculerMecef" @disabled(! $peutEcrire)
                                class="rounded-full px-md py-xs text-caption font-semibold {{ $mecefActif ? 'bg-brand-navy text-white' : 'border border-outline-variant text-outline' }}">
                            {{ $mecefActif ? 'Actif' : 'Inactif' }}
                        </button>
                    </div>

                    @if ($mecefActif)
                        <div class="mt-sm grid grid-cols-1 gap-sm sm:grid-cols-2" data-mecef-champs>
                            <label class="text-caption font-semibold uppercase text-outline">URL du service e-MECeF
                                <input type="text" wire:model="mecefUrl" maxlength="255" class="{{ $champ }} normal-case">
                                <span class="text-caption font-normal normal-case text-outline">Fournie par la DGI</span></label>
                            <label class="text-caption font-semibold uppercase text-outline">NIM (Numéro d'Identification de la Machine)
                                <input type="text" wire:model="mecefNim" maxlength="255" class="{{ $champ }} normal-case">
                                <span class="text-caption font-normal normal-case text-outline">S'imprime sur chaque facture normalisée</span></label>
                        </div>
                        <p class="mt-sm rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-jeton-poste>
                            Le jeton e-MECeF est un secret : il se saisit et se garde uniquement sur le poste (magasin sécurisé du système).
                            Il n'est jamais affiché ni saisi ici.
                        </p>
                    @endif
                </section>

                <section class="rounded-lg border border-outline-variant bg-surface-card p-md">
                    <h2 class="mb-sm text-section-title font-bold">Configuration Email (SMTP)</h2>
                    <div class="grid grid-cols-1 gap-sm sm:grid-cols-3">
                        <label class="text-caption font-semibold uppercase text-outline sm:col-span-2">Serveur SMTP
                            <input type="text" wire:model="smtpServeur" maxlength="255" class="{{ $champ }} normal-case"></label>
                        <label class="text-caption font-semibold uppercase text-outline">Port
                            <input type="text" inputmode="numeric" wire:model="smtpPort" class="{{ $champ }} normal-case"></label>
                        <label class="text-caption font-semibold uppercase text-outline">Sécurité
                            <select wire:model="smtpSecurite" class="{{ $champ }} normal-case">
                                <option value=""></option>
                                @foreach ($securites as $s)<option value="{{ $s }}">{{ $s }}</option>@endforeach
                            </select></label>
                    </div>
                    <p class="mt-sm text-caption italic text-outline">
                        Le mot de passe SMTP n'est volontairement pas stocké ici : un secret n'a pas sa place en clair dans la base. Il sera
                        demandé via un stockage sécurisé le jour où l'envoi d'e-mails sera réellement implémenté.
                    </p>
                </section>

                <section class="rounded-lg border border-outline-variant bg-surface-card p-md">
                    <h2 class="mb-sm text-section-title font-bold">Logo / Favicon</h2>
                    <p class="text-xs text-outline">
                        Le dépôt de logo sera disponible avec le module d'impression (Doc E9), seul consommateur de ces images.
                    </p>
                </section>
            </fieldset>

            @if ($peutEcrire)
                <button type="submit" class="rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">
                    Enregistrer les Modifications
                </button>
                <p class="text-caption text-outline">
                    Un champ laissé vide n'efface jamais la valeur déjà connue du serveur : pour vider un champ, passez par le poste.
                </p>
            @else
                <p class="text-caption text-outline">Lecture seule : seul l'administrateur peut modifier ces informations.</p>
            @endif
        </form>
    @endif

    {{-- ============================================================ 2 · Utilisateurs --}}
    @if ($onglet === 2)
        <section class="rounded-lg border border-outline-variant bg-surface-card p-md" data-onglet="utilisateurs">
            <h2 class="mb-sm text-section-title font-bold">Gestion des Utilisateurs</h2>
            @if ($peutVoirComptes)
                <div class="hidden overflow-x-auto sm:block">
                    <table class="w-full text-left text-xs">
                        <thead class="bg-surface-zebra text-caption uppercase text-outline">
                            <tr><th class="px-md py-sm">Nom Complet</th><th class="px-md py-sm">Identifiant</th><th class="px-md py-sm">Rôle</th></tr>
                        </thead>
                        <tbody>
                            @forelse ($comptes as $c)
                                <tr class="{{ $loop->odd ? '' : 'bg-surface-zebra' }}" data-compte="{{ $c['identifiant'] }}">
                                    <td class="px-md py-sm">{{ $c['nom'] }}</td>
                                    <td class="px-md py-sm">{{ $c['identifiant'] }}</td>
                                    <td class="px-md py-sm">{{ $c['role'] }}</td>
                                </tr>
                            @empty
                                <tr><td colspan="3" class="px-md py-lg text-center text-outline">Aucun compte.</td></tr>
                            @endforelse
                        </tbody>
                    </table>
                </div>
                <div class="flex flex-col gap-sm sm:hidden">
                    @foreach ($comptes as $c)
                        <article class="rounded-lg border border-outline-variant p-sm text-xs" data-carte-compte="{{ $c['identifiant'] }}">
                            <p class="font-bold">{{ $c['nom'] }}</p>
                            <p class="text-outline">{{ $c['identifiant'] }} · {{ $c['role'] }}</p>
                        </article>
                    @endforeach
                </div>
            @endif
            <p class="mt-sm rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="utilisateurs">
                Les comptes d'un poste sont propres à ce poste : leur création, leur suppression et leurs mots de passe se gèrent sur le
                poste (Paramètres Généraux &gt; Gestion Utilisateurs). Le web n'affiche ici, en lecture seule, que les comptes du serveur.
            </p>
        </section>
    @endif

    {{-- ============================================================ 3 · Modes de paiement --}}
    @if ($onglet === 3)
        <section class="rounded-lg border border-outline-variant bg-surface-card p-md" data-onglet="paiement">
            <h2 class="mb-sm text-section-title font-bold">Modes de Paiement</h2>
            <p class="mb-xs text-caption font-semibold uppercase text-outline">Modes de règlement</p>
            @foreach (['Espèces', 'Mobile Money'] as $mode)
                <div class="flex items-center justify-between border-b border-outline-variant py-sm">
                    <div><p class="text-xs font-bold">{{ $mode }}</p><p class="text-caption text-outline">Toujours actif</p></div>
                    <span class="rounded-full bg-success-container px-sm py-xs text-caption font-semibold text-success-deep">Toujours actif</span>
                </div>
            @endforeach
            <p class="mt-sm text-xs text-outline">
                Conformément au CDCT, seuls 2 modes de règlement sont retenus — pas de virement bancaire ni de multi-comptes.
            </p>

            <p class="mb-xs mt-lg text-caption font-semibold uppercase text-outline">Conditions de paiement</p>
            @foreach ([['Comptant', 'Vente soldée à l\'encaissement'], ['Avance', 'Vente à crédit — suivie dans Clients & Créances']] as [$condition, $note])
                <div class="flex items-center justify-between border-b border-outline-variant py-sm">
                    <div><p class="text-xs font-bold">{{ $condition }}</p><p class="text-caption text-outline">{{ $note }}</p></div>
                    <span class="rounded-full bg-success-container px-sm py-xs text-caption font-semibold text-success-deep">Toujours actif</span>
                </div>
            @endforeach
            <p class="mt-sm rounded-lg bg-brand-gold/10 p-sm text-xs text-brand-navy">
                « Avance (Solde Restant Dû) » figurait jusqu'ici parmi les modes de règlement. C'est une condition de paiement : une
                avance se verse en espèces ou en Mobile Money, comme toute autre vente. Les deux se choisissent désormais séparément au
                point de vente, ce qui permet enfin de savoir avec quoi une avance a été encaissée.
            </p>
        </section>
    @endif

    {{-- ============================================================ 4 · Appairage --}}
    @if ($onglet === 4)
        <section class="rounded-lg border border-outline-variant bg-surface-card p-md" data-onglet="appairage">
            <h2 class="mb-sm text-section-title font-bold">Appairage</h2>
            @can('manage-users')
                <p class="mb-md text-xs text-outline">Les postes connus du serveur, leur état et la révocation de leur appairage.</p>
                <a href="{{ route('postes') }}" class="inline-block rounded-lg bg-brand-navy px-md py-sm text-xs font-semibold text-white hover:bg-brand-navy-dark">
                    Ouvrir Postes &amp; Appairage
                </a>
            @else
                <p class="text-xs text-outline">La gestion des postes appairés est réservée à l'administrateur.</p>
            @endcan
        </section>
    @endif

    {{-- ============================================================ 5-7 · Au poste --}}
    @if ($onglet >= 5)
        <section class="rounded-lg border border-outline-variant bg-surface-card p-md" data-onglet="au-poste">
            <h2 class="mb-sm text-section-title font-bold">{{ $onglets[$onglet] }}</h2>
            <p class="rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="au-poste">
                @if ($onglet === 5)
                    Les sauvegardes sont des copies de la base de chaque poste : elles se créent, se restaurent et se téléchargent sur le poste.
                @elseif ($onglet === 6)
                    La corbeille contient les éléments archivés de chaque poste : leur restauration ou leur effacement définitif se gère sur le poste.
                @else
                    La remise à zéro et la préparation de données d'essai se font uniquement sur le poste, sous son verrou « Données de Test ».
                @endif
                Cet onglet se gère sur le poste : rien ne s'y fait depuis le web.
            </p>
        </section>
    @endif
</div>
