<?php

namespace App\Livewire;

use App\Models\CycleCouveuse;
use App\Models\MachineIncubateur;
use App\Support\SuiviIncubation;
use App\Sync\Tables\CyclesCouveuseTable;
use App\Sync\Tables\MachinesIncubateurTable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;
use RuntimeException;

/**
 * Cycle Couveuse (Dart : `cycle_couveuse_screen.dart` et `modales_couveuse.dart`).
 *
 * Les lots et les incubateurs sont des FAITS (dernier ecrivain gagne). Le web ecrit par
 * `CyclesCouveuseTable::absorber` et `MachinesIncubateurTable::absorber` — la meme validation
 * et la meme regle que pour un poste. Les mirages sont deux colonnes du lot, saisies dans le
 * temps ; la suppression d'un lot est une pierre tombale. Aucun effet de bord : la couveuse
 * n'ecrit NI naissances dans les fiches d'elevage, NI stock, NI ecriture.
 *
 * Ecarts avec le Dart (declares) : pas d'export PDF, pas de fenetre « lignee des remplacements »
 * (le lot d'origine reste visible : « ↳ remplace C-… »), numerotation propre au web
 * (`C-WEB-AAAA-NNN`, le web n'a pas de code de poste).
 */
#[Layout('components.layouts.app')]
class Couveuse extends Component
{
    /** Date de reference (« Situation au … ») ; vide = aujourd'hui. */
    public string $reference = '';

    public string $filtreStatut = '';

    public string $filtreEspece = '';

    public string $filtreMachine = '';

    public ?string $message = null;

    // Declarer / modifier un cycle
    public bool $formulaireLot = false;

    public ?string $lotId = null;

    public string $espece = '';

    public string $dateChargement = '';

    public string $machineId = '';

    public string $oeufs = '';

    // Mirage
    public ?string $mirageLotId = null;

    public int $mirageJour = SuiviIncubation::JOUR_MIRAGE_1;

    public string $mirageRetires = '';

    // Eclosion
    public ?string $eclosionLotId = null;

    public string $poussins = '';

    public string $perdus = '';

    public bool $remplacer = false;

    public string $remplacementOeufs = '';

    public string $remplacementEspece = '';

    public string $remplacementDate = '';

    // Suppression
    public ?string $aSupprimer = null;

    // Incubateur
    public bool $formulaireMachine = false;

    public string $machineCode = '';

    public string $machineLibelle = '';

    public string $machineCapacite = '';

    public ?string $erreur = null;

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-elevage'), 403);
    }

    // ------------------------------------------------------------- Outils

    /** « Aujourd'hui » au fuseau de l'exploitation, ou la date de reference choisie. */
    private function dateDeReference(): CarbonImmutable
    {
        $texte = trim($this->reference);
        if ($texte !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $texte) === 1) {
            return SuiviIncubation::jour($texte);
        }

        return SuiviIncubation::jour(CarbonImmutable::now(config('logialvia.fuseau')));
    }

    public function aujourdhui(): void
    {
        $this->reference = '';
    }

    /**
     * Instant de saisie du web : maintenant, a la microseconde, mais JAMAIS avant la derniere
     * saisie connue de la ligne (un poste dont l'horloge avance ferait ignorer la saisie du web
     * sans qu'on le dise : « dernier ecrivain gagne » exige un instant strictement posterieur).
     */
    private function maintenant(?CarbonImmutable $apres = null): string
    {
        $instant = CarbonImmutable::now('UTC');
        if ($apres !== null && ! $instant->greaterThan($apres)) {
            $instant = $apres->addMicrosecond();
        }

        return $instant->format('Y-m-d\TH:i:s.u\Z');
    }

    private function lot(?string $id): ?CycleCouveuse
    {
        return $id === null ? null : CycleCouveuse::query()->whereNull('supprime_le')->find($id);
    }

    /** La ligne complete d'un lot (le serveur valide toute la ligne, jamais un morceau). */
    private function ligne(CycleCouveuse $lot, array $surcharge = []): array
    {
        return array_merge([
            'id' => $lot->id,
            'code_incubation' => $lot->code_incubation,
            'espece' => $lot->espece,
            'date_incubation' => $lot->date_incubation->format('Y-m-d'),
            'oeufs_couves' => $lot->oeufs_couves,
            'poussins_nes' => $lot->poussins_nes,
            'oeufs_perdus' => $lot->oeufs_perdus,
            'statut' => $lot->statut,
            'machine_id' => $lot->machine_id,
            'oeufs_blancs_j7' => $lot->oeufs_blancs_j7,
            'oeufs_gates_j14' => $lot->oeufs_gates_j14,
            'lot_parent_id' => $lot->lot_parent_id,
            'supprime_le' => null,
        ], $surcharge, ['updated_at' => $this->maintenant($lot->updated_at?->toImmutable())]);
    }

    private function ecrire(array $ligne): ?string
    {
        return (new CyclesCouveuseTable)->absorber(Catalogue::POSTE_WEB, $ligne);
    }

    /** Numero officiel d'un lot cree au web : `C-WEB-2026-001` (le web n'a pas de code de poste). */
    private function prochainCode(int $annee): string
    {
        $prefixe = "C-WEB-$annee-";
        $maximum = 0;
        foreach (CycleCouveuse::query()->where('code_incubation', 'like', $prefixe.'%')->pluck('code_incubation') as $code) {
            $numero = substr($code, strlen($prefixe));
            if (ctype_digit($numero) && (int) $numero > $maximum) {
                $maximum = (int) $numero;
            }
        }

        return $prefixe.str_pad((string) ($maximum + 1), 3, '0', STR_PAD_LEFT);
    }

    private function entier(string $texte): ?int
    {
        $texte = trim($texte);

        return $texte !== '' && ctype_digit($texte) ? (int) $texte : null;
    }

    // ------------------------------------------------- Declarer / modifier

    public function nouveauLot(): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['lotId', 'espece', 'dateChargement', 'machineId', 'oeufs', 'erreur', 'message']);
        $this->formulaireLot = true;
    }

    public function modifierLot(string $id): void
    {
        $this->verifierDroitDeGerer();
        $lot = $this->lot($id);
        if ($lot === null) {
            return;
        }
        $this->reset(['erreur', 'message']);
        $this->lotId = $lot->id;
        $this->espece = $lot->espece;
        $this->dateChargement = $lot->date_incubation->format('Y-m-d');
        $this->machineId = (string) $lot->machine_id;
        $this->oeufs = (string) $lot->oeufs_couves;
        $this->formulaireLot = true;
    }

    public function enregistrerLot(): void
    {
        $this->verifierDroitDeGerer();
        $lot = $this->lot($this->lotId);
        if ($this->lotId !== null && $lot === null) {
            $this->erreur = 'Ce lot n\'existe plus.';

            return;
        }

        // Validations de la modale (VM du poste : `creerCycle`, `modifierCycle`).
        if ($lot !== null && ! SuiviIncubation::enCours($lot)) {
            $this->erreur = 'Un cycle éclos ne peut plus être modifié : son taux d\'éclosion est déjà entré dans les statistiques.';

            return;
        }
        if (! array_key_exists($this->espece, SuiviIncubation::ESPECES)) {
            $this->erreur = 'L\'espèce est obligatoire.';

            return;
        }
        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $this->dateChargement) !== 1) {
            $this->erreur = 'La date est obligatoire.';

            return;
        }
        $charges = $this->entier($this->oeufs);
        if ($charges === null || $charges < 1) {
            $this->erreur = 'Le nombre d\'œufs est obligatoire.';

            return;
        }

        if ($lot === null) {
            $motif = $this->ecrire([
                'id' => (string) Str::uuid(),
                'code_incubation' => $this->prochainCode((int) substr($this->dateChargement, 0, 4)),
                'espece' => $this->espece,
                'date_incubation' => $this->dateChargement,
                'oeufs_couves' => $charges,
                'poussins_nes' => null,
                'oeufs_perdus' => null,
                'statut' => SuiviIncubation::EN_INCUBATION,
                'machine_id' => $this->machineId === '' ? null : $this->machineId,
                'oeufs_blancs_j7' => null,
                'oeufs_gates_j14' => null,
                'lot_parent_id' => null,
                'supprime_le' => null,
                'updated_at' => $this->maintenant(),
            ]);
        } else {
            // Comme le poste : « Non précisé » ne retire pas l'incubateur d'un lot existant.
            $motif = $this->ecrire($this->ligne($lot, [
                'espece' => $this->espece,
                'date_incubation' => $this->dateChargement,
                'oeufs_couves' => $charges,
                'machine_id' => $this->machineId === '' ? $lot->machine_id : $this->machineId,
            ]));
        }

        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = $lot === null ? 'Cycle enregistré avec succès.' : "Cycle {$lot->code_incubation} modifié.";
        $this->formulaireLot = false;
        $this->erreur = null;
    }

    // ---------------------------------------------------------------- Mirage

    public function ouvrirMirage(string $id, int $jour): void
    {
        $this->verifierDroitDeGerer();
        $lot = $this->lot($id);
        if ($lot === null) {
            return;
        }
        $this->reset(['erreur', 'message', 'mirageRetires']);
        $this->mirageLotId = $lot->id;
        $this->mirageJour = $jour;
        $valeur = $jour === SuiviIncubation::JOUR_MIRAGE_1 ? $lot->oeufs_blancs_j7 : $lot->oeufs_gates_j14;
        $this->mirageRetires = $valeur === null ? '' : (string) $valeur;
    }

    public function enregistrerMirage(): void
    {
        $this->verifierDroitDeGerer();
        $lot = $this->lot($this->mirageLotId);
        if ($lot === null) {
            $this->erreur = 'Ce lot n\'existe plus.';

            return;
        }
        if (! SuiviIncubation::enCours($lot)) {
            $this->erreur = 'Ce lot est clôturé : ses mirages ne peuvent plus être saisis.';

            return;
        }
        if (! in_array($this->mirageJour, [SuiviIncubation::JOUR_MIRAGE_1, SuiviIncubation::JOUR_MIRAGE_2], true)) {
            $this->erreur = 'Le mirage se fait à J+7 ou à J+14.';

            return;
        }
        $retires = $this->entier($this->mirageRetires);
        if ($retires === null) {
            $this->erreur = 'Le nombre d\'œufs retirés est obligatoire.';

            return;
        }

        // Un mirage ne retire pas plus d'œufs qu'il n'en reste, sinon le denominateur du TER
        // deviendrait negatif.
        $premier = $this->mirageJour === SuiviIncubation::JOUR_MIRAGE_1;
        $dejaRetires = $premier ? ($lot->oeufs_gates_j14 ?? 0) : ($lot->oeufs_blancs_j7 ?? 0);
        if ($retires + $dejaRetires > $lot->oeufs_couves) {
            $this->erreur = "Ce lot ne contient que {$lot->oeufs_couves} œufs, dont $dejaRetires déjà retirés : impossible d'en retirer $retires de plus.";

            return;
        }

        $motif = $this->ecrire($this->ligne($lot, [$premier ? 'oeufs_blancs_j7' : 'oeufs_gates_j14' => $retires]));
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = "Mirage enregistré sur {$lot->code_incubation}.";
        $this->mirageLotId = null;
        $this->erreur = null;
    }

    // --------------------------------------------------------------- Eclosion

    public function ouvrirEclosion(string $id): void
    {
        $this->verifierDroitDeGerer();
        $lot = $this->lot($id);
        if ($lot === null) {
            return;
        }
        $this->reset(['erreur', 'message', 'poussins', 'perdus', 'remplacer', 'remplacementOeufs']);
        $this->eclosionLotId = $lot->id;
        $this->remplacementEspece = $lot->espece;
        $this->remplacementDate = CarbonImmutable::now(config('logialvia.fuseau'))->format('Y-m-d');
    }

    public function enregistrerEclosion(): void
    {
        $this->verifierDroitDeGerer();
        $lot = $this->lot($this->eclosionLotId);
        if ($lot === null) {
            $this->erreur = 'Ce lot n\'existe plus.';

            return;
        }
        if (! SuiviIncubation::enCours($lot)) {
            $this->erreur = 'Ce lot est déjà clôturé.';

            return;
        }

        foreach ([$this->poussins, $this->perdus] as $saisie) {
            if (trim($saisie) !== '' && ! ctype_digit(trim($saisie))) {
                $this->erreur = 'Les quantités ne peuvent être négatives.';

                return;
            }
        }
        $eclos = $this->entier($this->poussins) ?? 0;
        $perdus = $this->entier($this->perdus) ?? 0;

        // On ne peut pas faire eclore plus d'œufs qu'il n'en RESTE apres les mirages.
        $retenus = SuiviIncubation::retenus($lot);
        if ($eclos + $perdus > $retenus) {
            $total = $eclos + $perdus;
            $this->erreur = "Poussins éclos + œufs perdus ($total) dépasse les $retenus œufs encore en incubation après les mirages.";

            return;
        }

        $remplacement = $this->remplacer ? $this->entier($this->remplacementOeufs) : null;
        $remplace = $remplacement !== null && $remplacement > 0;
        if ($remplace && ! array_key_exists($this->remplacementEspece, SuiviIncubation::ESPECES)) {
            $this->erreur = 'L\'espèce du remplacement est obligatoire.';

            return;
        }
        if ($remplace && preg_match('/^\d{4}-\d{2}-\d{2}$/', $this->remplacementDate) !== 1) {
            $this->erreur = 'La date d\'insertion est obligatoire.';

            return;
        }

        // Cloture et remplacement dans UNE transaction : si la creation du sous-lot echoue, le lot
        // d'origine ne doit pas rester marque « Remplacé » alors que sa place est restee vide.
        try {
            DB::transaction(function () use ($lot, $eclos, $perdus, $remplace, $remplacement) {
                $motif = $this->ecrire($this->ligne($lot, [
                    'poussins_nes' => $eclos,
                    'oeufs_perdus' => $perdus,
                    'statut' => $remplace ? SuiviIncubation::REMPLACE : SuiviIncubation::ECLOSION_EFFECTUEE,
                ]));
                if ($motif !== null) {
                    throw new RuntimeException($motif);
                }
                if ($remplace) {
                    $motif = $this->ecrire([
                        'id' => (string) Str::uuid(),
                        'code_incubation' => $this->prochainCode((int) substr($this->remplacementDate, 0, 4)),
                        'espece' => $this->remplacementEspece,
                        'date_incubation' => $this->remplacementDate,
                        'oeufs_couves' => $remplacement,
                        'poussins_nes' => null,
                        'oeufs_perdus' => null,
                        'statut' => SuiviIncubation::EN_INCUBATION,
                        'machine_id' => $lot->machine_id,
                        'oeufs_blancs_j7' => null,
                        'oeufs_gates_j14' => null,
                        'lot_parent_id' => $lot->id,
                        'supprime_le' => null,
                        'updated_at' => $this->maintenant(),
                    ]);
                    if ($motif !== null) {
                        throw new RuntimeException($motif);
                    }
                }
            });
        } catch (RuntimeException $e) {
            $this->erreur = $e->getMessage();

            return;
        }

        $this->message = "Éclosion du cycle {$lot->code_incubation} enregistrée.";
        $this->eclosionLotId = null;
        $this->erreur = null;
    }

    // ------------------------------------------------------------ Suppression

    public function demanderSuppression(string $id): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->erreur = null;
        $lot = $this->lot($id);
        if ($lot !== null && ! SuiviIncubation::enCours($lot)) {
            $this->message = 'Un cycle éclos ne peut pas être supprimé : ses poussins sont déjà entrés dans les effectifs de la filière.';

            return;
        }
        $this->aSupprimer = $lot?->id;
    }

    public function confirmerSuppression(): void
    {
        $this->verifierDroitDeGerer();
        $lot = $this->lot($this->aSupprimer);
        $this->aSupprimer = null;
        if ($lot === null) {
            return;
        }
        if (! SuiviIncubation::enCours($lot)) {
            $this->message = 'Un cycle éclos ne peut pas être supprimé : ses poussins sont déjà entrés dans les effectifs de la filière.';

            return;
        }

        // Les sous-lots deviennent des lots racines plutot que de disparaitre : ils sont
        // physiquement dans la machine. Puis pierre tombale du lot (le serveur n'efface jamais).
        try {
            DB::transaction(function () use ($lot) {
                $enfants = CycleCouveuse::query()->whereNull('supprime_le')->where('lot_parent_id', $lot->id)->get();
                foreach ($enfants as $enfant) {
                    $motif = $this->ecrire($this->ligne($enfant, ['lot_parent_id' => null]));
                    if ($motif !== null) {
                        throw new RuntimeException($motif);
                    }
                }
                $motif = $this->ecrire($this->ligne($lot, ['supprime_le' => $this->maintenant($lot->updated_at?->toImmutable())]));
                if ($motif !== null) {
                    throw new RuntimeException($motif);
                }
            });
        } catch (RuntimeException $e) {
            $this->message = $e->getMessage();

            return;
        }
        $this->message = "Cycle {$lot->code_incubation} supprimé.";
    }

    // -------------------------------------------------------------- Incubateur

    public function nouvelIncubateur(): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['machineCode', 'machineLibelle', 'machineCapacite', 'erreur', 'message']);
        $this->formulaireMachine = true;
    }

    public function enregistrerIncubateur(): void
    {
        $this->verifierDroitDeGerer();
        $code = trim($this->machineCode);
        $libelle = trim($this->machineLibelle);
        $capacite = trim($this->machineCapacite);

        if ($code === '') {
            $this->erreur = 'Le code est obligatoire.';

            return;
        }
        if ($libelle === '') {
            $this->erreur = 'Le libellé est obligatoire.';

            return;
        }
        if (MachineIncubateur::query()->whereRaw('lower(code) = ?', [mb_strtolower($code)])->exists()) {
            $this->erreur = "Un incubateur porte déjà le code $code.";

            return;
        }
        if ($capacite !== '' && (! ctype_digit($capacite) || (int) $capacite <= 0)) {
            $this->erreur = 'La capacité doit être supérieure à 0.';

            return;
        }

        $motif = (new MachinesIncubateurTable)->absorber(Catalogue::POSTE_WEB, [
            // Meme identite que le poste : l'UUID derive du code.
            'id' => self::uuidDeCode($code),
            'code' => $code,
            'libelle' => $libelle,
            'capacite_oeufs' => $capacite === '' ? null : (int) $capacite,
            'active' => true,
            'updated_at' => $this->maintenant(),
        ]);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = "Incubateur $code enregistré.";
        $this->formulaireMachine = false;
        $this->erreur = null;
    }

    /**
     * UUID deterministe depuis le code (`machine:inc-01`), identique a `uuidDeterministe` du
     * poste : deux postes — et le web — qui declarent « INC-01 » designent le meme incubateur.
     */
    public static function uuidDeCode(string $code): string
    {
        $octets = array_values(unpack('C16', substr(sha1('logialvia:machine:'.mb_strtolower(trim($code)), true), 0, 16)));
        $octets[6] = ($octets[6] & 0x0F) | 0x50;
        $octets[8] = ($octets[8] & 0x3F) | 0x80;
        $hex = implode('', array_map(fn (int $o) => str_pad(dechex($o), 2, '0', STR_PAD_LEFT), $octets));

        return substr($hex, 0, 8).'-'.substr($hex, 8, 4).'-'.substr($hex, 12, 4).'-'.substr($hex, 16, 4).'-'.substr($hex, 20);
    }

    public function annuler(): void
    {
        $this->formulaireLot = false;
        $this->formulaireMachine = false;
        $this->mirageLotId = null;
        $this->eclosionLotId = null;
        $this->aSupprimer = null;
        $this->erreur = null;
    }

    // ------------------------------------------------------------------ Rendu

    public function render()
    {
        $t = $this->dateDeReference();
        $tous = CycleCouveuse::query()->whereNull('supprime_le')->orderByDesc('date_incubation')->orderByDesc('code_incubation')->get();
        $machines = MachineIncubateur::query()->whereNull('supprime_le')->orderBy('code')->get();
        $codes = $tous->pluck('code_incubation', 'id');
        $codesMachines = $machines->pluck('code', 'id');

        $lots = $tous->filter(function (CycleCouveuse $l) {
            if ($this->filtreStatut === 'en_cours' && ! SuiviIncubation::enCours($l)) {
                return false;
            }
            if ($this->filtreStatut === 'eclos' && SuiviIncubation::enCours($l)) {
                return false;
            }
            if ($this->filtreEspece !== '' && $l->espece !== $this->filtreEspece) {
                return false;
            }
            if ($this->filtreMachine !== '' && $l->machine_id !== $this->filtreMachine) {
                return false;
            }

            return true;
        })->values();

        $alertes = SuiviIncubation::alertes($tous, $t);
        $tauxBrut = SuiviIncubation::tauxBrutMoyen($tous);

        return view('livewire.couveuse', [
            'jourRef' => $t,
            'estAujourdhui' => $t->equalTo(SuiviIncubation::jour(CarbonImmutable::now(config('logialvia.fuseau')))),
            'tous' => $tous,
            'lots' => $lots,
            'machines' => $machines,
            'codes' => $codes,
            'codesMachines' => $codesMachines,
            'alertes' => $alertes,
            'enRetard' => count(array_filter($alertes, fn (array $a) => $a['ecart'] > 0)),
            'aVenir' => SuiviIncubation::aVenir($tous, $t),
            'cyclesEnCours' => $tous->filter(fn (CycleCouveuse $l) => SuiviIncubation::enCours($l))->count(),
            'poussinsAttendus' => SuiviIncubation::poussinsAttendus($tous),
            'tauxBrut' => $tauxBrut,
            'tauxReel' => SuiviIncubation::terMoyen($tous, $t),
            'oeufsEnIncubation' => SuiviIncubation::oeufsEnIncubation($tous),
            'peutGerer' => Auth::user()?->can('manage-elevage') ?? false,
            'lotMirage' => $this->lot($this->mirageLotId),
            'lotEclosion' => $this->lot($this->eclosionLotId),
            'lotASupprimer' => $this->lot($this->aSupprimer),
            'especes' => SuiviIncubation::ESPECES,
        ])->title('Cycle Couveuse');
    }
}
