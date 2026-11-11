# PROMPT_INSTALLATEUR_WINDOWS_FLUTTER — Guide et prompt réutilisable : installateur Windows d'une application Flutter (Inno Setup)

> **L'installateur du dépôt fait foi** : `logialvia_app/installer/logialvia.iss` et `logialvia_app/build_windows.bat`. Ce document en est tiré (valeurs relevées le 2026-11-11) ; en cas d'écart, ces deux fichiers priment.
>
> **État** : `docs/logialvia/47w_INSTALLATEUR_WINDOWS.md` décrit l'installateur comme « **écrit, NON exécuté** » (environnement de développement Linux : ni Windows, ni Visual Studio, ni Inno Setup ; « premier essai à faire sur une machine Windows ») ; le commit `da1bc6d` (2026-11-10 00:56 `+0000`) porte le même aveu (« non exécuté »). Il n'existe **aucun fichier `RESTE_A_FAIRE`** dans le dépôt (recherche `find . -name 'RESTE_A_FAIRE*'` : aucun résultat) : la formulation à retenir est donc celle de `47w_`. **Tant que le propriétaire du produit n'a pas validé un essai sur Windows, ne pas présenter l'installateur comme éprouvé.**
>
> **Nuance à connaître** : la même note `47w_` contient une section « Durées constatées (poste du client, 2026-11-10) » (premier `build_runner` ≈ 6 min, 812 fichiers générés ; `flutter analyze` 3 à 4 min). Ces mesures montrent qu'un build a été lancé sur un poste Windows du client ; elles **ne prouvent pas** que l'étape Inno Setup ni l'installateur produit aient été exécutés, et le document ne le dit pas.

Documents liés : `47w_INSTALLATEUR_WINDOWS.md` (état), `CODE_DE_SECOURS_ADMINISTRATEUR.md` (l'outil de réinitialisation du mot de passe n'est pas livré par l'installateur), `logialvia_app/lib/core/database/reprise_dossier_precedent.dart` (piège du dossier de données).

## 1. Principe

Deux étapes, deux fichiers, aucun serveur de build :

1. `build_windows.bat` (à lancer depuis `logialvia_app\`) : lit la version dans `pubspec.yaml`, exécute `flutter pub get`, `dart run build_runner build`, `flutter analyze`, `flutter test --concurrency=2`, `flutter build windows --release`, copie les DLL du runtime Visual C++ à côté de l'exécutable, puis appelle `ISCC.exe`.
2. `installer/logialvia.iss` (Inno Setup 6) : empaquette **tout** le dossier `build\windows\x64\runner\Release`, crée les raccourcis, et protège les données locales à la désinstallation.

Sortie : `installer\Output\LogiALVIA-Setup-<version>[-<env>].exe`. Le suffixe d'environnement n'existe pas en production.

Choix de conception relevés dans les fichiers :
- **Les données ne sont jamais dans le dossier d'installation** : la base vit hors de `{app}`, donc une mise à jour (réinstallation par-dessus) ne les touche pas (commentaire du `.iss` : « Une mise à jour ne touche jamais aux données »).
- **Pas de `--dart-define` d'environnement** : l'adresse du serveur est saisie au poste à l'appairage ; l'environnement ne sert qu'à nommer l'installateur (`47w_`).
- **Aucune étape destructive en mode silencieux** : `UninstallSilent` sort sans rien supprimer.

## 2. Prérequis (poste de build Windows)

| Prérequis | Source |
|---|---|
| Flutter dans le `PATH` (Dart `^3.12.2`, Flutter `>= 3.41`, vérifié avec 3.47.9 selon `CLAUDE.md`) | `build_windows.bat`, `pubspec.yaml`, `CLAUDE.md` |
| Visual Studio 2022, charge de travail « Développement Desktop en C++ » | en-tête de `build_windows.bat` |
| Inno Setup 6 : `ISCC.exe` cherché dans `%ProgramFiles(x86)%\Inno Setup 6\`, puis `%ProgramFiles%\Inno Setup 6\`, puis `where ISCC.exe` | `build_windows.bat` |
| Pack de langue `French.isl` fourni avec Inno Setup (`compiler:Languages\French.isl`) | `[Languages]` du `.iss` |
| Icône `windows\runner\resources\app_icon.ico` (sinon erreur 3 ; la générer : `py outils\generer_icone.py`, depuis `logo\logo_logialvia.png`, Pillow requis) | `build_windows.bat`, `outils/generer_icone.py` |
| Runtime Visual C++ 2015-2022 x64 présent dans `%SystemRoot%\System32` (DLL `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`) | `build_windows.bat` |
| `version:` de `pubspec.yaml` au format strict `x.y.z+n` (actuellement `1.0.0+1`) | `build_windows.bat` |

Aucun job Windows n'existe dans `.github/workflows/` (`ci.yml`, `mysql.yml`, `performance.yml` : tous les jobs sont `runs-on: ubuntu-latest`) : l'installateur n'est jamais construit en CI.

## 3. Ce que fait `build_windows.bat`, étape par étape

Appel, depuis `logialvia_app\` :

```bash
.\build_windows.bat [--env dev|recette|production] [--rapide] [--sans-tests] [--sans-installateur]
```

(à lancer dans une invite de commandes Windows ; le bloc ci-dessus donne la syntaxe, pas un script Linux)

| Option | Effet |
|---|---|
| `--env` | `dev`, `recette` ou `production` (défaut `production`) ; autre valeur : code 2 |
| `--rapide` | saute `flutter analyze` **et** les tests ; **refusé en production** (code 2) |
| `--sans-tests` | saute seulement les tests |
| `--sans-installateur` | s'arrête après `flutter build windows --release` et la copie des DLL (dossier prêt : `build\windows\x64\runner\Release`) |

Contrôles avant tout, dans l'ordre : version lue par `findstr /b /c:"version:" pubspec.yaml` puis validée par l'expression `^x.y.z+n$` (une version comme `1.2.0-demo+3` est refusée) ; icône présente ; avertissement si `.fvmrc` existe (le fichier est absent du dépôt).

Les 6 étapes (numérotées dans la sortie du script) :

1. `flutter pub get`
2. `dart run build_runner build` (sans `--delete-conflicting-outputs`, alors que `CLAUDE.md` recommande cette option pour une modification de table Drift)
3. `flutter analyze`, sortie enregistrée dans `%TEMP%\logialvia_analyze.txt` ; **doit contenir « No issues found! »**, sinon échec
4. `flutter test --concurrency=2`
5. `flutter build windows --release`, contrôle de `logialvia_app.exe`, copie des trois DLL VC++ si absentes
6. `ISCC.exe /Qp "/DVersion=<x.y.z>" "/DEnvironnement=<env>" "/DNomInstallateur=LogiALVIA-Setup-<x.y.z>[-<env>]" "/DDossierRelease=..\build\windows\x64\runner\Release" installer\logialvia.iss`, puis contrôle de `installer\Output\<nom>.exe`

Codes de sortie : 0 succès ; 1 échec d'une étape (`:echec`) ; 2 option, environnement ou version invalide, `--rapide` en production ; 3 icône absente.

## 4. Leçons réelles (tirées du dépôt)

1. **Le dossier de données dépend de `Runner.rc`.** Sous Windows, `getApplicationSupportDirectory()` construit son chemin à partir de `CompanyName` et `ProductName` de l'exécutable. Valeurs actuelles de `windows\runner\Runner.rc` : `CompanyName` = « ALLMANY ET COMPAGNIE », `ProductName` = « LogiALVIA » → base `%APPDATA%\ALLMANY ET COMPAGNIE\LogiALVIA\logialvia.db` (nom de fichier : `RepriseDossierPrecedent.nomFichier`). Tant que ces champs valaient les valeurs par défaut de Flutter, la base vivait dans `%APPDATA%\com.example\logialvia_app\`. Les modifier déplace la base : l'application repart sur une base **vide**. `RepriseDossierPrecedent` copie (jamais ne déplace, ne remplace jamais une base existante) l'ancienne base au démarrage, mais **uniquement depuis `com.example\logialvia_app`**. Le `.iss` le rappelle : « ne plus [les] modifier une fois en service ».
2. **`AppId` : ne jamais le changer** après la première livraison, ni réutiliser celui d'un autre produit (le `.iss` cite LogiAgriERP). GUID de LogiALVIA : `EE2E70A6-4A58-4AE4-A58E-8F86599040EB` (écrit `{{EE2E70A6-...}` dans le fichier : l'accolade ouvrante est doublée, convention Inno Setup).
3. **Sauvegardes hors du dossier de données** : le poste les écrit dans `Documents\LogiALVIA\Sauvegardes` (`ServiceSauvegarde.sousDossier`), parce que le dossier de support « que la désinstallation efface » ne conviendrait pas. À la désinstallation, le `.iss` propose en plus une copie `Documents\LogiALVIA-Sauvegarde-<aaaammjj-hhnnss>`.
4. **Désinstallation prudente** : question 1 « Supprimer aussi les données locales (ventes, fiches, comptabilité) ? » (réponse par défaut **Non**), avec l'avertissement que les saisies non envoyées au serveur seraient **perdues** ; question 2 « Faire d'abord une sauvegarde ? » ; copie par `xcopy /E /I /Y /Q` ; puis `DelTree`. Jamais de suppression avec `UninstallSilent`.
5. **Runtime Visual C++** : sans les trois DLL à côté de l'exécutable, « un poste neuf ne démarre pas » (commentaire du `.bat`). Le script les copie depuis `System32` de la machine de build ou échoue avec le message d'installer le runtime.
6. **Analyse et tests sont obligatoires pour livrer** : `--rapide` est interdit en production (code 2). Un essai `--rapide` n'est qu'un build de vérification.
7. **Durées observées** (poste du client, 2026-11-10, `47w_`) : premier `build_runner` ≈ 6 min (812 fichiers) puis 10 à 90 s ; `flutter analyze` 3 à 4 min ; les tests s'y ajoutent. Conseils de `47w_` : exclure `C:\Projects`, le dossier Flutter et `%LOCALAPPDATA%\Pub\Cache` de l'analyse Windows Defender ; build sur SSD.
8. **Exécutable** : `logialvia_app.exe` (constante `Exe` du `.iss`, `OriginalFilename` de `Runner.rc`).
9. **Pas de signature** : aucun `SignTool` ni `SignedUninstaller` dans les fichiers (Windows SmartScreen peut avertir au premier lancement : constat général sur les installateurs non signés, non testé ici).
10. **L'outil de réinitialisation du mot de passe administrateur n'est pas livré** (`logialvia_app/outils/reinitialiser_mot_de_passe_admin.dart`) : ni le `.bat` ni le `.iss` ne le copient (`CODE_DE_SECOURS_ADMINISTRATEUR.md`).

## 5. Fichier `.iss` du dépôt (référence)

Contenu **réel** de `logialvia_app/installer/logialvia.iss` (relevé le 2026-11-11). Les sections et les valeurs à changer pour un autre produit sont indiquées après le bloc.

```text
; LogiALVIA - installateur Inno Setup 6.
; Appel : ISCC.exe /DVersion=1.0.0 /DEnvironnement=production /DNomInstallateur=LogiALVIA-Setup-1.0.0 /DDossierRelease=..\build\windows\x64\runner\Release installer\logialvia.iss

#ifndef Version
  #define Version "0.0.0"
#endif
#ifndef Environnement
  #define Environnement "production"
#endif
#ifndef NomInstallateur
  #define NomInstallateur "LogiALVIA-Setup-" + Version
#endif
#ifndef DossierRelease
  #define DossierRelease "..\build\windows\x64\runner\Release"
#endif

#define NomApp "LogiALVIA"
#define Exe "logialvia_app.exe"
#define DonneesPoste "{userappdata}\ALLMANY ET COMPAGNIE\LogiALVIA"

[Setup]
AppId={{EE2E70A6-4A58-4AE4-A58E-8F86599040EB}
AppName={#NomApp}
AppVersion={#Version}
AppPublisher=ALLMANY ET COMPAGNIE
DefaultDirName={autopf}\{#NomApp}
DefaultGroupName={#NomApp}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename={#NomInstallateur}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#Exe}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequired=admin

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "bureau"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "{#DossierRelease}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#NomApp}"; Filename: "{app}\{#Exe}"
Name: "{autodesktop}\{#NomApp}"; Filename: "{app}\{#Exe}"; Tasks: bureau

[Run]
Filename: "{app}\{#Exe}"; Description: "Lancer {#NomApp}"; Flags: nowait postinstall skipifsilent

[Code]
// (procédure CurUninstallStepChanged : voir §4 point 4 ; fichier complet dans le dépôt)
```

Écarts et points d'attention constatés dans ce fichier :
- `#define Environnement` est défini mais **jamais utilisé** dans le reste du script (le suffixe d'environnement n'est porté que par `NomInstallateur`, calculé par le `.bat`).
- `PrivilegesRequired=admin` et `DonneesPoste` en `{userappdata}` : quand une installation est élevée avec un **autre** compte administrateur, `{userappdata}` désigne le profil du compte élevé, pas forcément celui de l'utilisateur de la ferme. C'est une caractéristique générale d'Inno Setup, **à vérifier au premier essai** (la liste « À vérifier » de `47w_` cite déjà les droits administrateur et le chemin exact du dossier de données).
- La tâche « bureau » n'a pas de drapeau `unchecked` : d'après la documentation d'Inno Setup elle est donc **cochée par défaut** (à confirmer à l'essai) ; le libellé de la tâche est « Créer un raccourci sur le Bureau ».
- Pas de `[InstallDelete]`, pas de `[Registry]`, pas de vérification du runtime VC++ dans le `.iss` (elle se fait dans le `.bat`).

## 6. Ce qui n'existe pas (encore)

| Attendu pour un installateur « complet » | Réalité dans le dépôt | Procédure réelle |
|---|---|---|
| Exécution validée sur Windows | **Jamais** (`47w_` : écrit, non exécuté) | Premier essai à faire sur Windows ; liste « À vérifier » de `47w_` (§7 ci-dessous) |
| Job CI qui construit l'installateur | Absent (`.github/workflows/`) | Lancer `build_windows.bat` à la main |
| Signature de code | Absente | Livrer tel quel, ou signer hors dépôt |
| Adresse du serveur préremplie (`--dart-define`) | Absente par décision (« À ajouter si le client veut une adresse préremplie », `47w_`) | Saisie au poste à l'appairage (`BLUEPRINT_SYNCHRONISATION_POSTES.md` §3) |
| Mise à jour automatique | Absente | Réinstaller par-dessus ; les données ne sont pas touchées (le `.iss` n'a aucun `[InstallDelete]`) |
| Outil de réinitialisation du mot de passe dans l'installateur | Non livré | Technicien avec le SDK Dart et le dépôt (`CODE_DE_SECOURS_ADMINISTRATEUR.md`) |
| Fichier `.fvmrc` (version Flutter figée) | Absent ; le `.bat` n'avertit que s'il existe | Vérifier `flutter --version` (SDK `^3.12.2`) |
| Reprise de la base d'autres anciens emplacements | Une seule source connue : `com.example\logialvia_app` | Restaurer une sauvegarde `.sqlite` depuis l'onglet Sauvegardes |
| Tests de l'installateur | Aucun test ne référence `logialvia.iss` ni `build_windows.bat` | Contrôles manuels |

## 7. À vérifier au premier essai sur Windows (repris de `47w_`)

Chemin exact du dossier de données (`getApplicationSupportDirectory`), présence de `French.isl`, droits administrateur (`PrivilegesRequired=admin`), runtime VC++ sur un poste neuf, installation par-dessus une version précédente, comportement de la désinstallation (question de suppression des données, copie de sauvegarde, mode silencieux).

```bash
# Rappel : ces commandes se lancent sous Windows (invite de commandes), depuis logialvia_app\
.\build_windows.bat --env recette --rapide
.\build_windows.bat --env production
.\build_windows.bat --sans-installateur
```

## 8. Prompt réutilisable (à coller)

Le bloc suivant est construit sur les **vrais** fichiers. Remplacer les valeurs entre chevrons pour un autre produit Flutter Windows ; pour LogiALVIA, les valeurs réelles sont déjà indiquées en exemple.

```text
Tu construis l'installateur Windows d'une application Flutter desktop, avec un script batch (build_windows.bat) et un script Inno Setup 6 (installer\<produit>.iss). Réponds en français, de façon factuelle ; n'invente rien : si tu n'as pas pu exécuter une étape (pas de Windows, pas de Visual Studio, pas d'Inno Setup), écris "écrit, NON exécuté" dans ta réponse et dans la documentation.

CONTEXTE
- Application : <NomApp> (exemple : LogiALVIA) ; exécutable produit par Flutter : <exe>.exe (exemple : logialvia_app.exe).
- Raison sociale / produit dans windows\runner\Runner.rc : CompanyName "<Société>" (exemple : ALLMANY ET COMPAGNIE), ProductName "<NomApp>". Ces champs fixent le dossier des données (%APPDATA%\<Société>\<NomApp>) : ne plus les modifier une fois en service. Si tu les corriges sur un produit déjà livré, ajoute une reprise de l'ancienne base (copie, jamais déplacement ni écrasement), comme lib\core\database\reprise_dossier_precedent.dart.
- Les données (base SQLite) ne sont JAMAIS dans le dossier d'installation : une mise à jour ne les touche pas.
- Version lue dans pubspec.yaml, format strict x.y.z+n (exemple : 1.0.0+1) ; une version "-demo" est refusée en production.

FICHIER 1 - build_windows.bat (à lancer depuis la racine du projet Flutter)
- Options : --env dev|recette|production (défaut production), --rapide (saute analyze ET tests, INTERDIT en production, code 2), --sans-tests, --sans-installateur.
- Contrôles : version x.y.z+n (findstr + expression régulière), environnement valide, windows\runner\resources\app_icon.ico présent (sinon code 3, indiquer comment le générer), avertissement si .fvmrc existe.
- Six étapes numérotées : [1/6] flutter pub get ; [2/6] dart run build_runner build ; [3/6] flutter analyze (sortie sauvée dans %TEMP% ; doit contenir "No issues found!") ; [4/6] flutter test --concurrency=2 ; [5/6] flutter build windows --release puis contrôle de l'exe et copie de msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll depuis System32 si absentes (sinon erreur : installer le runtime Visual C++ 2015-2022 x64) ; [6/6] ISCC.exe /Qp "/DVersion=<x.y.z>" "/DEnvironnement=<env>" "/DNomInstallateur=<NomApp>-Setup-<x.y.z>[-<env>]" "/DDossierRelease=..\build\windows\x64\runner\Release" installer\<produit>.iss.
- ISCC cherché dans %ProgramFiles(x86)%\Inno Setup 6\, puis %ProgramFiles%\Inno Setup 6\, puis where ISCC.exe ; introuvable : erreur sauf --sans-installateur.
- Sortie : installer\Output\<NomApp>-Setup-<x.y.z>[-<env>].exe (pas de suffixe en production). Codes : 0 succès, 1 échec d'étape, 2 option/environnement/version invalide ou --rapide en production, 3 icône absente. Sortie console préfixée [INFO], [ERREUR], [OK], [ECHEC] ; chcp 65001.

FICHIER 2 - installer\<produit>.iss
- Paramètres de compilation avec valeurs par défaut (#ifndef) : Version, Environnement, NomInstallateur, DossierRelease.
- [Setup] : AppId = GUID PROPRE au produit, NE JAMAIS LE CHANGER après la première livraison ni réutiliser celui d'un autre produit (doubler l'accolade ouvrante : {{GUID}) ; AppName, AppVersion={#Version}, AppPublisher=<Société>, DefaultDirName={autopf}\<NomApp>, DisableProgramGroupPage=yes, OutputDir=Output, OutputBaseFilename={#NomInstallateur}, SetupIconFile=..\windows\runner\resources\app_icon.ico, UninstallDisplayIcon={app}\<exe>.exe, Compression=lzma2, SolidCompression=yes, ArchitecturesAllowed=x64compatible, ArchitecturesInstallIn64BitMode=x64compatible, WizardStyle=modern, PrivilegesRequired=admin.
- [Languages] french (compiler:Languages\French.isl) ; [Tasks] tâche « raccourci sur le Bureau » ; [Files] tout le dossier Release (recursesubdirs createallsubdirs ignoreversion) ; [Icons] groupe + Bureau ; [Run] lancer l'application après installation (nowait postinstall skipifsilent).
- [Code] : à la désinstallation seulement (CurUninstallStepChanged, étape usUninstall), si le dossier de données {userappdata}\<Société>\<NomApp> existe ET que la désinstallation n'est pas silencieuse : demander "Supprimer aussi les données locales ? Les saisies non envoyées au serveur seraient PERDUES." (réponse par défaut Non) ; si Oui, proposer une sauvegarde dans {userdocs}\<NomApp>-Sauvegarde-<aaaammjj-hhnnss> (xcopy /E /I /Y /Q) puis supprimer le dossier (DelTree). Ne JAMAIS supprimer de données en mode silencieux.

INTERDITS
- Changer l'AppId, la raison sociale ou le nom de produit d'une application déjà livrée sans reprise de la base.
- Copier l'AppId ou les chemins d'un autre produit.
- Écrire des données dans le dossier d'installation.
- Prétendre que l'installateur a été testé sans l'avoir exécuté sur Windows.
- Désactiver l'analyse ou les tests pour un livrable de production.

LIVRABLES
1. build_windows.bat et installer\<produit>.iss à la racine du projet Flutter.
2. Une note de documentation : statut honnête (exécuté ou non, sur quelle machine), prérequis, appel, étapes, contrôles bloquants, "À vérifier au premier essai" (chemin exact des données, French.isl, droits administrateur, runtime VC++ sur un poste neuf, installation par-dessus une version précédente, désinstallation).
3. Un tableau "Ce qui n'existe pas" (signature de code, CI Windows, mise à jour automatique, adresse du serveur préremplie...), avec la procédure réelle.

VALIDATION
- Sous Windows : .\build_windows.bat --env recette --rapide (build de vérification), puis .\build_windows.bat --env production ; installer, lancer, saisir une donnée, réinstaller par-dessus (la donnée doit subsister), désinstaller (répondre Non, puis Oui avec sauvegarde, puis tester /SILENT : rien ne doit être supprimé).
- Sans Windows : relire les deux fichiers, vérifier chaque valeur contre Runner.rc et pubspec.yaml, et le dire.
```
