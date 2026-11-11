import '../../../administration/domain/entities/compte_utilisateur.dart';
import 'modele_manuel.dart';

/// Le contenu du manuel d'utilisation.
///
/// ## Règle d'écriture
///
/// Ce manuel décrit ce que le logiciel **fait**, jamais ce qu'il devrait faire.
/// Là où une fonction est absente ou volontairement différente du prototype,
/// c'est écrit — un manuel qui promet plus que le logiciel est pire que pas de
/// manuel : il fait perdre du temps et il fait douter de tout le reste.
///
/// Style : phrases courtes, présent de l'indicatif, « vous ». Les éléments de
/// l'interface sont nommés exactement comme à l'écran.
class ContenuManuel {
  ContenuManuel._();

  static const String version = '1.0.0';

  /// L'éditeur, lu depuis les constantes de l'application.
  ///
  /// Recopier ces coordonnées ici les ferait diverger de l'écran « Contactez
  /// l'Éditeur » à la première correction. Une seule source, deux lecteurs.
  static const EditeurManuel editeur = EditeurManuel(
    nom: Editeur.contact,
    qualification: Editeur.qualification,
    telephones: Editeur.telephones,
    emails: Editeur.emails,
    societe: Editeur.societe,
    roleSociete: Editeur.roleSociete,
    programme: Editeur.programme,
  );

  static const ManuelUtilisation manuel = ManuelUtilisation(
    version: version,
    editeur: editeur,
    destinataire: 'ALLMANY ET COMPAGNIE',
    avantPropos: [
      'LogiALVIA gère l\'exploitation d\'ALLMANY ET COMPAGNIE : l\'élevage '
          '(goliaths, pintades, lapins, escargots, ovins, poissons-chats, poulets et pondeuses), '
          'la couveuse, les ventes, les achats, les stocks et la comptabilité.',
      'Le logiciel fonctionne **hors ligne**. Toutes vos données vivent dans un '
          'seul fichier, sur cet ordinateur. Aucune connexion n\'est nécessaire '
          'pour travailler, et rien ne part sur Internet.',
      'Ce manuel suit l\'ordre du menu, à gauche de l\'écran. Chaque section '
          'indique où trouver l\'écran, qui y a accès, à quoi il sert, et les '
          'gestes dans l\'ordre.',
      'Le logiciel a été réalisé par le cabinet **FAGUEZ SARL**, qui '
          'accompagne les PME dans le cadre du **Projet d\'Appui à '
          'l\'Entrepreneuriat au Bénin (PAEB)**. L\'assistance passe par lui : '
          'ses coordonnées figurent à l\'annexe F.',
      'Trois comptes existent : l\'Administratrice voit tout, l\'Agent de Vente '
          'travaille au point de vente et sur les clients, l\'Agent d\'Élevage '
          'sur les fiches et les soins. Un écran auquel vous n\'avez pas droit '
          'n\'apparaît pas dans votre menu.',
    ],
    chapitres: [
      _priseEnMain,
      _elevage,
      _commercial,
      _approvisionnement,
      _comptabilite,
      _rapports,
      _parametres,
    ],
    annexes: _annexes,
  );

  // =============================================================== ANNEXES

  static const List<AnnexeManuel> _annexes = [
    AnnexeManuel(
      lettre: 'A',
      titre: 'Qui peut faire quoi',
      introduction:
          'Trois rôles, et un menu qui s\'adapte. Un écran absent de votre '
          'barre latérale n\'est pas une panne : votre compte n\'y a pas droit.',
      tableaux: [
        TableauManuel(
          titre: 'Les écrans par rôle',
          colonnes: [
            ColonneManuel(
              'Administratrice',
              'Tous les écrans, sans exception. Seule elle accède à la '
                  'comptabilité, aux achats, aux paramètres et à la clôture '
                  'd\'exercice — et seule elle peut déclôturer.',
            ),
            ColonneManuel(
              'Agent de Vente',
              'Tableau de Bord, Ventes, Clients et Créances, Inventaire, '
                  'Facturation MeCeF, Mon Profil, Aide & À Propos, Contactez '
                  'l\'Éditeur.',
            ),
            ColonneManuel(
              'Agent d\'Élevage',
              'Tableau de Bord, Dashboard Élevage, Cycle Couveuse, '
                  'Statistiques Mirages, les cinq fiches d\'élevage, Soins & '
                  'Calendrier, Paramètres Élevage, et les trois écrans du '
                  'compte.',
            ),
          ],
        ),
      ],
      encadres: [
        EncadreManuel.information(
          'L\'Inventaire est **visible par les deux** rôles administratifs. Il '
          'expose les coûts de revient et la valorisation du stock ; la '
          'question a été posée, et la réponse est de les montrer aussi au '
          'point de vente.',
        ),
      ],
    ),
    AnnexeManuel(
      lettre: 'B',
      titre: 'Que faire si…',
      introduction:
          'Les situations qui arrêtent le travail, et ce qu\'elles veulent '
          'réellement dire. La plupart ne sont pas des pannes.',
      tableaux: [
        TableauManuel(
          titre: 'Dépannage par symptôme',
          colonnes: [
            ColonneManuel(
              'Mon compte est verrouillé',
              'Cinq mots de passe faux de suite. Le verrou dure quinze '
                  'minutes. C\'est ce qui empêche d\'essayer les mots de passe '
                  'un par un.',
            ),
            ColonneManuel(
              'Un écran a disparu du menu',
              'Soit votre rôle ne vous y donne pas droit (annexe A), soit le '
                  'module est désactivé dans Paramètres Général › Modules '
                  'Actifs.',
            ),
            ColonneManuel(
              'La vente refuse de s\'enregistrer',
              'Le panier est vide, le stock est insuffisant, ou une vente à '
                  'crédit n\'a pas de montant reçu. Le message dit lequel.',
            ),
            ColonneManuel(
              'Le module MeCeF ne s\'active pas',
              'L\'IFU et le RCCM de l\'entreprise doivent être renseignés '
                  'd\'abord, dans Données de l\'Entreprise.',
            ),
            ColonneManuel(
              'Ma facture reste « À transmettre »',
              'La transmission e-MECeF n\'est pas configurée, ou elle a '
                  'échoué. Le document imprimé le dit en toutes lettres — il '
                  'ne vaut pas facture normalisée.',
            ),
            ColonneManuel(
              'Un effectif me paraît faux',
              'Il ne se saisit pas : il se déduit de la veille et des '
                  'mouvements du jour. Corrigez le mouvement, jamais '
                  'l\'effectif.',
            ),
            ColonneManuel(
              'Le total d\'un état ne tombe pas juste',
              'Vérifiez d\'abord le bandeau rouge de l\'Inventaire : il liste '
                  'les articles dont les mouvements n\'expliquent pas le '
                  'stock.',
            ),
            ColonneManuel(
              'Le logiciel ne trouve plus mes données',
              'Après une mise à jour ayant changé le nom du dossier, la base '
                  'précédente est reprise automatiquement au démarrage. Si '
                  'l\'écran reste vide, appelez l\'éditeur avant toute autre '
                  'manipulation.',
            ),
          ],
        ),
      ],
      encadres: [
        EncadreManuel.astuce(
          'Avant d\'appeler : notez l\'écran, le geste exact et le message '
          'affiché. L\'écran Contactez l\'Éditeur enregistre tout cela et le '
          'copie dans le presse-papiers.',
        ),
      ],
    ),
    AnnexeManuel(
      lettre: 'C',
      titre: 'Glossaire',
      introduction:
          'Les termes employés à l\'écran, dans le sens que leur donne '
          'LogiALVIA.',
      tableaux: [
        TableauManuel(
          titre: 'Les mots du logiciel',
          colonnes: [
            ColonneManuel(
              'Bande',
              'Un groupe d\'animaux mis en place le même jour. Sa date de '
                  'mise en bande est le jour 1 du cycle, et date toutes les '
                  'échéances de prophylaxie.',
            ),
            ColonneManuel(
              'Mirage',
              'Examen des œufs par transparence. Le premier, à J+7, retire '
                  'les œufs clairs — jamais fécondés. Le second, à J+14, les '
                  'œufs gâtés — embryon arrêté.',
            ),
            ColonneManuel(
              'TER',
              'Taux d\'Éclosion Réel : poussins éclos rapportés aux œufs '
                  '**retenus** après les deux mirages. À ne pas confondre '
                  'avec le taux brut, rapporté aux œufs chargés.',
            ),
            ColonneManuel(
              'Rémanence',
              'Délai d\'attente après un traitement, pendant lequel les '
                  'produits de l\'animal ne se commercialisent pas.',
            ),
            ColonneManuel(
              'PMP',
              'Prix Moyen Pondéré. Base de valorisation des intrants, '
                  'recalculée à chaque réception.',
            ),
            ColonneManuel(
              'Coût de revient',
              'Ce qu\'un produit fini a coûté. Il valorise le stock — jamais '
                  'le prix de vente : un animal en enclos n\'a rien rapporté.',
            ),
            ColonneManuel(
              'Avance',
              'Une **condition de paiement**, pas un moyen. Le client règle '
                  'une partie ; le reste devient une créance.',
            ),
            ColonneManuel(
              'Contrepassation',
              'Annuler une écriture par une écriture inverse. Une pièce '
                  'comptable ne se supprime pas.',
            ),
            ColonneManuel(
              'Avoir (FA)',
              'Facture qui corrige ou annule une facture de vente. Elle ne '
                  'modifie pas l\'originale : elle la contrepasse.',
            ),
            ColonneManuel(
              'MeCeF / e-MECeF',
              'Machine Électronique Certifiée Fiscalement, et le service de '
                  'la DGI qui normalise les factures.',
            ),
            ColonneManuel(
              'IFU',
              'Identifiant Fiscal Unique de l\'entreprise. Sans lui, aucune '
                  'facture normalisée.',
            ),
            ColonneManuel(
              'SYSCOHADA',
              'Le référentiel comptable en vigueur au Bénin. Il fixe le plan '
                  'de comptes et la forme des états financiers.',
            ),
          ],
        ),
      ],
    ),
    AnnexeManuel(
      lettre: 'D',
      titre: 'Les gestes à ne jamais faire',
      introduction:
          'Six actions dont on ne revient pas, ou difficilement. Les '
          'connaître vaut mieux que les découvrir.',
      puces: [
        'Réinitialiser les données de test sur une exploitation en service. '
            'Tout est effacé. Le verrou du mode « Données de Test » existe '
            'pour cela.',
        'Restaurer une sauvegarde sans regarder sa date. Tout ce qui a été '
            'saisi depuis est perdu — les ventes du jour comprises.',
        'Clôturer un exercice sans avoir vérifié la Balance Générale et les '
            'États Financiers.',
        'Prêter son mot de passe. Chaque geste est attribué au compte qui '
            'l\'a fait ; le prêter, c\'est endosser ce que l\'autre fera.',
        'Copier le fichier de base pendant que le logiciel est ouvert. '
            'Passez par Générer une sauvegarde.',
        'Remettre à un client une facture portant « FACTURE NON NORMALISÉE » '
            'en la présentant comme une facture en règle.',
      ],
      encadres: [
        EncadreManuel.astuce(
          'Une sauvegarde prend quelques secondes et se fait depuis '
          'Paramètres Général › Sauvegardes. Faites-en une avant toute '
          'opération de cette liste.',
        ),
      ],
    ),
    AnnexeManuel(
      lettre: 'E',
      titre: 'Les comptes livrés',
      introduction:
          'Le logiciel est livré avec un seul compte, celui de '
          'l\'administratrice. Les autres se créent depuis Paramètres Général '
          '› Gestion Utilisateurs.',
      paragraphes: [
        'L\'identifiant du compte initial est **admin**. Son mot de passe est '
            'suggéré par le formulaire de connexion lui-même, dans le champ '
            'MOT DE PASSE : il est donc visible de quiconque ouvre le '
            'logiciel, et il apparaît sur la capture de la section 1.1 de ce '
            'manuel. Ce n\'est pas un secret — c\'est une valeur de mise en '
            'service, et elle n\'a de sens que jusqu\'à ce que vous la '
            'changiez.',
      ],
      encadres: [
        EncadreManuel.alerte(
          'Changez-le **le jour de la mise en service**, depuis Mon Profil. '
          'Tant qu\'il est inchangé, il est connu de tous ceux qui ont '
          'participé au déploiement — et de quiconque a ouvert le formulaire '
          'de connexion une fois.',
        ),
        EncadreManuel.information(
          'Un compte ne se supprime pas : il se désactive. Les saisies qu\'il '
          'a faites gardent son nom, et c\'est ce qui rend les journaux '
          'utilisables.',
        ),
      ],
    ),
    AnnexeManuel(
      lettre: 'F',
      titre: 'Joindre l\'éditeur',
      introduction:
          'Pour une anomalie, une évolution, ou une question que ce manuel '
          'ne tranche pas. LogiALVIA a été réalisé par le cabinet FAGUEZ '
          'SARL, qui accompagne les PME dans le cadre du Projet d\'Appui à '
          'l\'Entrepreneuriat au Bénin.',
      tableaux: [
        TableauManuel(
          titre: 'Coordonnées',
          colonnes: [
            ColonneManuel('Éditeur', Editeur.contact),
            ColonneManuel('Qualification', Editeur.qualification),
            ColonneManuel(
              'Cabinet',
              '${Editeur.societe} — ${Editeur.roleSociete}',
            ),
            ColonneManuel('Programme', Editeur.programme),
            ColonneManuel('Téléphone', Editeur.telephones),
            ColonneManuel('Courriel', Editeur.emails),
          ],
        ),
      ],
      paragraphes: [
        'L\'écran **Contactez l\'Éditeur**, dans le menu de votre compte, '
            'enregistre votre message avec sa date et le copie dans le '
            'presse-papiers. LogiALVIA fonctionne hors ligne : il ne peut pas '
            'l\'expédier lui-même, mais il vous évite de tout retaper.',
      ],
      encadres: [
        EncadreManuel.astuce(
          'Un signalement utile tient en trois lignes : l\'écran, le geste '
          'exact, et le message affiché mot pour mot.',
        ),
      ],
    ),
  ];

  // ====================================================== 0. PRISE EN MAIN

  static const ChapitreManuel _priseEnMain = ChapitreManuel(
    titre: 'Prise en main',
    introduction:
        'Se connecter, comprendre l\'écran, se déplacer dedans. Une dizaine de '
        'minutes qui évitent de chercher pendant des semaines.',
    sections: [
      SectionManuel(
        titre: 'Connexion',
        chemin: 'Au lancement du logiciel',
        role: 'Tous',
        capture: '00-connexion',
        aQuoiCaSert:
            'C\'est le premier écran. Il identifie qui travaille : chaque '
            'saisie porte ensuite le nom de son auteur, et le menu n\'affiche '
            'que les écrans auxquels ce compte a droit.',
        etapes: [
          EtapeManuel(
            'Saisissez votre identifiant',
            'Celui que l\'administratrice vous a remis. Ce n\'est pas une '
                'adresse e-mail.',
          ),
          EtapeManuel(
            'Saisissez votre mot de passe',
            'L\'icône en bout de champ l\'affiche en clair, le temps de '
                'vérifier une frappe.',
          ),
          EtapeManuel(
            'Cliquez sur Se Connecter',
            'Le Tableau de Bord s\'ouvre, et les rappels du jour avec lui.',
          ),
        ],
        encadres: [
          EncadreManuel.alerte(
            'Cinq échecs de suite verrouillent le compte pendant quinze '
            'minutes. Ce n\'est pas une panne : c\'est ce qui empêche d\'essayer '
            'les mots de passe un par un. Attendez, ou faites réinitialiser le '
            'vôtre par l\'administratrice.',
          ),
          EncadreManuel.attention(
            'La case « Se souvenir de moi » mémorise votre **identifiant**, '
            'jamais votre session. Le mot de passe reste demandé à chaque '
            'lancement : le poste est partagé.',
          ),
        ],
        aRetenir: [
          'Un mot de passe ne se prête pas : les journaux attribuent chaque '
              'geste au compte qui l\'a fait.',
          'Le logiciel fonctionne hors ligne. Aucune connexion Internet n\'est '
              'nécessaire pour se connecter.',
        ],
      ),
      SectionManuel(
        titre: 'Tableau de Bord',
        chemin: 'PILOTAGE › Tableau de Bord',
        role: 'Tous',
        capture: '01-tableau-de-bord',
        reperes: [
          ReperManuel(
            ancre: 'filtre-periode',
            legende: 'la période, qui recalcule tout',
          ),
          ReperManuel(
            ancre: 'kpi-panel',
            legende: 'les indicateurs de la période',
            zone: true,
          ),
        ],
        aQuoiCaSert:
            'Il rassemble en une page les chiffres de la période : chiffre '
            'd\'affaires, dépenses, résultat, soldes restant dus, stock '
            'critique, effectif du cheptel et cycles de couveuse en cours. '
            'Les graphiques montrent l\'évolution, les panneaux du bas les '
            'dernières ventes et les alertes.',
        etapes: [
          EtapeManuel(
            'Choisissez la période',
            'Les champs de dates en haut recalculent tous les indicateurs.',
          ),
          EtapeManuel(
            'Lisez les cartes du haut',
            'Chaque carte porte son détail sous la valeur : il dit sur quoi '
                'elle porte et ce qu\'elle exclut.',
          ),
          EtapeManuel(
            'Ouvrez une alerte',
            'Les alertes du bandeau mènent directement à l\'écran concerné.',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'Deux rappels s\'ouvrent d\'eux-mêmes à l\'arrivée sur cet écran : '
            '**Prophylaxie du Jour**, quand un soin est dû ou en retard, et '
            '**Alertes Critiques de Stock**, quand un article est passé sous '
            'son seuil. Ils ne se déclenchent que s\'il y a réellement quelque '
            'chose à faire.',
          ),
          EncadreManuel.attention(
            'Le rappel de prophylaxie signale aussi les **échéances du '
            'calendrier jamais planifiées** — celles qui ne figurent dans '
            'aucun registre, et qui passaient donc inaperçues. Le bouton '
            '« Planifier » mène à la fiche : le type d\'action s\'y choisit, le '
            'calendrier ne le porte pas.',
          ),
          EncadreManuel.astuce(
            '« Plus tard » écarte un rappel jusqu\'à la prochaine ouverture du '
            'logiciel. Rien n\'est effacé : il revient tant que le soin n\'est '
            'pas administré ou le stock pas réapprovisionné.',
          ),
          EncadreManuel.information(
            'Un indicateur affiche « — » quand sa donnée n\'existe pas encore, '
            'et « 0 » quand la valeur est réellement nulle. Les deux ne disent '
            'pas la même chose.',
          ),
        ],
        aRetenir: [
          'Les chiffres viennent des saisies : rien n\'est estimé ni arrondi.',
          'Le chiffre d\'affaires exclut les ventes annulées.',
        ],
      ),
      SectionManuel(
        titre: 'Se déplacer dans le logiciel',
        chemin: 'Partout',
        role: 'Tous',
        capture: '19-comptabilite-hub',
        reperes: [
          ReperManuel(
            ancre: 'compta-hub',
            legende: 'les tuiles, seul chemin vers quatre écrans',
            zone: true,
          ),
        ],
        aQuoiCaSert:
            'Trois zones, toujours les mêmes : la **barre latérale** à gauche '
            'groupe les écrans par métier ; la **barre du haut** porte la '
            'cloche des notifications et votre compte ; le reste est l\'écran '
            'lui-même.',
        etapes: [
          EtapeManuel(
            'Ouvrez un groupe de la barre latérale',
            'PILOTAGE, ÉLEVAGE & COUVEUSE, VENTES & CLIENTS, ACHATS & '
                'FOURNISSEURS, STOCKS & CATALOGUE, COMPTABILITÉ, PARAMÈTRES, '
                'ÉDITIONS.',
          ),
          EtapeManuel(
            'Cliquez sur l\'écran voulu',
            'Il remplace la zone centrale ; la barre latérale ne bouge pas.',
          ),
          EtapeManuel(
            'Servez-vous de la cloche',
            'Elle porte le nombre d\'alertes en cours. Cliquer sur une alerte '
                'ouvre l\'écran qui permet de la traiter.',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'Quatre écrans de comptabilité ne figurent pas dans la barre '
            'latérale et ne s\'atteignent que par les tuiles de l\'écran '
            'Comptabilité : Journal Comptable, Plan Comptable, Comptabilité '
            'Analytique et Clôture d\'Exercice.',
          ),
          EncadreManuel.attention(
            'Un écran absent de votre menu n\'est pas une panne : votre rôle ne '
            'vous y donne pas droit. La liste complète figure à l\'annexe A.',
          ),
        ],
      ),
    ],
  );

  // ============================================================ 2. ÉLEVAGE

  static const ChapitreManuel _elevage = ChapitreManuel(
    titre: 'Élevage et couveuse',
    introduction:
        'Le cœur du métier : la vue d\'ensemble de l\'animalier, les lots en '
        'incubation, les fiches journalières de chaque filière et le '
        'calendrier de soins.',
    sections: [
      SectionManuel(
        titre: 'Dashboard Élevage',
        chemin: 'ÉLEVAGE & COUVEUSE › Dashboard Élevage',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '02-dashboard-elevage',
        aQuoiCaSert:
            'La vue consolidée des filières actives : effectifs, mortalité, '
            'provende consommée, soins à venir et lots de couveuse. C\'est '
            'l\'écran de l\'animalier.',
        aRetenir: [
          'Une filière désactivée dans les Paramètres disparaît de cet écran.',
          'Les effectifs viennent de la dernière journée réellement saisie.',
        ],
      ),
      SectionManuel(
        titre: 'Cycle Couveuse',
        chemin: 'ÉLEVAGE & COUVEUSE › Cycle Couveuse',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '03-cycle-couveuse',
        aQuoiCaSert:
            'Il suit une couveuse en incubation continue : plusieurs lots '
            'd\'âges différents, dans une ou plusieurs machines. Chaque lot a '
            'son calendrier — deux mirages, puis l\'éclosion — et son taux.',
        tableaux: [
          TableauManuel(
            titre: 'Les colonnes du tableau Lots d\'Incubation',
            colonnes: [
              ColonneManuel('Lot', 'Référence du lot, C-2026-004 par exemple.'),
              ColonneManuel(
                'Espèce',
                'Goliath ou Pintadeau — elle fixe la durée d\'incubation.',
              ),
              ColonneManuel('Machine', 'L\'incubateur qui héberge le lot.'),
              ColonneManuel(
                'Chargés',
                'Nombre d\'œufs mis en couveuse au départ.',
              ),
              ColonneManuel('Âge', 'Jours écoulés depuis le chargement.'),
              ColonneManuel(
                'Mirages',
                'Les deux boutons MIRAGE 1 et MIRAGE 2. Ils passent au rouge dès que l\'échéance est atteinte.',
              ),
              ColonneManuel(
                'Éclosion Prévue',
                'La fourchette calculée, deux jours avant à deux jours après.',
              ),
              ColonneManuel(
                'TER',
                'Taux d\'Éclosion Réel : éclos rapportés aux œufs retenus après les deux mirages. Vide tant que le lot n\'a pas éclos.',
              ),
              ColonneManuel('Statut', 'En incubation, Éclos, ou Remplacé.'),
              ColonneManuel(
                'Actions',
                'Éclosion, historique des remplacements, modification, suppression.',
              ),
            ],
          ),
        ],
        modales: [
          ModaleManuel(
            nom: 'Déclarer un Nouveau Cycle',
            declencheur: 'Déclarer un Nouveau Cycle',
            aQuoiCaSert:
                'Elle met un lot d\'œufs en incubation et calcule aussitôt son calendrier : les deux mirages et la fourchette d\'éclosion.',
            capture: 'm01-couveuse-nouveau-cycle',
            champs: [
              ColonneManuel(
                'ESPÈCE',
                'Goliath ou Pintadeau. C\'est elle qui fixe la durée d\'incubation : 21 jours ou 28.',
              ),
              ColonneManuel(
                'DATE DE CHARGEMENT',
                'Le jour où les œufs entrent dans la machine. Tout le calendrier en découle.',
              ),
              ColonneManuel(
                'INCUBATEUR',
                'La machine qui reçoit le lot. Son occupation se met à jour.',
              ),
              ColonneManuel(
                'NOMBRE D\'ŒUFS CHARGÉS',
                'Le compte réel mis en couveuse. Il sert de dénominateur au taux brut.',
              ),
              ColonneManuel(
                'CALENDRIER PRÉVISIONNEL (CALCULÉ)',
                'Ne se saisit pas. Il affiche les dates de mirage et la fourchette d\'éclosion dès que l\'espèce et la date sont renseignées.',
              ),
            ],
            encadres: [
              EncadreManuel.attention(
                'La date d\'éclosion s\'affiche en **fourchette**, deux jours avant et deux jours après. Une éclosion ne tombe pas au jour dit : la température, l\'hygrométrie et l\'âge des reproducteurs l\'avancent ou la retardent.',
              ),
            ],
          ),
          ModaleManuel(
            nom: 'Ajouter un Incubateur',
            declencheur: 'Ajouter un Incubateur',
            aQuoiCaSert:
                'Elle déclare une machine. Sans incubateur, un lot ne peut pas dire où il se trouve.',
            capture: 'm02-couveuse-incubateur',
            champs: [
              ColonneManuel(
                'CODE',
                'Identifiant court, INC-01 par exemple. Il figure sur chaque ligne de lot.',
              ),
              ColonneManuel('LIBELLÉ', 'Le nom courant de la machine.'),
              ColonneManuel(
                'CAPACITÉ',
                'Nombre d\'œufs que la machine accepte. Sert à afficher son taux d\'occupation.',
              ),
            ],
          ),
        ],
        etapes: [
          EtapeManuel(
            'Déclarez vos incubateurs',
            'Bouton « Ajouter un Incubateur ». Le code, le libellé, et la '
                'capacité si vous la connaissez.',
          ),
          EtapeManuel(
            'Déclarez un nouveau cycle',
            'Bouton « Déclarer un Nouveau Cycle ». Espèce, date de chargement, '
                'incubateur et nombre d\'œufs. Le calendrier prévisionnel '
                's\'affiche aussitôt.',
          ),
          EtapeManuel(
            'Faites le premier mirage à J+7',
            'Dans la ligne du lot, le bouton MIRAGE 1 passe au rouge quand '
                'l\'échéance est atteinte. Saisissez le nombre d\'œufs clairs '
                'retirés.',
          ),
          EtapeManuel(
            'Faites le second mirage à J+14',
            'Même geste avec MIRAGE 2, pour les œufs gâtés — ceux dont '
                'l\'embryon a démarré puis s\'est arrêté.',
          ),
          EtapeManuel(
            'Enregistrez l\'éclosion',
            'Le bouton rouge « Éclosion » clôture le lot. Saisissez les '
                'poussins éclos et les œufs perdus. Vous pouvez, dans la foulée, '
                'charger un nouveau lot à la place libérée.',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'La date d\'éclosion s\'affiche en fourchette, deux jours avant et '
            'deux jours après. Une éclosion ne tombe pas au jour dit : la '
            'température, l\'hygrométrie et l\'âge des reproducteurs '
            'l\'avancent ou la retardent.',
          ),
          EncadreManuel.attention(
            'La pintade incube 28 jours, pas 27. Le goliath, 21 jours. Les '
            'dates sont calculées, jamais saisies.',
          ),
          EncadreManuel.astuce(
            'Le sélecteur « Situation au … » en haut rejoue l\'écran à une '
            'date passée : pratique pour comprendre après coup ce qui s\'est '
            'passé sur un lot décevant.',
          ),
          EncadreManuel.alerte(
            'Un lot éclos ne se modifie ni ne se supprime : ses poussins sont '
            'déjà entrés dans les effectifs et son taux dans les statistiques.',
          ),
        ],
        aRetenir: [
          'L\'icône en arborescence ouvre l\'historique des remplacements : '
              'la suite des lots ayant occupé la même place.',
          'Chaque sous-lot a ses propres mirages, comptés depuis sa date à lui.',
        ],
      ),
      SectionManuel(
        titre: 'Statistiques Mirages',
        chemin: 'ÉLEVAGE & COUVEUSE › Statistiques Mirages',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '04-statistiques-mirages',
        aQuoiCaSert:
            'Il répond à une question que le taux d\'éclosion seul ne tranche '
            'pas : quand une couvée rate, à qui la faute ?',
        etapes: [
          EtapeManuel(
            'Choisissez la période',
            'Les taux ne portent que sur les lots chargés dans cette période.',
          ),
          EtapeManuel(
            'Lisez les trois taux',
            'Infertilité, mortalité embryonnaire, taux d\'éclosion réel : chacun accuse une cause différente.',
          ),
          EtapeManuel(
            'Recoupez avec le tableau',
            'Le détail par lot montre lequel tire la moyenne vers le bas.',
          ),
        ],
        aRetenir: [
          'Beaucoup d\'œufs clairs au J+7 : ils n\'ont jamais été fécondés. '
              'C\'est le troupeau de reproducteurs qui est en cause, pas la '
              'machine.',
          'Beaucoup d\'œufs gâtés au J+14 : les embryons ont démarré puis se '
              'sont arrêtés. C\'est la conduite de l\'incubation.',
          'Peu d\'éclos sur les œufs retenus : c\'est la fin d\'incubation.',
        ],
        encadres: [
          EncadreManuel.attention(
            'Un bandeau rouge signale les lots dont un mirage est échu et non '
            'saisi. Tant qu\'il en manque, tous les taux de cet écran sont '
            'faux : un mirage oublié gonfle le dénominateur et fait passer une '
            'bonne couvée pour une mauvaise.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Fiche Goliaths',
        chemin: 'ÉLEVAGE & COUVEUSE › Fiche Goliaths',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '05-fiche-goliaths',
        aQuoiCaSert:
            'La saisie journalière d\'une filière : entrées, sorties, morts et '
            'dons par catégorie. L\'effectif, le rationnement et le taux de '
            'mortalité se calculent tout seuls. Les cinq fiches fonctionnent '
            'de la même façon ; seuls les libellés changent.',
        etapes: [
          EtapeManuel(
            'Déclarez la mise en bande',
            'Le bandeau du haut. La date de mise en place devient le jour 1 du '
                'cycle : c\'est elle qui date les échéances de prophylaxie.',
          ),
          EtapeManuel(
            'Choisissez le jour',
            'Le tableau du bas — cliquez sur une date pour ouvrir sa saisie.',
          ),
          EtapeManuel(
            'Saisissez les mouvements',
            'Achats et Nés (Couveuse) se règlent aux boutons « − » et « + », '
                'ou en tapant '
                'directement le nombre. Ventes (POS) est en lecture seule : elle '
                'vient du point de vente.',
          ),
          EtapeManuel(
            'Comptez les pertes par catégorie',
            'Chaque catégorie a son compteur. Une mortalité saisie sur une '
                'catégorie ne touche qu\'elle.',
          ),
          EtapeManuel(
            'Enregistrez',
            'L\'effectif final et la provende du jour se recalculent, ainsi que '
                'les jours suivants déjà saisis.',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'Les champs numériques n\'acceptent que des chiffres, et jamais de '
            'valeur négative.',
          ),
          EncadreManuel.attention(
            'L\'effectif ne se saisit pas : il se déduit de la veille et des '
            'mouvements du jour. Si un chiffre vous paraît faux, corrigez le '
            'mouvement, pas l\'effectif.',
          ),
          EncadreManuel.astuce(
            'La pilule « Vue Hebdomadaire », à droite du titre de '
            'l\'historique, résume le mois par semaines.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Fiche Pintades',
        chemin: 'ÉLEVAGE & COUVEUSE › Fiche Pintades',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '06-fiche-pintades',
        aQuoiCaSert:
            'Identique à la fiche Goliaths, avec les catégories et les rations '
            'propres aux pintades.',
      ),
      SectionManuel(
        titre: 'Fiche Lapins',
        chemin: 'ÉLEVAGE & COUVEUSE › Fiche Lapins',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '07-fiche-lapins',
        aQuoiCaSert:
            'Même principe. Les naissances s\'appellent ici « Nés (Mise bas) ».',
        encadres: [
          EncadreManuel.information(
            'La fiche n\'apparaît que si le module Cuniculture est activé dans '
            'Paramètres Général.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Fiche Escargots',
        chemin: 'ÉLEVAGE & COUVEUSE › Fiche Escargots',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '07b-fiche-escargots',
        aQuoiCaSert:
            'Même principe, avec trois catégories : Naissain, Marchand '
            '(vendu à la pièce) et Reproducteur. Les naissances s\'appellent '
            'ici « Nés (Éclosions) ».',
        encadres: [
          EncadreManuel.information(
            'La fiche n\'apparaît que si le module Héliciculture est activé '
            'dans Paramètres Général. Le calendrier de soins est un '
            'calendrier d\'hygiène : l\'Agent d\'Élevage peut le compléter '
            'dans Paramètres Élevage.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Fiche Ovins',
        chemin: 'ÉLEVAGE & COUVEUSE › Fiche Ovins',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '07c-fiche-ovins',
        aQuoiCaSert:
            'Même principe, avec trois catégories : Agneau, Embouche (vendue à '
            'la tête) et Reproducteur. Les naissances s\'appellent ici « Nés '
            '(Agnelage) ».',
        encadres: [
          EncadreManuel.information(
            'La fiche n\'apparaît que si le module Ovins est activé dans '
            'Paramètres Général. Les rations affichées sont indicatives, et '
            'les doses du calendrier de prophylaxie sont des repères : la '
            'notice du produit utilisé prévaut toujours.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Fiche Poissons-Chats',
        chemin: 'ÉLEVAGE & COUVEUSE › Fiche Poissons-Chats',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '08-fiche-poissons-chats',
        aQuoiCaSert:
            'Même principe, avec le vocabulaire de la pisciculture. La colonne '
            'de naissances s\'appelle simplement « Nés » : un poisson-chat n\'a '
            'pas de couveuse.',
      ),
      SectionManuel(
        titre: 'Fiche Poulets/Pondeuses',
        chemin: 'ÉLEVAGE & COUVEUSE › Fiche Poulets/Pondeuses',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '09-fiche-poulets-pondeuses',
        aQuoiCaSert:
            'La fiche des pondeuses ajoute le suivi du stock d\'œufs : œufs '
            'pondus, œufs cassés et sorties en plateaux de 30.',
        onglets: [
          OngletManuel(
            'Poulets',
            'Les poulets de chair : entrées, sorties, pertes et effectif, comme sur les autres fiches.',
          ),
          OngletManuel(
            'Pondeuses',
            'Les pondeuses, avec en plus le suivi du stock d\'œufs : œufs pondus, œufs cassés, sorties en plateaux de 30.',
            capture: '09b-fiche-poulets-pondeuses-pondeuses',
          ),
        ],
        encadres: [
          EncadreManuel.attention(
            'Le stock d\'ouverture d\'un jour est le **stock final** de la '
            'veille, pas son total du jour. Les deux ne coïncident que les '
            'jours sans sortie de plateaux.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Soins & Calendrier',
        chemin: 'ÉLEVAGE & COUVEUSE › Soins & Calendrier',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '10-soins-calendrier',
        aQuoiCaSert:
            'Trois onglets : le registre des soins, les doses administrées, et '
            'le suivi d\'infirmerie — les sujets isolés.',
        modales: [
          ModaleManuel(
            nom: 'Nouveau Soin',
            declencheur: 'Nouveau Soin',
            aQuoiCaSert:
                'Elle inscrit un soin au registre — planifié ou déjà administré.',
            capture: 'm03-soins-nouveau',
            champs: [
              ColonneManuel(
                'TYPE D\'ACTION *',
                'Vaccination, Traitement curatif, Vermifuge ou Vitamines. Liste fermée.',
              ),
              ColonneManuel(
                'LOT / BANDE *',
                'La filière et la bande concernées.',
              ),
              ColonneManuel(
                'DATE DU SOIN *',
                'Le jour prévu, ou celui de l\'administration si elle a déjà eu lieu.',
              ),
              ColonneManuel(
                'PRODUIT UTILISÉ',
                'Le nom commercial, tel qu\'il figure sur le flacon.',
              ),
              ColonneManuel('DOSE', 'La posologie appliquée.'),
              ColonneManuel(
                'DÉLAI D\'ATTENTE / RÉMANENCE (JOURS)',
                'Le nombre de jours pendant lesquels les produits de l\'animal ne se commercialisent pas.',
              ),
              ColonneManuel(
                'COÛT (FCFA)',
                'Ce que le soin a coûté. Alimente le KPI Coût Vétérinaire du mois.',
              ),
              ColonneManuel(
                'VÉTÉRINAIRE / ANIMALIER',
                'Qui a administré le soin.',
              ),
              ColonneManuel(
                'SYMPTÔMES OBSERVÉS',
                'Facultatif. Utile pour un traitement curatif.',
              ),
            ],
            encadres: [
              EncadreManuel.alerte(
                'Un **délai d\'attente** en cours interdit la commercialisation des produits de l\'animal. Le renseigner n\'est pas une formalité : c\'est lui qui déclenche le bandeau rouge et protège l\'exploitation.',
              ),
            ],
          ),
          ModaleManuel(
            nom: 'Planifier une Intervention',
            declencheur: 'Planifier une Intervention',
            aQuoiCaSert:
                'Le même enregistrement, ouvert depuis le planning du mois. C\'est le seul moyen d\'ajouter une échéance sans quitter l\'onglet Calendrier des Doses.',
            capture: 'm04-soins-planifier',
            champs: [
              ColonneManuel('TYPE D\'ACTION *', 'Identique au Nouveau Soin.'),
              ColonneManuel(
                'DATE DU SOIN *',
                'Préremplie avec le mois affiché.',
              ),
            ],
          ),
        ],
        onglets: [
          OngletManuel(
            'Registre des Soins',
            'La liste des soins planifiés et effectués, avec le produit, la dose et le délai d\'attente.',
          ),
          OngletManuel(
            'Calendrier des Doses',
            'Le planning du mois, filière par filière. Son bouton « Planifier une Intervention » est le seul moyen d\'ajouter une échéance depuis le planning.',
            capture: '10b-soins-calendrier-doses',
          ),
          OngletManuel(
            'Suivi Infirmerie',
            'Les sujets isolés : entrée, motif, puis réintégration ou décès.',
            capture: '10c-soins-infirmerie',
          ),
        ],
        etapes: [
          EtapeManuel(
            'Planifiez un soin',
            'Bouton « Nouveau Soin ». Filière, date, type d\'action, produit, '
                'dose et délai d\'attente.',
          ),
          EtapeManuel(
            'Confirmez l\'administration',
            'Le soin passe de « Planifié » à « Effectué ». Le délai d\'attente '
                'court à partir de ce moment.',
          ),
          EtapeManuel(
            'Isolez un sujet malade',
            'Onglet Suivi Infirmerie, bouton d\'entrée. Précisez la filière : '
                'sans elle, un décès ne pourra pas être reporté sur la fiche.',
          ),
          EtapeManuel(
            'Clôturez l\'entrée',
            '« Réintégrer » ou « Décès ». En cas de décès, indiquez dans '
                'quelle catégorie porter la perte.',
          ),
        ],
        encadres: [
          EncadreManuel.alerte(
            'Un délai d\'attente en cours interdit la commercialisation des '
            'produits de l\'animal. Le bandeau rouge le rappelle tant qu\'il '
            'court.',
          ),
          EncadreManuel.information(
            'Au décès, le logiciel ajoute la perte à la fiche d\'élevage du '
            'jour et recalcule les effectifs. Si vous l\'avez déjà saisie '
            'vous-même, choisissez « Déjà saisie sur la fiche ».',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Paramètres Élevage',
        chemin: 'ÉLEVAGE & COUVEUSE › Paramètres Élevage',
        role: 'Administratrice, Agent d\'Élevage',
        capture: '11-parametres-elevage',
        aQuoiCaSert:
            'Les barèmes de rationnement, les calendriers de prophylaxie, les '
            'intrants de provende et le format des numéros de bandes.',
        onglets: [
          OngletManuel(
            'Rationnement',
            'Les barèmes de provende par filière et par stade. Ce que vous changez ici change aussitôt la provende calculée sur les fiches journalières. Les ovins se rationnent autrement : un second tableau donne, par classe de poids vif, le pourcentage du poids à distribuer chaque jour, et la fiche Ovins calcule sa provende à partir de la pesée du lot. Les valeurs proposées sont des repères marqués « à valider » : dans la fenêtre de modification, le bouton Valider les passe à « validé » (changer ensuite la valeur les remet « à valider »).',
          ),
          OngletManuel(
            'Calendriers Prophylaxie',
            'Les échéances de vaccination et de traitement, datées en jour du cycle, avec le produit, la dose et la rémanence.',
            capture: '11b-parametres-elevage-prophylaxie',
          ),
          OngletManuel(
            'Intrants de Provende',
            'La composition de la provende : quels intrants entrent dans sa fabrication.',
            capture: '11c-parametres-elevage-provende',
          ),
          OngletManuel(
            'Numérotation Bandes & Sujets',
            'Les conventions de numérotation par filière : préfixe d\'enclos, de cage, de bande.',
            capture: '11d-parametres-elevage-numerotation',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'Une ration modifiée ici change immédiatement la provende calculée '
            'sur les fiches journalières. C\'est le seul endroit où la '
            'modifier.',
          ),
          EncadreManuel.attention(
            'Les échéances de prophylaxie sont datées en **jour du cycle** '
            '(J1, J5, J15), pas en jour du mois. Elles ne se convertissent en '
            'dates réelles qu\'une fois la bande déclarée sur la fiche.',
          ),
        ],
      ),
    ],
  );

  // ========================================================= 3. COMMERCIAL

  static const ChapitreManuel _commercial = ChapitreManuel(
    titre: 'Vendre et suivre les clients',
    introduction: 'Le point de vente, les créances, et l\'inventaire valorisé.',
    sections: [
      SectionManuel(
        titre: 'Ventes',
        chemin: 'VENTES & CLIENTS › Ventes',
        role: 'Administratrice, Agent de Vente',
        capture: '12-ventes',
        aQuoiCaSert:
            'Le point de vente, en quatre onglets : Enregistrer Vente, Devis '
            'Prestations, Historique des Ventes et Retours et Avoirs. Vous '
            'composez un panier, vous encaissez, et la vente met à jour le '
            'stock et la comptabilité en une seule fois.',
        onglets: [
          OngletManuel(
            'Enregistrer Vente',
            'Le point de vente proprement dit : le panier, le montant négocié, le règlement.',
          ),
          OngletManuel(
            'Devis Prestations',
            'Les devis de prestation : client, objet, montant et durée de validité.',
            capture: '12b-ventes-devis',
          ),
          OngletManuel(
            'Historique des Ventes',
            'Toutes les ventes passées. C\'est d\'ici que s\'impriment les factures et que s\'annule une vente.',
            capture: '12c-ventes-historique',
          ),
          OngletManuel(
            'Retours et Avoirs',
            'La liste des avoirs. **Vue de consultation seule** : elle se remplit par les annulations faites depuis l\'Historique, jamais à la main.',
            capture: '12d-ventes-retours',
          ),
        ],
        etapes: [
          EtapeManuel(
            'Ajoutez les articles',
            'Cliquez sur un produit du catalogue. Il entre au panier.',
          ),
          EtapeManuel(
            'Saisissez le montant négocié',
            'Le prix du catalogue est indicatif. C\'est le montant réellement '
                'convenu avec le client que vous saisissez.',
          ),
          EtapeManuel(
            'Choisissez le mode de règlement',
            'Espèces ou Mobile Money. En Mobile Money, la ligne créditée est '
                'celle de Paramètres Général.',
          ),
          EtapeManuel(
            'Choisissez la condition',
            'Comptant, ou Avance si le client ne solde pas. Une avance fait '
                'apparaître Montant reçu (avance) et Payable le : elle ouvre '
                'une créance.',
          ),
          EtapeManuel(
            'Encaissez',
            'Le stock diminue et l\'écriture comptable est générée. La facture '
                's\'imprime ensuite depuis l\'onglet Historique des Ventes, '
                'bouton « Imprimer la Facture ».',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'Le mode de règlement (comment on paie) et la condition (quand on '
            'paie) sont deux choses distinctes. « Avance » n\'est pas un moyen '
            'de paiement.',
          ),
          EncadreManuel.alerte(
            'Une vente annulée n\'est pas effacée : elle est contrepassée. La '
            'trace reste, comme l\'exige la comptabilité.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Clients et Créances',
        chemin: 'VENTES & CLIENTS › Clients et Créances',
        role: 'Administratrice, Agent de Vente',
        capture: '13-clients',
        aQuoiCaSert:
            'La liste des clients, leurs soldes restant dus, et les relances.',
        tableaux: [
          TableauManuel(
            titre: 'Les colonnes des tableaux Clients et Créances Ouvertes',
            colonnes: [
              ColonneManuel('Nom', 'Le client.'),
              ColonneManuel('Téléphone', 'Sert aux relances.'),
              ColonneManuel(
                'Total Achats',
                'Cumul de ce que le client a acheté.',
              ),
              ColonneManuel(
                'Solde Actuel',
                'Ce qu\'il reste dû, toutes ventes confondues.',
              ),
              ColonneManuel(
                'Référence Vente',
                'La vente à l\'origine de la créance.',
              ),
              ColonneManuel('Montant Total', 'Le montant de cette vente.'),
              ColonneManuel('Déjà Réglé', 'Ce qui a été encaissé dessus.'),
              ColonneManuel('Solde Restant Dû', 'La différence, en rouge.'),
              ColonneManuel(
                'Ancienneté',
                'Nombre de jours depuis la vente. Ne devient « En retard » que si une échéance a été convenue.',
              ),
              ColonneManuel('Action', 'Enregistrer un paiement.'),
            ],
          ),
        ],
        modales: [
          ModaleManuel(
            nom: 'Ajouter un Client',
            declencheur: 'Ajouter un Client',
            aQuoiCaSert:
                'Elle crée une fiche client. Une vente à crédit exige un client nommé : « Client Comptant » ne porte pas de créance.',
            capture: 'm08-clients-ajouter',
            champs: [
              ColonneManuel(
                'NOM COMPLET *',
                'Le seul champ obligatoire. C\'est lui qui porte la créance.',
              ),
              ColonneManuel(
                'TÉLÉPHONE',
                'Sert aux relances et figure sur la lettre de rappel.',
              ),
              ColonneManuel(
                'DATE DE NAISSANCE',
                'Facultative. Suivi commercial, sans effet sur la facturation.',
              ),
            ],
          ),
        ],
        etapes: [
          EtapeManuel(
            'Enregistrez un règlement',
            'Sur la ligne du client, saisissez le montant reçu. Le solde '
                'diminue et l\'écriture est générée.',
          ),
          EtapeManuel(
            'Imprimez une relance',
            'Le document reprend le détail des sommes dues.',
          ),
        ],
        encadres: [
          EncadreManuel.attention(
            'Une créance n\'est « En retard » que si une échéance a été '
            'convenue. Sans échéance, elle figure avec son solde mais n\'est '
            'jamais déclarée en retard — et le courrier s\'intitule alors '
            '« Rappel de Solde ».',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Facturation MeCeF',
        chemin: 'VENTES & CLIENTS › Facturation MeCeF',
        role: 'Administratrice, Agent de Vente',
        capture: '14b-factures-mecef',
        aQuoiCaSert:
            'Il émet les factures de vente et les factures d\'avoir exigées par '
            'la conformité fiscale béninoise, et suit leur transmission à la '
            'DGI. L\'entrée n\'apparaît dans le menu que si le module MeCeF est '
            'actif.'
            '',
        tableaux: [
          TableauManuel(
            titre: 'Les colonnes du tableau Factures et avoirs',
            colonnes: [
              ColonneManuel(
                'RÉFÉRENCE',
                'FV-AAAA-NNN pour une facture de vente, FA-AAAA-NNN pour un avoir. Une séquence par type et par année.',
              ),
              ColonneManuel('DATE', 'Date de la pièce.'),
              ColonneManuel(
                'CLIENT',
                'Le client facturé. Sous un avoir figure la facture qu\'il corrige.',
              ),
              ColonneManuel(
                'TOTAL TTC',
                'Toutes taxes comprises. **Négatif** sur un avoir : il retire du chiffre d\'affaires.',
              ),
              ColonneManuel(
                'STATUT',
                'À transmettre, Normalisée ou Rejetée. Un rejet affiche sa raison au survol.',
              ),
              ColonneManuel(
                'ACTIONS',
                'Exporter le PDF, transmettre à e-MECeF, saisir le code de normalisation, émettre un avoir.',
              ),
            ],
          ),
        ],
        modales: [
          ModaleManuel(
            nom: 'Émettre une facture de vente',
            declencheur: 'Émettre une Facture',
            aQuoiCaSert:
                'Elle transforme une vente encaissée en pièce fiscale. La liste ne propose que les ventes **non encore facturées**.',
            capture: 'm10-mecef-emettre',
            champs: [
              ColonneManuel(
                'Vente à facturer *',
                'La vente encaissée. Son montant, son client et sa date sont repris tels quels.',
              ),
              ColonneManuel(
                'IFU du client',
                'Facultatif : un particulier n\'en a pas.',
              ),
              ColonneManuel(
                'Adresse du client',
                'Facultative. Elle s\'imprime sur la facture si elle est '
                    'renseignée.',
              ),
            ],
            encadres: [
              EncadreManuel.alerte(
                'Une facture émise ne se modifie ni ne se supprime. La seule correction possible est un avoir.',
              ),
            ],
          ),
        ],
        etapes: [
          EtapeManuel(
            'Activez le module',
            'Paramètres Général › Modules Actifs. Il ne devient activable '
                'qu\'une fois l\'IFU et le RCCM renseignés : une facture sans '
                'ces mentions n\'est pas recevable.',
          ),
          EtapeManuel(
            'Renseignez la transmission',
            'URL du service e-MECeF, NIM et jeton, sous l\'interrupteur. Sans '
                'eux, les factures s\'émettent et s\'impriment mais restent '
                '« À transmettre ».',
          ),
          EtapeManuel(
            'Émettez une facture',
            'Bouton « Émettre une Facture », puis choisissez la vente '
                'encaissée à facturer. L\'IFU du client est facultatif : un '
                'particulier n\'en a pas.',
          ),
          EtapeManuel(
            'Transmettez-la',
            'Icône « Transmettre à e-MECeF » sur la ligne. Si la transmission '
                'échoue, la facture passe « Rejetée » et le motif s\'affiche au '
                'survol de la pastille.',
          ),
          EtapeManuel(
            'Corrigez par un avoir',
            'Icône rouge « Émettre un avoir », motif obligatoire. La facture '
                'd\'origine n\'est pas modifiée : elle est contrepassée.',
          ),
        ],
        encadres: [
          EncadreManuel.alerte(
            'Une facture émise ne se modifie ni ne se supprime, jamais. La '
            'seule correction possible est un avoir. C\'est la règle fiscale, '
            'et c\'est aussi la seule qui laisse une trace vérifiable de '
            'l\'erreur.',
          ),
          EncadreManuel.attention(
            'Une facture n\'est **normalisée** que lorsque la DGI a rendu un '
            'code et un NIM. Tant qu\'ils manquent, le document imprimé porte '
            'en toutes lettres « FACTURE NON NORMALISÉE ». Ne le remettez pas '
            'à un client en le présentant comme une facture en règle.',
          ),
          EncadreManuel.information(
            'Le groupe de taxe vient du produit, réglable dans Catalogue & '
            'Seuils. Les produits sont **exonérés par défaut** : réclamer une '
            'TVA non due engage l\'entreprise, alors qu\'une taxe oubliée se '
            'rattrape par un avoir.',
          ),
          EncadreManuel.astuce(
            'Le montant du panier est déjà toutes taxes comprises. La facture '
            'en extrait la taxe au lieu de l\'ajouter : le client paie '
            'exactement ce qu\'il a réglé en caisse.',
          ),
        ],
        aRetenir: [
          'Le jeton e-MECeF n\'est pas stocké dans la base : il ne part donc '
              'pas dans les sauvegardes.',
          'Facturé Net = factures de vente moins avoirs. Un avoir retire du '
              'chiffre d\'affaires, il ne s\'y ajoute pas.',
        ],
      ),
      SectionManuel(
        titre: 'Inventaire',
        chemin: 'VENTES & CLIENTS › Inventaire',
        role: 'Administratrice, Agent de Vente',
        capture: '14-inventaire',
        aQuoiCaSert:
            'L\'état daté de ce que détient l\'exploitation, valorisé au coût. '
            'Il répond à la question du comptable : que possédait-on à cette '
            'date, et d\'où vient l\'écart avec la précédente ?',
        tableaux: [
          TableauManuel(
            titre: 'Les colonnes des trois tableaux',
            colonnes: [
              ColonneManuel(
                'ARTICLE / PRODUIT',
                'Le nom de la ligne inventoriée.',
              ),
              ColonneManuel('CATÉGORIE', 'Famille de l\'article.'),
              ColonneManuel(
                'STOCK INITIAL',
                'La quantité détenue au premier jour de la période.',
              ),
              ColonneManuel(
                'ENTRÉES',
                'Ce qui est entré pendant la période : réceptions, fabrications, retours.',
              ),
              ColonneManuel(
                'SORTIES',
                'Ce qui en est sorti : consommations, ventes, ajustements négatifs.',
              ),
              ColonneManuel(
                'STOCK FINAL',
                'Stock initial + entrées − sorties. Les quatre colonnes doivent se boucler.',
              ),
              ColonneManuel(
                'COÛT DE REVIENT',
                'Base de valorisation des produits finis. Vide, le produit n\'entre dans aucun total.',
              ),
              ColonneManuel('VALEUR', 'Stock final × base de valorisation.'),
              ColonneManuel(
                'DERNIÈRE SAISIE',
                'Pour les animaux : le jour de la dernière fiche renseignée. « Jamais saisie » et « effectif nul » ne disent pas la même chose.',
              ),
            ],
          ),
        ],
        etapes: [
          EtapeManuel(
            'Choisissez la période',
            'Journalier, Hebdomadaire, Mensuel ou Plage personnalisée.',
          ),
          EtapeManuel(
            'Lisez les quatre colonnes de mouvement',
            'Stock initial, entrées, sorties, stock final. Les quatre doivent '
                'se boucler.',
          ),
          EtapeManuel(
            'Imprimez l\'état',
            'Le PDF reprend les trois tableaux et les bases de valorisation.',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'Les intrants sont valorisés au prix moyen pondéré, les produits '
            'finis à leur coût de revient. Jamais au prix de vente : un animal '
            'encore en enclos n\'a rien rapporté.',
          ),
          EncadreManuel.attention(
            'Un produit sans coût de revient renseigné n\'entre dans aucun '
            'total. Le nombre d\'articles exclus est annoncé sous le montant.',
          ),
          EncadreManuel.alerte(
            'Un bandeau rouge signale les articles dont les mouvements '
            'n\'expliquent pas le stock. Vérifiez-les avant de signer l\'état.',
          ),
        ],
        aRetenir: [
          'Les animaux sur pied sont comptés mais non valorisés : leur coût '
              'dépend de la provende consommée, que le logiciel ne cumule pas '
              'par lot.',
        ],
      ),
    ],
  );

  // ================================================== 4. APPROVISIONNEMENT

  static const ChapitreManuel _approvisionnement = ChapitreManuel(
    titre: 'Acheter et tenir les stocks',
    introduction:
        'Les commandes aux fournisseurs, les réceptions, et le stock d\'intrants.',
    sections: [
      SectionManuel(
        titre: 'Achats & Commandes',
        chemin: 'ACHATS & FOURNISSEURS › Achats & Commandes',
        role: 'Administratrice',
        capture: '15-achats',
        aQuoiCaSert:
            'Les commandes passées aux fournisseurs, de leur création à leur '
            'réception.',
        etapes: [
          EtapeManuel(
            'Créez la commande',
            'Choisissez le fournisseur, ajoutez les lignes, puis « Valider la Commande ».',
          ),
          EtapeManuel(
            'Réceptionnez la marchandise',
            'Bouton « Réceptionner » sur la ligne, à l\'arrivée. Le stock entre et le prix moyen pondéré est recalculé.',
          ),
        ],
        encadres: [
          EncadreManuel.attention(
            'C\'est la **réception** qui fait entrer la marchandise en stock et '
            'qui recalcule le prix moyen pondéré, pas la commande.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Fournisseurs',
        chemin: 'ACHATS & FOURNISSEURS › Fournisseurs',
        role: 'Administratrice',
        capture: '16-fournisseurs',
        aQuoiCaSert:
            'Le répertoire des fournisseurs et le suivi des sommes dues.',
        modales: [
          ModaleManuel(
            nom: 'Ajouter un Fournisseur',
            declencheur: 'Ajouter un Fournisseur',
            aQuoiCaSert:
                'Elle crée une fiche fournisseur, à laquelle se rattachent les commandes et les dettes.',
            capture: 'm09-fournisseurs-ajouter',
            champs: [
              ColonneManuel('Nom *', 'Le seul champ obligatoire.'),
              ColonneManuel(
                'Téléphone',
                'Facultatif. Utile pour relancer une commande en retard.',
              ),
              ColonneManuel(
                'Adresse',
                'Facultative. Elle figure sur les documents d\'achat.',
              ),
            ],
          ),
        ],
        etapes: [
          EtapeManuel(
            'Ajoutez un fournisseur',
            'Bouton « Ajouter un Fournisseur ». Le Nom est le seul champ obligatoire.',
          ),
          EtapeManuel(
            'Suivez la dette',
            'La carte Dette Totale et la colonne du tableau donnent ce qui reste dû à chacun.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Gestion Stocks',
        chemin: 'STOCKS & CATALOGUE › Gestion Stocks',
        role: 'Administratrice',
        capture: '17-gestion-stocks',
        aQuoiCaSert:
            'L\'état des intrants — provende, produits vétérinaires — avec '
            'leurs seuils d\'alerte et l\'historique des mouvements.',
        tableaux: [
          TableauManuel(
            titre: 'Les colonnes du tableau des intrants',
            colonnes: [
              ColonneManuel('Désignation', 'Le nom de l\'intrant.'),
              ColonneManuel(
                'Catégorie',
                'Famille, dont dépend l\'usage en fabrication.',
              ),
              ColonneManuel('Quantité', 'Le stock actuel, avec son unité.'),
              ColonneManuel(
                'Seuil',
                'En dessous, l\'article passe en alerte critique.',
              ),
              ColonneManuel(
                'PMP',
                'Prix moyen pondéré, recalculé à chaque réception.',
              ),
              ColonneManuel('Valeur', 'Quantité × PMP.'),
              ColonneManuel(
                'Actions',
                'Ajustement d\'inventaire, modification, suppression.',
              ),
            ],
          ),
        ],
        modales: [
          ModaleManuel(
            nom: 'Ajouter un Intrant',
            declencheur: 'Ajouter un Intrant',
            aQuoiCaSert:
                'Elle crée un article de stock : provende, produit vétérinaire, composant de fabrication.',
            capture: 'm05-stocks-intrant',
            champs: [
              ColonneManuel(
                'DÉSIGNATION *',
                'Le nom de l\'article, tel qu\'il apparaîtra partout ailleurs.',
              ),
              ColonneManuel(
                'CATÉGORIE *',
                'Détermine notamment si l\'article entre dans la fabrication de provende.',
              ),
              ColonneManuel('QUANTITÉ', 'Le stock de départ.'),
              ColonneManuel(
                'UNITÉ',
                'kg, sac, dose… Elle accompagne chaque quantité affichée.',
              ),
              ColonneManuel(
                'SEUIL D\'ALERTE',
                'En dessous, l\'article déclenche une alerte critique et la popup du tableau de bord.',
              ),
              ColonneManuel(
                'PRIX UNITAIRE (PMP)',
                'Prix moyen pondéré. Il sert à valoriser le stock, et se recalcule seul à chaque réception.',
              ),
            ],
          ),
          ModaleManuel(
            nom: 'Fabrication de Provende',
            declencheur: 'Fabrication de Provende',
            aQuoiCaSert:
                'Elle transforme des intrants en provende : les composants sortent du stock, la provende y entre.',
            capture: 'm06-stocks-provende',
            champs: [
              ColonneManuel(
                'Quantités par composant',
                'Une ligne par intrant de catégorie « Intrants Provende ». Saisissez ce qui part réellement au mélange.',
              ),
            ],
            encadres: [
              EncadreManuel.attention(
                'La fabrication **consomme** les composants. Une quantité saisie par erreur se corrige par un ajustement d\'inventaire, pas en refaisant la fabrication à l\'envers.',
              ),
            ],
          ),
        ],
        etapes: [
          EtapeManuel(
            'Ajoutez un intrant',
            'Bouton « Ajouter un Intrant ». Désignation, unité, quantité et seuil d\'alerte.',
          ),
          EtapeManuel(
            'Fabriquez la provende',
            'Bouton « Fabrication de Provende ». Saisissez les quantités de chaque composant : elles sortent du stock, la provende y entre.',
          ),
          EtapeManuel(
            'Corrigez un écart',
            'Icône « Ajustement d\'inventaire » sur la ligne. L\'écart est enregistré comme un mouvement, avec son motif.',
          ),
        ],
        aRetenir: [
          'Un article sous son seuil remonte en alerte sur le tableau de bord.',
          'Chaque mouvement porte sa date, son motif et sa quantité signée.',
        ],
      ),
      SectionManuel(
        titre: 'Catalogue & Seuils',
        chemin: 'STOCKS & CATALOGUE › Catalogue & Seuils',
        role: 'Administratrice',
        capture: '18-catalogue',
        aQuoiCaSert:
            'Les produits vendables : tarif indicatif, coût de revient, stock '
            'et seuil.',
        modales: [
          ModaleManuel(
            nom: 'Ajouter un Produit',
            declencheur: 'Ajouter un Produit',
            aQuoiCaSert:
                'Elle crée un produit vendable : ce qui apparaîtra au point de vente.',
            capture: 'm07-catalogue-produit',
            champs: [
              ColonneManuel(
                'DÉSIGNATION *',
                'Le nom vu par l\'Agent de Vente.',
              ),
              ColonneManuel(
                'SKU',
                'Code article, généré sous la forme PRD-001 s\'il est laissé vide.',
              ),
              ColonneManuel(
                'CATÉGORIE',
                'Avicole, Commerce Annexe, Cuniculture, Pisciculture.',
              ),
              ColonneManuel(
                'TARIF INDICATIF (FCFA) *',
                'Le prix de référence. Il reste **indicatif** : la caisse enregistre le montant négocié.',
              ),
              ColonneManuel(
                'TARIF HAUT (FACULTATIF)',
                'Le haut de la fourchette de négociation, s\'il y en a une.',
              ),
              ColonneManuel(
                'COÛT DE REVIENT (FCFA)',
                'Ce que le produit a coûté. Il valorise le stock ; sans lui, le produit n\'entre dans aucun total d\'inventaire.',
              ),
              ColonneManuel('STOCK', 'La quantité disponible.'),
              ColonneManuel(
                'SEUIL D\'ALERTE',
                'En dessous, le produit remonte en stock critique.',
              ),
              ColonneManuel('UNITÉ', 'sujet, plateau, kg…'),
            ],
            encadres: [
              EncadreManuel.attention(
                'Un coût de revient **supérieur** au tarif est refusé : chaque vente serait à perte. C\'est le prix qu\'il faut corriger, pas le contrôle.',
              ),
            ],
          ),
        ],
        etapes: [
          EtapeManuel(
            'Ajoutez un produit',
            'Bouton « Ajouter un Produit ». Désignation, catégorie, tarif, coût de revient et seuil.',
          ),
          EtapeManuel(
            'Vérifiez les stocks critiques',
            'La carte Produits en Stock Critique compte ceux passés sous leur seuil.',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'Le coût de revient sert à valoriser le stock. Sans lui, le produit '
            'apparaît « Non valorisé » dans l\'inventaire — c\'est voulu : '
            'mieux vaut un trou signalé qu\'un chiffre inventé.',
          ),
          EncadreManuel.attention(
            'Un coût de revient supérieur au tarif est refusé : chaque vente '
            'serait à perte, c\'est le prix qu\'il faut corriger.',
          ),
        ],
      ),
    ],
  );

  // ======================================================= 5. COMPTABILITÉ

  static const ChapitreManuel _comptabilite = ChapitreManuel(
    titre: 'Tenir la comptabilité',
    introduction:
        'Comptabilité SYSCOHADA en partie double. La plupart des écritures sont '
        'générées automatiquement par les ventes et les achats ; vous saisissez '
        'surtout les dépenses.',
    sections: [
      SectionManuel(
        titre: 'Comptabilité',
        chemin: 'COMPTABILITÉ › Comptabilité',
        role: 'Administratrice',
        capture: '19-comptabilite-hub',
        aQuoiCaSert:
            'Le point d\'entrée du module : quatre indicateurs de synthèse — '
            'Total Actif, Trésorerie, Résultat Cumulé, Marge Nette — et les '
            'tuiles qui mènent à chaque écran comptable.',
        encadres: [
          EncadreManuel.information(
            'Quatre écrans ne figurent pas dans la barre latérale et ne '
            's\'atteignent que d\'ici : Journal Comptable, Plan Comptable, '
            'Comptabilité Analytique et Clôture d\'Exercice.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Journal Comptable',
        chemin: 'COMPTABILITÉ › Comptabilité › Journal Comptable',
        role: 'Administratrice',
        capture: '20-journal-comptable',
        aQuoiCaSert:
            'Toutes les écritures, dans l\'ordre, par journal : ventes, '
            'achats, caisse, opérations diverses.',
        tableaux: [
          TableauManuel(
            titre: 'Les colonnes du journal',
            colonnes: [
              ColonneManuel('Date', 'Date de l\'écriture.'),
              ColonneManuel(
                'N° Pièce',
                'Le numéro qui relie l\'écriture à la vente ou à l\'achat dont elle vient. C\'est par lui que se recoupe une opération.',
              ),
              ColonneManuel(
                'Journal',
                'VT ventes, AC achats, CA caisse, OD opérations diverses.',
              ),
              ColonneManuel('Compte', 'Le numéro SYSCOHADA mouvementé.'),
              ColonneManuel('Libellé', 'Ce que l\'écriture enregistre.'),
              ColonneManuel('Débit', 'Montant porté au débit.'),
              ColonneManuel(
                'Crédit',
                'Montant porté au crédit. Sur une même pièce, la somme des débits égale celle des crédits.',
              ),
            ],
          ),
        ],
        etapes: [
          EtapeManuel(
            'Choisissez le journal',
            'Ventes, Achats, Caisse ou Opérations Diverses.',
          ),
          EtapeManuel(
            'Retrouvez une pièce',
            'Chaque écriture porte son numéro de pièce : c\'est par lui que se recoupe une vente ou un achat.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Grand Livre',
        chemin: 'COMPTABILITÉ › Grand Livre',
        role: 'Administratrice',
        capture: '21-grand-livre',
        aQuoiCaSert:
            'Le détail compte par compte, avec le solde après chaque ligne.',
        etapes: [
          EtapeManuel(
            'Choisissez le compte',
            'Le détail s\'affiche, ligne à ligne, dans l\'ordre des dates.',
          ),
          EtapeManuel(
            'Suivez le solde',
            'La dernière colonne donne le solde après chaque écriture.',
          ),
        ],
        encadres: [
          EncadreManuel.astuce(
            'Le solde progressif permet de retrouver l\'écriture exacte à '
            'partir de laquelle un compte a basculé.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Balance Générale',
        chemin: 'COMPTABILITÉ › Balance Générale',
        role: 'Administratrice',
        capture: '22-balance-generale',
        aQuoiCaSert:
            'Reports, mouvements de la période et soldes de clôture, en débit '
            'et en crédit.',
        encadres: [
          EncadreManuel.information(
            'Les deux totaux de chaque paire doivent être égaux. C\'est le '
            'contrôle de la partie double, et il est affiché plutôt que '
            'supposé.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Plan Comptable',
        chemin: 'COMPTABILITÉ › Comptabilité › Plan Comptable',
        role: 'Administratrice',
        capture: '23-plan-comptable',
        aQuoiCaSert: 'La liste des comptes SYSCOHADA utilisés par la ferme.',
      ),
      SectionManuel(
        titre: 'Saisie Dépenses',
        chemin: 'ACHATS & FOURNISSEURS › Saisie Dépenses',
        role: 'Administratrice',
        capture: '24-saisie-depenses',
        aQuoiCaSert:
            'La saisie d\'une dépense courante — transport, électricité, '
            'main-d\'œuvre.',
        etapes: [
          EtapeManuel('Choisissez la date et le compte de charge', ''),
          EtapeManuel('Saisissez le montant et le libellé', ''),
          EtapeManuel(
            'Indiquez l\'axe analytique',
            'Facultatif : il dit à quelle filière imputer la charge.',
          ),
          EtapeManuel('Enregistrez', 'L\'écriture équilibrée est générée.'),
        ],
        encadres: [
          EncadreManuel.information(
            'Sans axe analytique, la charge reste dans les « charges non '
            'affectées » : elle compte dans le résultat, mais pas dans la marge '
            'd\'une filière.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Comptabilité Analytique',
        chemin: 'COMPTABILITÉ › Comptabilité › Comptabilité Analytique',
        role: 'Administratrice',
        capture: '25-comptabilite-analytique',
        aQuoiCaSert:
            'La marge par filière : ce que chaque activité rapporte, une fois '
            'ses charges déduites.',
        encadres: [
          EncadreManuel.attention(
            'Rien n\'est réparti au prorata. Les charges de structure restent '
            'affichées à part : une clé de répartition que personne n\'a fixée '
            'donnerait des marges fausses avec l\'air d\'être exactes.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'États Financiers',
        chemin: 'COMPTABILITÉ › États Financiers',
        role: 'Administratrice',
        capture: '26-etats-financiers',
        aQuoiCaSert:
            'Bilan, compte de résultat, TAFIRE et notes annexes, au format '
            'SYSCOHADA.',
        onglets: [
          OngletManuel('Bilan', 'L\'actif et le passif a la date d\'arrete.'),
          OngletManuel(
            'Compte de Résultat',
            'Les produits, les charges et le résultat de l\'exercice.',
            capture: '26b-etats-financiers-resultat',
          ),
          OngletManuel(
            'Flux de Trésorerie',
            'Le TAFIRE : d\'où vient la trésorerie, et où elle va.',
            capture: '26c-etats-financiers-tresorerie',
          ),
          OngletManuel(
            'Notes Annexes',
            'Les notes qui accompagnent les trois états, exigées par le SYSCOHADA.',
            capture: '26d-etats-financiers-notes',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'Aucun montant ne s\'y saisit. Corriger un état se fait en '
            'corrigeant l\'écriture qui le porte.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Bilan de l\'Entreprise',
        chemin: 'COMPTABILITÉ › Bilan de l\'Entreprise',
        role: 'Administratrice',
        capture: '27-bilan-entreprise',
        aQuoiCaSert: 'La situation patrimoniale : actif, passif, équilibre.',
      ),
      SectionManuel(
        titre: 'Clôture d\'Exercice',
        chemin: 'COMPTABILITÉ › Comptabilité › Clôture d\'Exercice',
        role: 'Administratrice uniquement',
        capture: '28-cloture-exercice',
        aQuoiCaSert:
            'La fermeture de la comptabilité, à deux niveaux : mois par mois, '
            'dans la grille des douze mois, et pour l\'exercice entier. Un '
            'mois clôturé n\'accepte plus d\'écriture.',
        encadres: [
          EncadreManuel.astuce(
            'Clôturez chaque mois une fois vos saisies vérifiées. Une erreur '
            'se rattrape sur un mois ; sur un exercice entier, elle se cherche.',
          ),
          EncadreManuel.alerte(
            'La clôture est l\'opération la plus lourde de la comptabilité. '
            'Vérifiez la Balance Générale et les États Financiers avant de la '
            'lancer. Seule l\'administratrice peut déclôturer.',
          ),
        ],
      ),
    ],
  );

  // ============================================================ 6. RAPPORTS

  static const ChapitreManuel _rapports = ChapitreManuel(
    titre: 'Éditer les rapports',
    introduction: 'Six états exportables en PDF, filtrés sur une période.',
    sections: [
      SectionManuel(
        titre: 'Rapports & États',
        chemin: 'ÉDITIONS › Rapports & États',
        role: 'Administratrice',
        capture: '29-rapports-exports',
        aQuoiCaSert:
            'Ventes, achats, trésorerie, créances, élevage et stocks : chaque '
            'onglet est un état imprimable.',
        onglets: [
          OngletManuel(
            'Recettes et Dépenses',
            'Les entrées et les sorties de la période, avec leur résultat.',
          ),
          OngletManuel(
            'État de Trésorerie',
            'Les mouvements de caisse et de Mobile Money.',
            capture: '29b-rapports-tresorerie',
          ),
          OngletManuel(
            'Créances Clients',
            'Ce que les clients doivent, classé par ancienneté.',
            capture: '29c-rapports-creances',
          ),
          OngletManuel(
            'Dettes Fournisseurs',
            'Ce que la ferme doit à ses fournisseurs.',
            capture: '29d-rapports-dettes',
          ),
          OngletManuel(
            'Rapport Élevage',
            'Effectifs, mortalité et provende consommée, par filière.',
            capture: '29e-rapports-elevage',
          ),
          OngletManuel(
            'Rapport de Stocks',
            'L\'état des intrants et le détail de leurs mouvements.',
            capture: '29f-rapports-stocks',
          ),
        ],
        etapes: [
          EtapeManuel('Choisissez la période', 'En haut de page.'),
          EtapeManuel('Ouvrez l\'onglet voulu', ''),
          EtapeManuel(
            'Exportez en PDF',
            'Le document porte l\'en-tête officielle de l\'entreprise, ses '
                'mentions légales et la date d\'édition.',
          ),
        ],
        encadres: [
          EncadreManuel.astuce(
            'Le document est produit au moment du clic : il reflète donc les '
            'filtres et la période affichés à l\'écran.',
          ),
        ],
      ),
    ],
  );

  // ========================================================== 7. PARAMÈTRES

  static const ChapitreManuel _parametres = ChapitreManuel(
    titre: 'Paramétrer et protéger',
    introduction:
        'La configuration de l\'entreprise, les comptes utilisateurs, les '
        'sauvegardes — et votre profil.',
    sections: [
      SectionManuel(
        titre: 'Paramètres Général',
        chemin: 'PARAMÈTRES › Paramètres Général',
        role: 'Administratrice',
        capture: '30-parametres-generaux',
        aQuoiCaSert:
            'Les modules actifs, l\'identité de l\'entreprise, les comptes '
            'utilisateurs, les modes de paiement, la corbeille, les données de '
            'test et les sauvegardes.',
        onglets: [
          OngletManuel(
            'Modules Actifs',
            'Les filières et les modules que le logiciel affiche. Un module désactivé disparaît du menu.',
          ),
          OngletManuel(
            'Données de l\'Entreprise',
            'Le nom, l\'adresse, l\'IFU et le RCCM. Ils figurent en tête de chaque document imprimé.',
            capture: '30b-parametres-general-entreprise',
          ),
          OngletManuel(
            'Gestion Utilisateurs',
            'Les comptes utilisateurs, leur rôle et leur mot de passe.',
            capture: '30c-parametres-general-utilisateurs',
          ),
          OngletManuel(
            'Modes de Paiement',
            'Les moyens acceptés, et la ligne Mobile Money créditée par les ventes.',
            capture: '30d-parametres-general-paiement',
          ),
          OngletManuel(
            'Sauvegardes',
            'La génération, la restauration et l\'export CSV. C\'est l\'onglet le plus important du logiciel.',
            capture: '30e-parametres-general-sauvegardes',
          ),
          OngletManuel(
            'Corbeille',
            'Ce qui a été supprimé, et de quoi le récupérer.',
            capture: '30f-parametres-general-corbeille',
          ),
          OngletManuel(
            'Données de Test',
            'La génération et l\'effacement des données de démonstration. Réservé à la prise en main.',
            capture: '30g-parametres-general-donnees-test',
          ),
        ],
        etapes: [
          EtapeManuel(
            'Générez une sauvegarde',
            'Onglet Sauvegardes, bouton « Générer une sauvegarde ». Le '
                'fichier est déposé dans vos Documents, dossier '
                'LogiALVIA › Sauvegardes.',
          ),
          EtapeManuel(
            'Restaurez une sauvegarde',
            'Icône « Restaurer cette sauvegarde », sur la ligne voulue. Le logiciel '
                'vérifie le fichier, conserve votre base actuelle, puis applique '
                'la restauration au redémarrage suivant.',
          ),
          EtapeManuel(
            'Récupérez un élément supprimé',
            'Onglet Corbeille. Une suppression archive, elle n\'efface pas.',
          ),
        ],
        encadres: [
          EncadreManuel.astuce(
            'Faites une sauvegarde avant toute opération importante : clôture '
            'd\'exercice, réinitialisation, changement de poste. Elle prend '
            'quelques secondes.',
          ),
          EncadreManuel.alerte(
            'Une restauration remplace toute la base. Les ventes et saisies '
            'faites depuis la date de la sauvegarde seront perdues. Votre base '
            'actuelle est conservée dans le dossier des sauvegardes : '
            'l\'opération reste réversible.',
          ),
          EncadreManuel.attention(
            'La réinitialisation des données de test efface l\'**activité** — '
            'ventes, élevage, dépenses, écritures, clients, fournisseurs — et '
            'préserve le **référentiel** : plan comptable SYSCOHADA, '
            'exercices, comptes utilisateurs, catalogue, intrants, barèmes, '
            'grille de taxe. '
            'Elle exige que le mode « Données de Test » soit activé dans '
            'Modules Actifs — ce verrou existe pour qu\'une exploitation en '
            'service ne puisse pas s\'effacer par mégarde.',
          ),
        ],
        aRetenir: [
          'La base de données ne vit pas dans le dossier du logiciel : une '
              'mise à jour ne l\'efface pas.',
          'Pour changer de poste : sauvegarde sur l\'ancien, copie du fichier, '
              'restauration sur le nouveau.',
        ],
      ),
      SectionManuel(
        titre: 'Mon Profil',
        chemin: 'Avatar, en haut à droite › Mon Profil',
        role: 'Tous',
        capture: '31-mon-profil',
        aQuoiCaSert:
            'Vos informations personnelles et votre mot de passe. '
            'C\'est le seul écran où vous changez vous-même vos identifiants.',
        etapes: [
          EtapeManuel('Modifiez vos informations', 'Nom, fonction, téléphone.'),
          EtapeManuel(
            'Changez votre mot de passe',
            'Saisissez l\'ancien, puis le nouveau deux fois.',
          ),
        ],
        encadres: [
          EncadreManuel.information(
            'Le mot de passe n\'est jamais conservé en clair : seule son '
            'empreinte est stockée, avec un sel propre à votre compte.',
          ),
          EncadreManuel.attention(
            'La case « Se souvenir de moi » de l\'écran de connexion mémorise '
            'votre identifiant, jamais votre session. Le mot de passe reste '
            'demandé à chaque lancement : le poste est partagé.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Aide & À Propos',
        chemin: 'Avatar, en haut à droite › Aide & À Propos',
        role: 'Tous',
        capture: '32-aide-a-propos',
        aQuoiCaSert:
            'L\'aide embarquée, module par module. Elle reste consultable sans '
            'connexion.',
        encadres: [
          EncadreManuel.astuce(
            'Le bouton de visite guidée, en haut de chaque écran, surligne les '
            'éléments un par un et les explique. C\'est le complément direct '
            'de ce manuel.',
          ),
        ],
      ),
      SectionManuel(
        titre: 'Contactez l\'Éditeur',
        chemin: 'Avatar, en haut à droite › Contactez l\'Éditeur',
        role: 'Tous',
        capture: '33-contact-editeur',
        aQuoiCaSert:
            'Signaler une anomalie ou demander une évolution à l\'éditeur du '
            'logiciel. Le message est conservé dans LogiALVIA, avec sa date.',
        etapes: [
          EtapeManuel(
            'Écrivez votre message',
            'Objet et description. Soyez précis sur l\'écran et sur le geste qui pose problème.',
          ),
          EtapeManuel(
            'Enregistrez',
            'Le message est copié dans le presse-papiers : collez-le dans WhatsApp ou dans votre messagerie.',
          ),
        ],
        encadres: [
          EncadreManuel.attention(
            'Le message est enregistré et copié dans le presse-papiers, prêt à '
            'être envoyé. LogiALVIA fonctionne hors ligne : il ne peut pas '
            'l\'expédier lui-même.',
          ),
        ],
      ),
    ],
  );
}
