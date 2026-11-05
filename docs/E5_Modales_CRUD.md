# E5 — Modales CRUD — Spécification Complète

Formalise les 3 patterns de modale déjà construits et validés côté HTML/JS (`gestion-stocks.html`, `suivi-reproduction.html`) — Ajouter, Modifier, Supprimer. S'appuie sur `AppModal` (Doc E2).

---

## 1. Modale "Ajouter" — pattern standard

```dart
Future<void> ouvrirModaleAjouter(BuildContext context, StockViewModel vm) async {
  final nomCtrl = TextEditingController();
  final qteCtrl = TextEditingController();
  String? erreurNom;

  await AppModal.show(context,
    title: 'Ajouter une Entrée de Stock',
    child: StatefulBuilder(builder: (context, setModalState) {
      return Column(children: [
        AppFormField(label: 'Désignation', controller: nomCtrl, required: true, errorText: erreurNom),
        const SizedBox(height: AppSpacing.md),
        AppFormField(label: 'Quantité', controller: qteCtrl, required: true, keyboardType: TextInputType.number),
      ]);
    }),
    actions: [
      AppButton(label: 'Annuler', variant: AppButtonVariant.outline, onPressed: () => Navigator.pop(context)),
      AppButton(label: 'Enregistrer', onPressed: () async {
        if (nomCtrl.text.trim().isEmpty) { setState(() => erreurNom = 'Ce champ est obligatoire.'); return; }
        await vm.ajouter(nom: nomCtrl.text, qte: int.tryParse(qteCtrl.text) ?? 0);
        if (context.mounted) {
          Navigator.pop(context);
          showAppToast(context, 'Article "${nomCtrl.text}" ajouté à l\'inventaire.');
        }
      }),
    ],
  );
}
```

**Règle de validation** (fidèle au pattern `.invalid-feedback` du prototype web) : l'erreur s'affiche **sous le champ concerné**, jamais uniquement en toast global — le toast confirme/informe, il ne remplace pas la validation de champ.

---

## 2. Modale "Modifier" — pré-remplissage obligatoire

Différence unique avec "Ajouter" : les contrôleurs sont initialisés avec les valeurs actuelles de l'item, jamais vides.

```dart
Future<void> ouvrirModaleModifier(BuildContext context, StockViewModel vm, Produit item) async {
  final nomCtrl = TextEditingController(text: item.nom); // PRE-REMPLI, jamais vide
  final qteCtrl = TextEditingController(text: item.stock.toString());
  // ... reste identique au pattern Ajouter, mais appelle vm.modifier(item.id, ...) a la sauvegarde
}
```

**Piège à éviter** (déjà rencontré et documenté sur ce projet côté web) : si le champ "identifiant/référence" est modifiable dans la modale (ex : code d'un lot d'incubation), **tout bouton d'action de la ligne qui référence l'ancien identifiant doit être mis à jour après sauvegarde** — sans quoi le bouton "Modifier" suivant pointe vers un identifiant qui n'existe plus. Ce bug a été identifié et corrigé sur `openEditIncubationModal`/`submitEditIncubation` du prototype web ; le code Dart équivalent doit soit ne jamais permettre la modification de l'identifiant primaire (option recommandée), soit gérer explicitement la réindexation.

---

## 3. Modale "Supprimer" — avertissement obligatoire, jamais de suppression directe

Voir `showDeleteWarningModal()` (Doc E2 section 2). **Règle absolue, sans exception** : aucun bouton de suppression n'appelle directement `repository.supprimer()` — il ouvre systématiquement cette modale de confirmation en premier (Strict Avoid, FRS-STK-03).

```dart
onPressed: () async {
  final confirme = await showDeleteWarningModal(context, itemName: item.nom);
  if (confirme) {
    await vm.supprimer(item.id);
    if (context.mounted) showAppToast(context, 'Article supprimé de l\'inventaire.', type: ToastType.warning);
  }
},
```

---

## 4. Modale d'Action Métier Spécifique (pattern Palpation/Mise Bas/Sevrage)

Certains écrans (Suivi Reproduction) ont des modales qui ne sont ni Ajouter/Modifier/Supprimer génériques, mais des **actions de cycle métier** — plusieurs panneaux dans une seule modale, affichés conditionnellement selon l'étape :

```dart
class ActionLapineModal extends StatefulWidget {
  const ActionLapineModal({super.key, required this.lapineNum, required this.action});
  final String lapineNum;
  final String action; // 'palpation' | 'misebas' | 'sevrage'

  @override
  State<ActionLapineModal> createState() => _ActionLapineModalState();
}
// build() affiche le panneau correspondant a widget.action uniquement —
// meme mecanisme que les 3 <div class="action-panel"> du prototype HTML,
// un seul visible a la fois selon l'action demandee.
```

---

## 5. Accessibilité des Modales (rappel de l'audit déjà mené sur AgriERP, à répliquer)

- Toute modale DOIT être annoncée comme telle aux technologies d'assistance : `Semantics(container: true, label: titreDeLaModale, child: ...)` — équivalent Dart de `role="dialog" aria-modal="true"` déjà appliqué côté web
- Le bouton de fermeture (×) DOIT avoir un `tooltip`/`Semantics.label` explicite ("Fermer"), jamais silencieux pour un lecteur d'écran
- Le focus doit être piégé dans la modale tant qu'elle est ouverte (`Dialog` de Flutter le fait nativement — vérifier que ce comportement n'est pas cassé par une implémentation `Overlay` personnalisée)

---

## 6. Récapitulatif — quand utiliser quelle modale

| Situation | Modale |
|---|---|
| Créer un nouvel enregistrement | Ajouter (section 1) |
| Corriger un enregistrement existant | Modifier (section 2) |
| Retirer définitivement un enregistrement | Supprimer avec avertissement (section 3) — **jamais** de suppression sans cette étape |
| Faire progresser un enregistrement dans son cycle métier (ex : palpation → mise bas → sevrage) | Modale d'action métier multi-panneaux (section 4) |
