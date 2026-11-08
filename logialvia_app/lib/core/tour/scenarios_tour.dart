import 'tour_guide.dart';

/// Les scénarios de visite guidée, **repris mot pour mot** des 22 pages du
/// prototype qui définissent `window.TOUR_STEPS`.
///
/// Aucun texte n'est réécrit ni complété : ils décrivent le produit tel que ses
/// auteurs l'expliquent à la Gérante. Deux exceptions, chacune justifiée :
///
/// 1. **`soins-calendrier.html`, étape « Administrer une Dose »** — supprimée.
///    Elle vise `#administrer-dose-form`, un identifiant qui n'existe dans
///    **aucun** des 31 fichiers du prototype. `startTourGuide()` la filtre donc
///    silencieusement côté web. Son texte décrit un stock vétérinaire
///    décrémenté, un reçu imprimable et un blocage sur rupture : trois
///    comportements qu'aucun écran n'implémente. La porter reviendrait à
///    promettre à la Gérante une fonctionnalité inexistante.
/// 2. **`ventes.html`, étape « Mode de Règlement »** — réécrite. Son texte
///    présente « Espèces, Mobile Money, ou Avance » comme trois modes. Depuis
///    l'arbitrage de la Gérante, l'instrument et la condition sont deux
///    sélecteurs distincts (voir `ConditionPaiement`). Recopier la phrase
///    apprendrait à la Gérante quelque chose de faux sur son propre logiciel.
///
/// ## Les 12 visites ajoutées, et pourquoi elles ne sont pas des reprises
///
/// Le prototype ne définit `TOUR_STEPS` que sur **22 pages sur 41**. Douze
/// écrans de l'application n'avaient donc aucune visite : Achats, Clients &
/// Créances, le hub Comptabilité, Grand Livre, Balance, États Financiers,
/// Saisie des Dépenses, Mon Profil, Aide, Contact, plus les deux écrans neufs
/// (Inventaire, Statistiques des Mirages).
///
/// À la demande de la Gérante, ils en ont une désormais. ⚠️ **Ces textes-là
/// sont rédigés, pas transcrits** : aucune page HTML ne les porte. Ils suivent
/// donc la même règle que le reste du logiciel — ils décrivent ce que l'écran
/// fait réellement, jamais ce qu'il pourrait faire.
///
/// Une route absente de cette table n'a pas de visite : `TourGuide.demarrer`
/// affiche alors le message que le prototype prévoit lui-même plutôt que de
/// simuler un tour vide (`common.js` §16).
class ScenariosTour {
  ScenariosTour._();

  static const Map<String, List<EtapeTour>> parRoute = {
  '/dashboard': [
    EtapeTour(
      cible: 'kpi-panel',
      titre: 'Indicateurs Clés (KPI)',
      texte:
          'Ces cartes affichent en un coup d\'œil le chiffre d\'affaires, la '
          'trésorerie, les dépenses, le résultat net, les soldes restant dus, '
          'le stock critique, l\'effectif du cheptel et les cycles de couveuse '
          'en cours.',
    ),
    EtapeTour(
      cible: 'graphique-ca-depenses',
      titre: 'Évolution CA vs Dépenses',
      texte:
          'Ce graphique compare vos recettes et vos dépenses sur les 6 derniers '
          'mois pour repérer les tendances.',
    ),
    EtapeTour(
      cible: 'alertes-critiques',
      titre: 'Alertes Critiques',
      texte:
          'Retrouvez ici les alertes les plus urgentes : stock bas, éclosion '
          'imminente, solde client en retard, anniversaire à venir.',
    ),
    EtapeTour(
      cible: 'cartes-filieres',
      titre: 'Élevage & Couveuse en Temps Réel',
      texte:
          'Suivez l\'effectif et la mortalité de vos Goliaths et Pintades, '
          'ainsi que l\'avancement de vos cycles de couveuse en cours.',
    ),
    EtapeTour(
      cible: 'filtre-periode',
      titre: 'Période & Export',
      texte:
          'Choisissez une période et exportez directement l\'état ou le rapport '
          'de gestion correspondant en PDF.',
    ),
  ],
  '/elevage/dashboard': [
    EtapeTour(
      cible: 'cartes-filieres-elevage',
      titre: 'Vue Consolidée par Filière',
      texte:
          'Cliquez sur une carte pour ouvrir directement la fiche détaillée de '
          'l\'espèce correspondante.',
    ),
    EtapeTour(
      cible: 'comparaison-croissance',
      titre: 'Comparaison de Croissance',
      texte:
          'Comparez le gain moyen quotidien des deux filières sur les 4 '
          'dernières semaines.',
    ),
  ],
  '/elevage/goliaths': [
    EtapeTour(
      cible: 'saisie-journaliere',
      titre: 'Saisie Journalière',
      texte:
          'Renseignez les entrées, sorties par catégorie et le poids du jour — '
          'l\'effectif final, le rationnement et le taux de mortalité se '
          'calculent automatiquement.',
    ),
    EtapeTour(
      cible: 'prophylaxie-du-jour',
      titre: 'Prophylaxie Automatique',
      texte:
          'Les traitements programmés pour ce jour s\'affichent automatiquement '
          'depuis le calendrier — cochez pour valider leur administration.',
    ),
    EtapeTour(
      cible: 'bascule-hebdomadaire',
      titre: 'Bascule Vue Hebdomadaire',
      texte:
          'Basculez vers une vue agrégée par semaine si la saisie quotidienne '
          'détaillée n\'est pas nécessaire ce mois-ci.',
    ),
  ],
  '/elevage/pintades': [
    EtapeTour(
      cible: 'saisie-journaliere',
      titre: 'Saisie Journalière',
      texte:
          'Renseignez les entrées, sorties par catégorie et le poids du jour — '
          'l\'effectif final, le rationnement et le taux de mortalité se '
          'calculent automatiquement.',
    ),
    EtapeTour(
      cible: 'prophylaxie-du-jour',
      titre: 'Prophylaxie Automatique',
      texte:
          'Les traitements programmés pour ce jour s\'affichent automatiquement '
          'depuis le calendrier — cochez pour valider leur administration.',
    ),
    EtapeTour(
      cible: 'bascule-hebdomadaire',
      titre: 'Bascule Vue Hebdomadaire',
      texte:
          'Basculez vers une vue agrégée par semaine si la saisie quotidienne '
          'détaillée n\'est pas nécessaire ce mois-ci.',
    ),
  ],
  '/elevage/lapins': [
    EtapeTour(
      cible: 'saisie-journaliere',
      titre: 'Saisie Journalière',
      texte:
          'Renseignez les entrées, sorties par catégorie et le poids du jour — '
          'l\'effectif final, le rationnement et le taux de mortalité se '
          'calculent automatiquement.',
    ),
    EtapeTour(
      cible: 'prophylaxie-du-jour',
      titre: 'Prophylaxie Automatique',
      texte:
          'Les traitements programmés pour ce jour s\'affichent automatiquement '
          'depuis le calendrier — cochez pour valider leur administration.',
    ),
    EtapeTour(
      cible: 'bascule-hebdomadaire',
      titre: 'Bascule Vue Hebdomadaire',
      texte:
          'Basculez vers une vue agrégée par semaine si la saisie quotidienne '
          'détaillée n\'est pas nécessaire ce mois-ci.',
    ),
  ],
  '/elevage/poissons-chats': [
    EtapeTour(
      cible: 'saisie-journaliere',
      titre: 'Saisie Journalière',
      texte:
          'Renseignez les entrées, sorties par catégorie et le poids du jour — '
          'l\'effectif final et le taux de mortalité se calculent '
          'automatiquement. Le rationnement reste à définir (aucune référence '
          'disponible pour cette espèce).',
    ),
    EtapeTour(
      cible: 'prophylaxie-du-jour',
      titre: 'Prophylaxie Automatique',
      texte:
          'Les traitements programmés pour ce jour s\'affichent automatiquement '
          'depuis le calendrier — cochez pour valider leur administration.',
    ),
    EtapeTour(
      cible: 'bascule-hebdomadaire',
      titre: 'Bascule Vue Hebdomadaire',
      texte:
          'Basculez vers une vue agrégée par semaine si la saisie quotidienne '
          'détaillée n\'est pas nécessaire ce mois-ci.',
    ),
  ],
  // ⚠️ Visites REDIGEES, non transcrites : les fiches Escargots et Bovins ont
  // ete ajoutees apres le prototype (DV-16, DV-17), aucune page HTML ne les
  // porte. Elles decrivent ce que l'ecran fait reellement.
  '/elevage/escargots': [
    EtapeTour(
      cible: 'saisie-journaliere',
      titre: 'Saisie Journalière',
      texte:
          'Renseignez les achats, les éclosions et les morts par catégorie '
          '(Naissain, Marchand, Reproducteur) — l\'effectif final, la provende '
          'et le taux de mortalité se calculent automatiquement.',
    ),
    EtapeTour(
      cible: 'prophylaxie-du-jour',
      titre: 'Hygiène et soins du jour',
      texte:
          'Les soins d\'hygiène programmés pour ce jour (nettoyage des bacs, '
          'désinfection, calcium) s\'affichent depuis le calendrier — cochez '
          'pour valider leur réalisation.',
    ),
    EtapeTour(
      cible: 'bascule-hebdomadaire',
      titre: 'Bascule Vue Hebdomadaire',
      texte:
          'Basculez vers une vue agrégée par semaine si la saisie quotidienne '
          'détaillée n\'est pas nécessaire ce mois-ci.',
    ),
  ],
  '/elevage/bovins': [
    EtapeTour(
      cible: 'saisie-journaliere',
      titre: 'Saisie Journalière',
      texte:
          'Renseignez les achats, les vêlages, les morts par catégorie (Veau, '
          'Embouche, Reproducteur) et la pesée totale du lot : avec la pesée, '
          'la provende se calcule en pourcentage du poids vif ; sans pesée, '
          'elle retombe sur la ration indicative par tête.',
    ),
    EtapeTour(
      cible: 'prophylaxie-du-jour',
      titre: 'Prophylaxie Automatique',
      texte:
          'Les vaccins, déparasitages et détiquages programmés pour ce jour '
          's\'affichent depuis le calendrier, avec leur dose — la notice du '
          'produit prévaut. Cochez pour valider leur administration.',
    ),
    EtapeTour(
      cible: 'bascule-hebdomadaire',
      titre: 'Bascule Vue Hebdomadaire',
      texte:
          'Basculez vers une vue agrégée par semaine si la saisie quotidienne '
          'détaillée n\'est pas nécessaire ce mois-ci.',
    ),
  ],
  '/elevage/poulets-pondeuses': [
    EtapeTour(
      cible: 'onglets-poulets-pondeuses',
      titre: 'Onglets Poulets / Pondeuses',
      texte:
          'Basculez entre le suivi de croissance (Poulets) et le suivi de '
          'production d\'œufs (Pondeuses) — deux mécaniques distinctes, chacune '
          'avec sa propre saisie journalière.',
    ),
    EtapeTour(
      cible: 'oeufs-pondus',
      titre: 'Workflow de Ponte',
      texte:
          'Le taux de ponte et le nombre de plateaux se calculent '
          'automatiquement à partir des œufs récoltés et cassés.',
    ),
  ],
  '/elevage/couveuse': [
    EtapeTour(
      cible: 'bouton-declarer-cycle',
      titre: 'Déclarer un Cycle',
      texte:
          'Cliquez ici pour démarrer un nouveau cycle de couveuse : choisissez '
          'l\'espèce, la date de chargement et le nombre d\'œufs — la date '
          'd\'éclosion prévisionnelle se calcule automatiquement.',
    ),
    EtapeTour(
      cible: 'tableau-cycles',
      titre: 'Cycles en Cours et Terminés',
      texte:
          'Chaque ligne représente un cycle. Cliquez dessus pour voir le détail '
          'complet, ou utilisez le bouton \\"Enregistrer Éclosion\\" une fois '
          'le résultat connu.',
    ),
  ],
  '/elevage/soins': [
    EtapeTour(
      cible: 'onglet-suivi-infirmerie',
      titre: 'Suivi Sanitaire',
      texte:
          'Distinct du calendrier de vaccination — ici vous suivez les sujets '
          'isolés jusqu\'à leur guérison ou leur décès.',
    ),
  ],
  '/ventes': [
    EtapeTour(
      cible: 'grille-produits',
      titre: 'Sélectionner un Produit',
      texte:
          'Touchez un produit — avicole ou commerce annexe — pour l\'ajouter au '
          'panier. Une confirmation de quantité et de montant s\'ouvrira '
          'toujours.',
    ),
    EtapeTour(
      cible: 'mode-reglement',
      titre: 'Mode et Condition de Règlement',
      texte:
          'Choisissez d\'abord l\'instrument — Espèces ou Mobile Money — puis '
          'la condition : Comptant, ou Avance si le client règle une partie '
          'seulement, auquel cas le solde restant dû sera suivi '
          'automatiquement.',
    ),
    EtapeTour(
      cible: 'filtres-historique',
      titre: 'Filtres',
      texte:
          'Filtrez par statut, mode de paiement ou client pour retrouver '
          'rapidement une transaction.',
    ),
    EtapeTour(
      cible: 'tableau-historique',
      titre: 'Historique des Ventes',
      texte:
          'Consultez le détail de chaque vente ou annulez-la avec un motif '
          'obligatoire — les ventes annulées sont exclues du chiffre '
          'd\'affaires.',
    ),
  ],
  '/catalogue': [
    EtapeTour(
      cible: 'onglet-seuils',
      titre: 'Seuils d\\\'Alerte',
      texte:
          'Ajustez ici le seuil déclenchant l\'alerte rouge sur le Point de '
          'Vente et le Tableau de Bord, produit par produit.',
    ),
    EtapeTour(
      cible: 'tableau-catalogue',
      titre: 'Fiche Produit Maître',
      texte:
          'Ce catalogue centralise le SKU, la désignation et le tarif — Gestion '
          'Stocks se concentre sur les mouvements de quantité.',
    ),
  ],
  '/stocks': [
    EtapeTour(
      cible: 'bouton-fabrication',
      titre: 'Fabrication de Provende',
      texte:
          'Toute utilisation d\'intrants pour fabriquer de la provende passe '
          'par ici — les 5 stocks sont décrémentés en une seule opération, '
          'jamais sortis séparément.',
    ),
    EtapeTour(
      cible: 'tableau-stocks',
      titre: 'Tableau des Stocks',
      texte:
          'Consultez le niveau de chaque article, filtrable par catégorie. Une '
          'ligne en rouge signale un stock sous son seuil d\'alerte.',
    ),
  ],
  '/fournisseurs': [
    EtapeTour(
      cible: 'onglet-dettes',
      titre: 'Dettes Fournisseurs',
      texte:
          'Suivez ici les achats réglés partiellement à crédit — le solde dû se '
          'règle en un clic depuis cet onglet.',
    ),
  ],
  '/comptabilite/journal': [
    EtapeTour(
      cible: 'tableau-journal',
      titre: 'Écritures Automatiques',
      texte:
          'Chaque vente ou achat enregistré ailleurs dans l\'application génère '
          'automatiquement son écriture ici — vous n\'avez rien à ressaisir.',
    ),
    EtapeTour(
      cible: 'bouton-nouvelle-ecriture',
      titre: 'Saisie Manuelle',
      texte:
          'Pour une opération diverse non couverte automatiquement, le même '
          'montant s\'applique au Débit et au Crédit — l\'équilibre est '
          'garanti.',
    ),
  ],
  '/comptabilite/plan': [
    EtapeTour(
      cible: 'tableau-plan-comptable',
      titre: 'Plan Comptable SYSCOHADA',
      texte:
          'Ces comptes alimentent automatiquement le Journal Comptable à chaque '
          'vente, achat ou dépense enregistrée dans l\'application.',
    ),
  ],
  '/comptabilite/analytique': [
    EtapeTour(
      cible: 'tableau-analytique',
      titre: 'Marges par Centre',
      texte:
          'Chaque filière ou activité est suivie indépendamment — utile pour '
          'identifier ce qui est réellement rentable, pas juste le chiffre '
          'd\'affaires global.',
    ),
  ],
  '/comptabilite/cloture': [
    EtapeTour(
      cible: 'timeline-exercices',
      titre: 'Timeline des Exercices',
      texte:
          'Visualisez en un coup d\'œil quel exercice est actif '
          '(lecture/écriture) et lesquels sont clôturés (lecture seule).',
    ),
  ],
  '/comptabilite/bilan': [
    EtapeTour(
      cible: 'bandeau-equilibre',
      titre: 'Équilibre Comptable',
      texte:
          'Le bilan vérifie automatiquement que le Total Actif égale le Total '
          'Passif — toute écriture déséquilibrée serait immédiatement visible '
          'ici.',
    ),
  ],
  '/rapports': [
    EtapeTour(
      cible: 'onglets-rapports',
      titre: '6 États Disponibles',
      texte:
          'Chaque onglet correspond à un état exportable en PDF, filtré sur la '
          'période choisie en haut de page.',
    ),
  ],
  '/parametres/elevage': [
    EtapeTour(
      cible: 'tableau-rationnement',
      titre: 'Barème de Rationnement',
      texte:
          'Ces valeurs sont utilisées automatiquement dans le calcul de '
          'provende de chaque fiche journalière — modifiez-les ici plutôt que '
          'dans chaque fiche individuellement.',
    ),
  ],
  // ---------------------------------------------------------------------
  // Visites REDIGEES — le prototype n'en definit aucune sur ces ecrans.
  // ---------------------------------------------------------------------
  '/achats': [
    EtapeTour(
      cible: 'achats-tableau',
      titre: 'Commandes et Réceptions',
      texte:
          'Chaque commande suit son cycle jusqu\'à la réception. C\'est la '
          'réception qui fait entrer la marchandise en stock et qui recalcule '
          'le prix moyen pondéré de l\'article — pas la commande.',
    ),
  ],
  '/clients': [
    EtapeTour(
      cible: 'clients-tableau',
      titre: 'Créances et Relances',
      texte:
          'Une créance n\'est « en retard » que si une échéance a été convenue. '
          'Sans échéance renseignée, elle figure ici avec son solde dû mais '
          'n\'est jamais déclarée en retard — et le courrier s\'intitule alors '
          '« Rappel de Solde » plutôt que « Lettre de Relance ».',
    ),
  ],
  '/comptabilite': [
    EtapeTour(
      cible: 'compta-hub',
      titre: 'Exercice Comptable',
      texte:
          'Tous les écrans comptables lisent l\'exercice sélectionné ici. Un '
          'exercice clôturé se consulte encore, mais n\'accepte plus aucune '
          'écriture : c\'est ce qui garantit que les états déjà signés ne '
          'changent plus.',
    ),
  ],
  '/comptabilite/grand-livre': [
    EtapeTour(
      cible: 'grand-livre-tableau',
      titre: 'Solde Progressif',
      texte:
          'Chaque ligne porte le solde du compte après elle. C\'est ce qui '
          'permet de retrouver à quelle écriture un compte a basculé — un '
          'total en pied de page ne le dirait pas.',
    ),
  ],
  '/comptabilite/balance': [
    EtapeTour(
      cible: 'balance-tableau',
      titre: 'Balance à Six Colonnes',
      texte:
          'Reports, mouvements de la période et soldes de clôture, en débit et '
          'en crédit. Les deux totaux de chaque paire doivent être égaux : '
          'c\'est le contrôle de la partie double, et il est affiché plutôt '
          'que supposé.',
    ),
  ],
  '/comptabilite/etats-financiers': [
    EtapeTour(
      cible: 'etats-financiers-corps',
      titre: 'États SYSCOHADA',
      texte:
          'Bilan, compte de résultat, TAFIRE et notes annexes sont produits à '
          'partir des seules écritures enregistrées. Aucun montant n\'y est '
          'saisi à la main : corriger un état se fait en corrigeant l\'écriture '
          'qui le porte.',
    ),
  ],
  '/depenses': [
    EtapeTour(
      cible: 'depenses-formulaire',
      titre: 'Une Dépense, Deux Lignes',
      texte:
          'Toute dépense génère une écriture équilibrée : la charge au débit, '
          'la trésorerie au crédit. L\'axe analytique, facultatif, indique à '
          'quelle filière imputer la charge — sans lui, elle reste dans les '
          'charges non affectées.',
    ),
  ],
  '/inventaire': [
    EtapeTour(
      cible: 'inventaire-filtres',
      titre: 'Un Inventaire est Daté',
      texte:
          'Journalier, hebdomadaire, mensuel ou sur une plage libre : les '
          'stocks sont reconstitués à la date de clôture choisie, à partir des '
          'mouvements réellement enregistrés.',
    ),
    EtapeTour(
      cible: 'inventaire-kpi',
      titre: 'Valorisé au Coût, Jamais au Prix de Vente',
      texte:
          'Les intrants sont valorisés au prix moyen pondéré, les produits '
          'finis à leur coût de revient. Un animal encore en enclos n\'a rien '
          'rapporté : le compter à son prix de vente gonflerait l\'actif d\'une '
          'marge non réalisée.',
    ),
    EtapeTour(
      cible: 'inventaire-intrants',
      titre: 'Stock Initial, Entrées, Sorties, Stock Final',
      texte:
          'Ces quatre colonnes doivent se boucler. Un article dont les '
          'mouvements n\'expliquent pas le stock est signalé en haut de page : '
          'un inventaire qui ne se justifie pas ne se signe pas.',
    ),
    EtapeTour(
      cible: 'inventaire-effectifs',
      titre: 'Animaux Comptés, Non Valorisés',
      texte:
          'Leur coût dépend de la provende consommée depuis la mise en bande, '
          'que le logiciel ne cumule pas par lot. Les compter dit la vérité ; '
          'leur coller un prix serait une estimation déguisée en chiffre.',
    ),
    EtapeTour(
      cible: 'inventaire-export',
      titre: 'État Imprimable',
      texte:
          'Le PDF reprend les trois tableaux, la base de valorisation et ce '
          'que le total exclut — un état signé doit porter ses propres '
          'réserves.',
    ),
  ],
  '/elevage/mirages': [
    EtapeTour(
      cible: 'mirages-kpi',
      titre: 'Trois Causes, Trois Chiffres',
      texte:
          'Un œuf clair au J+7 n\'a jamais été fécondé : c\'est le troupeau '
          'reproducteur qui est en cause. Un œuf gâté au J+14 a démarré puis '
          's\'est arrêté : c\'est la conduite de la machine. Les confondre dans '
          'un taux unique perdrait l\'information au moment où elle sert.',
    ),
    EtapeTour(
      cible: 'mirages-tableau',
      titre: 'Lot par Lot',
      texte:
          'Les taux ne sont calculés que sur les lots réellement mirés. Un '
          'mirage oublié apparaît en clair plutôt que d\'être compté zéro : '
          'sinon la négligence ressemblerait à un bon résultat.',
    ),
  ],
  '/profil': [
    EtapeTour(
      cible: 'profil-identite',
      titre: 'Votre Compte',
      texte:
          'Le mot de passe se change ici. Il n\'est jamais stocké en clair : '
          'seule son empreinte est conservée, avec un sel propre à votre '
          'compte.',
    ),
  ],
  '/aide': [
    EtapeTour(
      cible: 'aide-sommaire',
      titre: 'Aide en Ligne',
      texte:
          'Chaque module est décrit avec ses règles de gestion. Cette aide est '
          'embarquée : elle reste consultable sans connexion, comme le reste '
          'du logiciel.',
    ),
  ],
  '/contact': [
    EtapeTour(
      cible: 'contact-formulaire',
      titre: 'Contacter l\'Éditeur',
      texte:
          'Le message est enregistré et copié dans le presse-papiers, prêt à '
          'être envoyé. LogiALVIA fonctionne hors ligne : il ne peut pas '
          'l\'expédier lui-même, et prétendre le contraire serait mentir sur '
          'un accusé de réception.',
    ),
  ],

  '/parametres/generaux': [
    EtapeTour(
      cible: 'onglet-modules-actifs',
      titre: 'Modules Actifs',
      texte:
          'Activez ou désactivez chaque filière secondaire — l\'effet est '
          'immédiat sur le menu latéral et le panneau d\'accès rapide.',
    ),
  ],
  };

  static List<EtapeTour> pour(String route) => parRoute[route] ?? const [];
}
