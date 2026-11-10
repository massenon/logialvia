# LogiALVIA

Logiciel de gestion intégrée (ERP de bureau, **hors-ligne**) d'**ALLMANY ET COMPAGNIE** :
élevage multi-filières, ventes et caisse, stocks et achats, comptabilité SYSCOHADA,
rapports et administration. Interface entièrement en français. Cible principale : Windows.

## Prérequis

- Flutter `>= 3.41` (Dart `^3.12.2`) — vérifié avec Flutter 3.47.9
- Windows : Visual Studio 2022 avec la charge « Développement Desktop en C++ »

## Démarrage

```bash
cd logialvia_app
flutter pub get
flutter run -d windows
```

## Qualité

```bash
flutter analyze        # doit rester à « No issues found! »
flutter test           # ~990 tests
```

Après toute modification d'une table Drift :

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Livraison

```bash
flutter build windows --release
```

Le résultat (`build/windows/…`) n'est pas versionné : publier l'archive via les
**Releases GitHub**.

## Manuel d'utilisation

Le manuel PDF (`docs/manuel/`) est généré à partir de captures produites par les tests.
Les tests n'y touchent pas par défaut ; pour le régénérer volontairement :

```bash
GENERER_MANUEL=1 flutter test test/manuel/captures_test.dart
dart run outils/generer_manuel.dart
```

## Documentation

Spécifications, architecture et règles métier : [`docs/INDEX_MAITRE.md`](../docs/INDEX_MAITRE.md).
Conventions du dépôt : [`CLAUDE.md`](../CLAUDE.md).
