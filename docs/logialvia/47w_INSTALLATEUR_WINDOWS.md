# 47w — Installateur Windows (`build_windows.bat` + Inno Setup)

**Statut : écrit, NON exécuté** (environnement de développement Linux : ni Windows, ni Visual Studio, ni Inno Setup). Premier essai à faire sur une machine Windows.

Prérequis : Flutter dans le PATH, Visual Studio 2022 (« Développement Desktop en C++ »), Inno Setup 6.
Appel depuis `logialvia_app\` : `.\build_windows.bat [--env dev|recette|production] [--sans-tests] [--sans-installateur]`
Sortie : `installer\Output\LogiALVIA-Setup-<version>[-<env>].exe` (le suffixe d'environnement n'existe pas en production).

Étapes : pub get → build_runner → analyze (doit finir par « No issues found! ») → tests (`--concurrency=2`) → `flutter build windows --release` → runtime Visual C++ copié → ISCC.

Contrôles bloquants : version `x.y.z+n` lue dans `pubspec.yaml` (les versions `-demo` sont refusées) ; environnement dev/recette/production ; `app_icon.ico` présent ; DLL `msvcp140`, `vcruntime140`, `vcruntime140_1` ; Inno Setup trouvé (sauf `--sans-installateur`).

## Différences voulues avec LogiAgriERP
- `AppId` propre à LogiALVIA (GUID `EE2E70A6-4A58-4AE4-A58E-8F86599040EB`) : **ne jamais le changer** après la première livraison.
- **Pas de `--dart-define` d'environnement** : l'adresse du serveur est saisie au poste, à l'appairage (`preferences_poste`), il n'y a pas d'adresse par défaut à compiler. L'environnement ne sert ici qu'à nommer l'installateur. (À ajouter si le client veut une adresse préremplie.)
- Données du poste : `%APPDATA%\ALLMANY ET COMPAGNIE\LogiALVIA` (dérivé de `CompanyName`/`ProductName` de `Runner.rc`, à ne plus changer) ; sauvegardes applicatives : `Documents\LogiALVIA\Sauvegardes`.
- Une mise à jour ne touche pas aux données. La désinstallation demande confirmation avant de supprimer la base, propose une copie dans `Documents\LogiALVIA-Sauvegarde-<date>`, et ne supprime jamais rien en mode silencieux.

## À vérifier au premier essai
Chemin exact du dossier de données (`getApplicationSupportDirectory`), présence de `French.isl`, droits administrateur (`PrivilegesRequired=admin`), runtime VC++ sur un poste neuf, installation par-dessus une version précédente.
