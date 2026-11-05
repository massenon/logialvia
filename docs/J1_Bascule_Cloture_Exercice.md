# J1 — Bascule & Clôture d'Exercice Comptable

Référence : BR-CPT-001, BR-CPT-002 (Doc B6). Écran : `cloture_exercice_screen.dart` (Doc F6 Écran 9).

**Périmètre de ce document** : la clôture **annuelle**, verrouillage définitif avec génération du Report à Nouveau. Pour la clôture **périodique** (mensuelle, plus légère, avec déblocage exceptionnel possible), voir Doc F6 §6 (BR-CPT-006) — un processus distinct, ne pas confondre les deux.

---

## 1. Processus Complet, Étape par Étape

```
1. Verification pre-cloture
   └─ Tous les comptes de bilan (classes 1 a 5, SYSCOHADA) doivent avoir
      un solde calculable sans ecriture en attente/incoherente
   └─ BR-CPT-004 (Doc F6 §3) : BalanceGeneraleValidator.estEquilibree() DOIT
      retourner true — une cloture sur balance desequilibree est refusee

2. Calcul du solde final de chaque compte de bilan
   └─ Somme(Debit) - Somme(Credit) [ou inverse selon la nature du compte]
      pour toutes les ecritures de l'exercice en cours

3. Verrouillage des ecritures de l'exercice
   └─ EXERCICE_COMPTABLE.isCloture = true
   └─ Toutes les ECRITURE_COMPTABLE de cet exercice : isLocked = true
   └─ BR-CPT-001 : aucune modification possible ensuite

4. Generation des ecritures de Report a Nouveau (RAN)
   └─ Pour chaque compte de bilan a solde non nul :
      creer une ECRITURE_COMPTABLE dans le NOUVEL exercice,
      montant = solde final du compte dans l'exercice cloture,
      meme sens (debiteur reste debiteur)

5. Activation du nouvel exercice
   └─ Creation EXERCICE_COMPTABLE(annee: N+1, isCloture: false)
   └─ Navigation par defaut du systeme bascule sur le nouvel exercice
```

---

## 2. Implémentation — Transaction Atomique Complète

```dart
class ClorerExerciceUseCase {
  final ComptabiliteRepository repository;
  ClorerExerciceUseCase(this.repository);

  Future<void> executer(int anneeACloturer) async {
    await repository.transaction(() async {
      // Etape 1 : verification (leve une exception si incoherence, annule toute la transaction)
      await _verifierCoherence(anneeACloturer);

      // Etape 2 : calcul des soldes
      final soldes = await repository.calculerSoldesBilan(anneeACloturer);

      // Etape 3 : verrouillage
      await repository.verrouillerExercice(anneeACloturer);

      // Etape 4 : generation RAN
      final nouvelleAnnee = anneeACloturer + 1;
      await repository.creerExercice(nouvelleAnnee);
      for (final solde in soldes.where((s) => s.montant != 0)) {
        await repository.creerEcritureRAN(
          exerciceAnnee: nouvelleAnnee,
          numeroCompte: solde.numeroCompte,
          montant: solde.montant,
          libelle: 'Report à Nouveau — Exercice $anneeACloturer',
        );
      }
    });

    // Publication de l'evenement de domaine APRES succes de la transaction (Doc C1 §4)
    eventBus.publish(ExerciceClotureEvent(exerciceAnneeCloturee: anneeACloturer));
  }
}
```

**Règle d'atomicité renforcée** (au-delà de NFRS-FIAB-02) : si une seule étape échoue (ex. calcul de solde incohérent détecté à l'étape 1), **aucune** des étapes suivantes ne doit s'exécuter — la transaction complète est annulée, l'exercice reste dans son état d'avant clôture. Une clôture partiellement appliquée serait la pire régression possible sur ce module.

---

## 3. Interface — Écran de Clôture

### Structure
1. Affichage de l'exercice en cours (année, statut "Actif")
2. Récapitulatif pré-clôture : tableau des soldes projetés par compte de bilan (calculé en aperçu, sans écrire — Doc G1 §4, même principe que le calcul en direct des fiches d'élevage)
3. Liste des anomalies bloquantes s'il y en a (ex. écritures déséquilibrées détectées) — la clôture est **désactivée** tant qu'une anomalie bloquante existe
4. Bouton "Clôturer l'Exercice" — actif uniquement si aucune anomalie bloquante

### Modale de Confirmation Renforcée (au-delà du pattern standard Doc E5 §3)
```dart
Future<bool> confirmerClotureExercice(BuildContext context, int annee) async {
  return await AppModal.show<bool>(context,
    title: 'Clôturer l\'Exercice $annee ?',
    child: Column(children: [
      Icon(Icons.lock, size: 48, color: AppColors.errorDeep),
      const Text('Cette action verrouille définitivement toutes les écritures de cet '
        'exercice. Aucune modification ne sera plus possible après confirmation.'),
      const Text('Un nouvel exercice sera créé avec les soldes de report à nouveau.'),
      // Renforcement specifique : exige une saisie de confirmation textuelle,
      // pas seulement un clic — cohérent avec l'impact global de cette action
      TextField(decoration: const InputDecoration(hintText: 'Tapez CLOTURER pour confirmer')),
    ]),
    actions: [/* ... */],
  ) ?? false;
}
```

---

## 4. Consultation en Lecture Seule des Exercices Antérieurs

Après clôture, l'utilisateur (rôle `admin`, seul rôle ayant accès à la Comptabilité — Doc I1 corrigé) peut toujours **consulter** un exercice clôturé (Journal, Bilan — Doc F6) via un sélecteur d'exercice, mais toute action d'écriture est désactivée sur ces vues quand l'exercice sélectionné a `isCloture=true` — cohérent avec la règle d'affichage déjà posée en Doc F6 Écran 3.
