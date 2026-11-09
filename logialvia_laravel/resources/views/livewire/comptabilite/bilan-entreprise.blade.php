<div>
    @php($f = \App\Support\FormatComptable::class)
    @include('livewire.comptabilite._entete')

    <p class="mb-md rounded-lg bg-surface-zebra p-sm text-xs text-outline" data-ecart="lecture-seule">
        Lecture seule : somme des écritures de tous les postes. Export PDF : au poste.
    </p>

    @if ($bilan['vide'])
        <p class="mb-md rounded-lg border border-outline-variant bg-surface-zebra p-md text-xs font-bold text-outline" data-bandeau="vide">
            Aucune écriture sur l'exercice {{ $annee }} : il n'y a encore ni bien à inscrire à l'actif, ni dette au passif.</p>
    @elseif ($bilan['equilibre'])
        <p class="mb-md rounded-lg border border-success-deep/30 bg-success-container p-md text-xs font-bold text-success-deep" data-bandeau="equilibre">
            Bilan équilibré — Total Actif = Total Passif = {{ $f::montant($bilan['total_actif']) }}.</p>
    @else
        <p class="mb-md rounded-lg border border-error-deep/30 bg-error-container p-md text-xs font-bold text-error-deep" role="alert" data-bandeau="ecart">
            Écart de {{ $f::montant(abs($bilan['ecart'])) }} entre l'actif et le passif.
            @if ($bilan['ecart'] > 0)
                L'entreprise détient des biens dont l'origine n'a pas été enregistrée — le plus souvent l'apport de départ. Saisissez-le au compte 101 (Capital) depuis le Journal Comptable.
            @else
                Le passif dépasse l'actif : une ressource est enregistrée sans l'emploi correspondant. Vérifiez le Journal Comptable — une écriture de contrepartie manque probablement.
            @endif
        </p>
    @endif

    <div class="grid grid-cols-1 gap-md lg:grid-cols-2">
        @foreach ([['ACTIF', $bilan['actif'], 'TOTAL ACTIF', $bilan['total_actif'], null, 'actif'], ['PASSIF', $bilan['passif'], 'TOTAL PASSIF', $bilan['total_passif'], $ecartNonEnregistre, 'passif']] as [$titreCarte, $postes, $libelleTotal, $total, $ecart, $cle])
            <section class="overflow-hidden rounded-lg border border-outline-variant bg-surface-card shadow-sm" data-carte="{{ $cle }}">
                <header class="bg-brand-navy px-md py-sm font-bold text-white">{{ $titreCarte }}</header>
                @foreach ($postes as $p)
                    <div class="flex items-baseline justify-between gap-sm border-b border-outline-variant px-md py-sm text-xs" data-poste="{{ $p['compte'] }}">
                        <span>{{ $p['libelle'] }} <span class="font-mono text-outline">({{ $p['compte'] }})</span></span>
                        <span class="{{ abs($p['montant']) < 0.01 ? 'text-outline' : 'font-bold' }}" data-montant>{{ abs($p['montant']) < 0.01 ? '—' : $f::nombre($p['montant']) }}</span>
                    </div>
                @endforeach
                @if ($ecart !== null)
                    <div class="flex items-baseline justify-between gap-sm border-b border-outline-variant bg-error-container px-md py-sm text-xs font-bold text-error-deep" data-ligne="ecart">
                        <span>Origine non enregistrée — à saisir au compte 101</span><span>{{ $f::nombre($ecart) }}</span>
                    </div>
                @endif
                <footer class="flex justify-between border-t-2 border-brand-navy bg-brand-gold/10 px-md py-sm text-xs font-bold" data-total="{{ $cle }}">
                    <span>{{ $libelleTotal }}</span><span>{{ $f::nombre($total) }} FCFA</span>
                </footer>
            </section>
        @endforeach
    </div>
</div>
