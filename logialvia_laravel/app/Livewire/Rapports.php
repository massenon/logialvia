<?php

namespace App\Livewire;

use App\Services\Comptabilite\LivreComptable;
use App\Services\Rapports\CalculRapports;
use App\Services\Rapports\RapportElevage;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Rapports & Etats (Dart : `rapports_exports_screen.dart`, `rapports_view_model.dart`,
 * `rapports_repository_drift.dart`, `documents_rapports.dart`) — LECTURE SEULE.
 *
 * Six onglets sur une periode commune : Recettes et Depenses, Etat de Tresorerie, Creances Clients, Dettes
 * Fournisseurs, Rapport Elevage, Rapport de Stocks. Le web calcule depuis les tables du SERVEUR (ecritures de
 * tous les postes, ventes, achats, fiches d'elevage, soins, infirmerie, couveuse) ; les calculs vivent dans
 * `App\Services\Rapports\*`, la comptabilite est lue par `LivreComptable` (jamais recalculee).
 *
 * Le STOCK et le PMP sont propres a chaque poste (decision du client, `46_` §14-§15) : l'onglet Stocks est un
 * encart grise « Disponible sur le poste », jamais un chiffre invente.
 *
 * Export : CSV de l'onglet affiche avec ses filtres (le poste produit un PDF), protege par `export-rapports`.
 */
#[Layout('components.layouts.app')]
class Rapports extends Component
{
    public const ONGLETS = [
        'recettes' => 'Recettes et Dépenses',
        'tresorerie' => 'État de Trésorerie',
        'creances' => 'Créances Clients',
        'dettes' => 'Dettes Fournisseurs',
        'elevage' => 'Rapport Élevage',
        'stocks' => 'Rapport de Stocks',
    ];

    public const CENTRES = [
        CalculRapports::AVICULTURE => 'Aviculture (Goliaths/Pintades)',
        CalculRapports::COMMERCE_ANNEXE => 'Commerce Annexe',
        CalculRapports::CHARGE_GENERALE => 'Charge Générale',
    ];

    public const STATUTS_CREANCE = ['En Retard', 'À Échoir'];

    public const STATUTS_DETTE = ['Urgent', 'Normal'];

    public string $onglet = 'recettes';

    /** Periode commune, `Y-m-d` (Dart : 1er du mois -> aujourd'hui). */
    public string $debut = '';

    public string $fin = '';

    public ?string $filtreCentre = null;

    public ?string $filtreCompte = null;

    public ?string $filtreStatutCreance = null;

    public ?string $filtreStatutDette = null;

    public function mount(): void
    {
        $this->verifierLecture();
        $maintenant = $this->maintenant();
        $this->debut = $maintenant->startOfMonth()->format('Y-m-d');
        $this->fin = $maintenant->format('Y-m-d');
    }

    private function maintenant(): CarbonImmutable
    {
        return CarbonImmutable::now(config('logialvia.fuseau'));
    }

    private function peut(string $droit): bool
    {
        return Auth::user()?->can($droit) ?? false;
    }

    /** Chaque appel Livewire revalide le droit : la route ne protege que le premier chargement. */
    private function verifierLecture(): void
    {
        abort_unless($this->peut('view-rapports'), 403);
    }

    /** Jour `Y-m-d` saisi, ou null s'il est invalide. */
    private function jour(string $valeur): ?CarbonImmutable
    {
        try {
            $date = CarbonImmutable::createFromFormat('!Y-m-d', $valeur, config('logialvia.fuseau'));
        } catch (\Carbon\Exceptions\InvalidFormatException) {
            return null;
        }

        return ($date !== false && $date->format('Y-m-d') === $valeur) ? $date : null;
    }

    /**
     * Periode effective : [debut 00:00:00, fin 23:59:59.999999] en heure LOCALE, bornes incluses (une operation
     * du 08/08 entre dans « au 08/08 »). Une periode inversee est remise d'aplomb (le poste echange les deux
     * dates) ; une date invalide retombe sur le mois en cours, et l'ecran le dit.
     *
     * @return array{0: CarbonImmutable, 1: CarbonImmutable, 2: bool} [debut, fin, valide]
     */
    private function periode(): array
    {
        $maintenant = $this->maintenant();
        $d = $this->jour($this->debut);
        $f = $this->jour($this->fin);
        if ($d === null || $f === null) {
            return [$maintenant->startOfMonth(), $maintenant->endOfDay(), false];
        }
        if ($f->lessThan($d)) {
            [$d, $f] = [$f, $d];
        }

        return [$d->startOfDay(), $f->endOfDay(), true];
    }

    public function updatedDebut(): void
    {
        $this->remettreDAplomb();
    }

    public function updatedFin(): void
    {
        $this->remettreDAplomb();
    }

    private function remettreDAplomb(): void
    {
        $d = $this->jour($this->debut);
        $f = $this->jour($this->fin);
        if ($d !== null && $f !== null && $f->lessThan($d)) {
            [$this->debut, $this->fin] = [$this->fin, $this->debut];
        }
    }

    public function choisirOnglet(string $onglet): void
    {
        $this->onglet = array_key_exists($onglet, self::ONGLETS) ? $onglet : 'recettes';
    }

    public function reinitialiserFiltres(): void
    {
        $this->filtreCentre = $this->filtreCompte = $this->filtreStatutCreance = $this->filtreStatutDette = null;
    }

    /** Un filtre n'accepte que ses propres options (une valeur trafiquee vaut « tous »). */
    private function filtre(?string $valeur, array $options): ?string
    {
        return ($valeur !== null && in_array($valeur, $options, true)) ? $valeur : null;
    }

    /**
     * Donnees de l'onglet actif, filtres inclus.
     *
     * @return array<string, mixed>
     */
    private function donnees(string $onglet, CarbonImmutable $debut, CarbonImmutable $fin): array
    {
        $maintenant = $this->maintenant();

        switch ($onglet) {
            case 'recettes':
                $lignes = CalculRapports::recettesDepenses(LivreComptable::toutes(), LivreComptable::plan(), $debut, $fin);
                $centre = $this->filtre($this->filtreCentre, array_keys(self::CENTRES));

                return CalculRapports::syntheseRecettes($lignes, $centre) + ['toutes' => count($lignes), 'centre' => $centre];

            case 'tresorerie':
                $plan = LivreComptable::plan();
                $livre = LivreComptable::toutes();
                $tout = CalculRapports::tresorerie($livre, $plan, $debut, $fin, null);
                $compte = $this->filtre($this->filtreCompte, $tout['libelles']);

                return $compte === null ? $tout + ['compte' => null] : CalculRapports::tresorerie($livre, $plan, $debut, $fin, $compte) + ['compte' => $compte];

            case 'creances':
                $toutes = CalculRapports::creances($maintenant);
                $statut = $this->filtre($this->filtreStatutCreance, self::STATUTS_CREANCE);

                return CalculRapports::syntheseCreances($toutes) + [
                    'lignes' => array_values(array_filter($toutes, fn (array $l) => $statut === null || $l['statut'] === $statut)),
                    'toutes' => count($toutes),
                    'statut' => $statut,
                ];

            case 'dettes':
                $toutes = CalculRapports::dettes($maintenant);
                $statut = $this->filtre($this->filtreStatutDette, self::STATUTS_DETTE);

                return CalculRapports::syntheseDettes($toutes) + [
                    'lignes' => array_values(array_filter($toutes, fn (array $l) => $statut === null || $l['statut'] === $statut)),
                    'toutes' => count($toutes),
                    'statut' => $statut,
                ];

            case 'elevage':
                return RapportElevage::calculer($debut, $fin);

            default:
                return []; // Stocks : aucune donnee (propre a chaque poste).
        }
    }

    /** Export CSV de l'onglet affiche, avec ses filtres (le poste exporte un PDF du meme panneau). */
    public function exporter(): ?StreamedResponse
    {
        abort_unless($this->peut('view-rapports') && $this->peut('export-rapports'), 403);

        $onglet = array_key_exists($this->onglet, self::ONGLETS) ? $this->onglet : 'recettes';
        if ($onglet === 'stocks') {
            return null; // Rien a exporter : le stock est propre a chaque poste.
        }

        [$debut, $fin] = $this->periode();
        $donnees = $this->donnees($onglet, $debut, $fin);
        $lignes = $this->lignesCsv($onglet, $donnees, $debut, $fin);
        $nom = 'rapport-'.$onglet.'-'.$debut->format('Ymd').'-'.$fin->format('Ymd').'.csv';

        return response()->streamDownload(function () use ($lignes) {
            $sortie = fopen('php://output', 'w');
            fwrite($sortie, "\xEF\xBB\xBF"); // BOM : Excel lit l'UTF-8
            foreach ($lignes as $ligne) {
                fputcsv($sortie, $ligne, ';', '"', '');
            }
            fclose($sortie);
        }, $nom, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    private static function n(float $v): string
    {
        return (string) (int) round($v);
    }

    private static function p(?float $v): string
    {
        return $v === null ? '—' : number_format($v, 1, ',', '').' %';
    }

    private static function d(?CarbonImmutable $d): string
    {
        return $d === null ? '—' : $d->format('d/m/Y');
    }

    /**
     * Cellules du CSV : titre, periode, indicateurs, puis chaque tableau avec son en-tete (memes colonnes que l'ecran).
     *
     * @param  array<string, mixed>  $x
     * @return list<list<string>>
     */
    private function lignesCsv(string $onglet, array $x, CarbonImmutable $debut, CarbonImmutable $fin): array
    {
        $n = self::n(...);
        $p = self::p(...);
        $d = self::d(...);
        $titre = self::ONGLETS[$onglet];
        $out = [[$titre], ['Période', 'du '.$d($debut).' au '.$d($fin)], []];

        switch ($onglet) {
            case 'recettes':
                $out[] = ['Total Recettes', $n($x['total_recettes'])];
                $out[] = ['Total Dépenses', $n($x['total_depenses'])];
                $out[] = ['Résultat Net', $n($x['resultat_net'])];
                $out[] = ['Taux de Marge Brute', $p($x['taux_marge'])];
                $out[] = [];
                $out[] = ['Période', 'N° Pièce', 'Catégorie SYSCOHADA', 'Centre de Profit', 'Encaissement', 'Décaissement', 'Solde Cumulé'];
                foreach ($x['lignes'] as $l) {
                    $out[] = [$l['periode'], $l['numero_piece'], $l['categorie'], $l['centre'], $n($l['encaissement']), $n($l['decaissement']), $n($l['cumul'])];
                }
                break;

            case 'tresorerie':
                foreach ($x['libelles'] as $lib) {
                    $out[] = [$lib, $n($x['clotures'][$lib])];
                }
                $out[] = ['Trésorerie Nette', $n($x['nette'])];
                $out[] = [];
                $out[] = ['Date', 'Compte', 'Type d\'Opération', 'Libellé', 'Entrée', 'Sortie', 'Solde Progressif'];
                foreach ($x['ouvertures'] as $o) {
                    $out[] = [$d($debut), $o['court'], 'Solde d\'Ouverture', '', '', '', $n($o['ouverture'])];
                }
                foreach ($x['mouvements'] as $m) {
                    $out[] = [$d($m['date']), $m['compte'], $m['type'], $m['libelle'], $n($m['entree']), $n($m['sortie']), $n($m['solde'])];
                }
                break;

            case 'creances':
                $out[] = ['Créances En Cours', $n($x['en_cours'])];
                $out[] = ['Créances en Retard', $n($x['en_retard'])];
                $out[] = ['Clients Débiteurs', (string) $x['clients']];
                $out[] = ['Taux de Recouvrement', $p($x['taux'])];
                $out[] = [];
                $out[] = ['Code', 'Client', 'N° Facture', 'Date Vente', 'Échéance', 'Montant Initial', 'Acomptes', 'Solde Dû', 'Retard', 'Statut'];
                foreach ($x['lignes'] as $l) {
                    $out[] = [$l['code'], $l['client'], $l['facture'], $d($l['date_vente']), $d($l['echeance']), $n($l['initial']), $n($l['acomptes']), $n($l['solde']), $l['en_retard'] ? $l['retard'].'j' : '—', $l['statut']];
                }
                break;

            case 'dettes':
                $out[] = ['Total Dettes Fournisseurs', $n($x['total'])];
                $out[] = ['Dettes Urgentes', $n($x['urgentes'])];
                $out[] = ['Fournisseurs Créditeurs', (string) $x['fournisseurs']];
                $out[] = [];
                $out[] = ['Code', 'Fournisseur', 'N° Bon/Facture', 'Date Achat', 'Échéance', 'Montant Total', 'Réglé', 'Solde Restant', 'Statut'];
                foreach ($x['lignes'] as $l) {
                    $out[] = [$l['code'], $l['fournisseur'], $l['reference'], $d($l['date_achat']), $d($l['echeance']), $n($l['total']), $n($l['regle']), $n($l['solde']), $l['statut']];
                }
                break;

            case 'elevage':
                $out[] = ['Effectif Total', (string) $x['effectif_total']];
                $out[] = ['Sujets Malades', (string) $x['malades']];
                $out[] = ['Taux Éclosion Moyen', $p($x['taux_eclosion'])];
                $out[] = ['Cycles en Cours', (string) $x['cycles_en_cours']];
                $out[] = [];
                $out[] = ['Tableau 1 — Recensement & Structure du Cheptel'];
                $out[] = ['Lot / Souche', 'Effectif Total', 'Géniteurs / Matures', 'Jeunes', 'Morts (Période)', 'Dons (Période)', 'Effectif Malade'];
                foreach ($x['recensement'] as $r) {
                    $out[] = [$r['lot'], (string) $r['effectif_total'], (string) $r['matures'], (string) $r['jeunes'], (string) $r['morts'], (string) $r['dons'], (string) $r['malades']];
                }
                $out[] = [];
                $out[] = ['Tableau 2 — Mouvements, Traitements & Ventes'];
                $out[] = ['Lot', 'Qté Vendue', 'Montant Vente', 'Effectif Final', 'Traitement Administré', 'Signes Observés', 'Provende Servie (g/j)'];
                foreach ($x['mouvements'] as $m) {
                    $out[] = [$m['lot'], (string) $m['vendus'], $n($m['montant']), (string) $m['effectif_final'], $m['traitement'], $m['signes'], (string) $m['provende']];
                }
                $out[] = [];
                $out[] = ['Tableau 3 — Couvoir & Suivi d\'Incubation'];
                $out[] = ['Code Lot', 'Mise en Couvoir', 'Éclosion Attendue', 'Œufs Couvés', 'Nés', 'Taux d\'Éclosion', 'Morts au Démarrage', 'Statut'];
                foreach ($x['couvoir'] as $c) {
                    $out[] = [$c['code'], $d($c['mise']), $d($c['eclosion']), (string) $c['couves'], $c['nes'] === null ? '—' : (string) $c['nes'], $p($c['taux']), $c['morts'] === null ? '—' : (string) $c['morts'], $c['statut']];
                }
                break;
        }

        return array_map(fn (array $ligne) => array_map(self::neutraliser(...), $ligne), $out);
    }

    /**
     * Anti injection de formule (tableur) : un texte saisi (client, libelle, motif…) qui commence par `=`, `+`, `@`
     * ou `-` serait evalue par Excel ; une apostrophe le rend inerte. Les nombres (`-5000`, `-3,5 %`) restent intacts.
     */
    private static function neutraliser(string $cellule): string
    {
        if ($cellule === '' || preg_match('/^-?[0-9]+(,[0-9]+)?( %)?$/', $cellule) === 1) {
            return $cellule;
        }

        return in_array($cellule[0], ['=', '+', '-', '@', "\t", "\r"], true) ? "'".$cellule : $cellule;
    }

    public function render()
    {
        $this->verifierLecture();

        // Une valeur trafiquee de l'onglet retombe sur les recettes (la propriete publique, lue par la vue, est remise d'aplomb).
        if (! array_key_exists($this->onglet, self::ONGLETS)) {
            $this->onglet = 'recettes';
        }
        $onglet = $this->onglet;
        [$debut, $fin, $valide] = $this->periode();

        return view('livewire.rapports.rapports', [
            'onglets' => self::ONGLETS,
            'debutPeriode' => $debut,
            'finPeriode' => $fin,
            'periodeValide' => $valide,
            'x' => $this->donnees($onglet, $debut, $fin),
            'peutExporter' => $this->peut('export-rapports'),
            'peutVoirClients' => $this->peut('view-ventes'),
            'aujourdhui' => $this->maintenant(),
        ])->title('Rapports & États');
    }
}
