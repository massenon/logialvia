@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
rem ============================================================================
rem  LogiALVIA - construction de l'installateur Windows (Flutter + Inno Setup 6)
rem  Usage :  build_windows.bat [--env dev|recette|production] [--rapide] [--sans-tests] [--sans-installateur]
rem  --rapide = saute analyze ET tests (build de verification, a ne pas livrer en production)
rem  Sortie : installer\Output\LogiALVIA-Setup-<version>[-<env>].exe
rem  Prerequis : Flutter dans le PATH, Visual Studio 2022 (Developpement Desktop en C++), Inno Setup 6.
rem ============================================================================
cd /d "%~dp0"

set "ENV=production"
set "SANS_TESTS=0"
set "RAPIDE=0"
set "SANS_INSTALLATEUR=0"

:args
if "%~1"=="" goto args_fin
if /i "%~1"=="--env" ( set "ENV=%~2" & shift & shift & goto args )
if /i "%~1"=="--rapide" ( set "RAPIDE=1" & set "SANS_TESTS=1" & shift & goto args )
if /i "%~1"=="--sans-tests" ( set "SANS_TESTS=1" & shift & goto args )
if /i "%~1"=="--sans-installateur" ( set "SANS_INSTALLATEUR=1" & shift & goto args )
echo [ERREUR] Option inconnue : %~1
exit /b 2
:args_fin

if /i not "%ENV%"=="dev" if /i not "%ENV%"=="recette" if /i not "%ENV%"=="production" (
  echo [ERREUR] Environnement invalide : "%ENV%" ^(dev, recette ou production^).
  exit /b 2
)

if "%RAPIDE%"=="1" if /i "%ENV%"=="production" (
  echo [ERREUR] --rapide est interdit en production : analyse et tests obligatoires avant livraison.
  exit /b 2
)

rem --- Version lue dans pubspec.yaml (x.y.z+n) -------------------------------
set "VERSION_COMPLETE="
for /f "tokens=2" %%v in ('findstr /b /c:"version:" pubspec.yaml') do set "VERSION_COMPLETE=%%v"
if not defined VERSION_COMPLETE ( echo [ERREUR] Version introuvable dans pubspec.yaml. & exit /b 2 )
for /f "tokens=1 delims=+" %%a in ("%VERSION_COMPLETE%") do set "VERSION=%%a"
echo %VERSION_COMPLETE%| findstr /r /c:"^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*+[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo [ERREUR] Version "%VERSION_COMPLETE%" : format attendu x.y.z+n ^(une version de demonstration comme 1.2.0-demo+3 est refusee en production^).
  exit /b 2
)
echo [INFO] LogiALVIA %VERSION_COMPLETE% - environnement %ENV%

rem --- Icone et runtime Visual C++ ------------------------------------------
if not exist "windows\runner\resources\app_icon.ico" (
  echo [ERREUR] windows\runner\resources\app_icon.ico absente. La generer : py outils\generer_icone.py
  exit /b 3
)

rem --- Version de Flutter : simple avertissement -----------------------------
if exist ".fvmrc" (
  echo [INFO] Version Flutter figee dans .fvmrc : verifier qu'elle correspond a `flutter --version`.
)

echo.
echo [1/6] flutter pub get
call flutter pub get || goto echec

echo.
echo [2/6] dart run build_runner build
call dart run build_runner build || goto echec

echo.
if "%RAPIDE%"=="1" (
  echo [3/6] flutter analyze ignore ^(--rapide^)
  goto apres_analyze
)
echo [3/6] flutter analyze
call flutter analyze > "%TEMP%\logialvia_analyze.txt" 2>&1
type "%TEMP%\logialvia_analyze.txt"
rem Pas de "!" dans le motif : avec EnableDelayedExpansion il est supprime et la recherche echoue toujours.
findstr /c:"No issues found" "%TEMP%\logialvia_analyze.txt" >nul
if errorlevel 1 ( echo [ERREUR] flutter analyze doit finir par "No issues found!". & goto echec )
:apres_analyze

echo.
if "%SANS_TESTS%"=="1" (
  echo [4/6] Tests ignores ^(--sans-tests^)
) else (
  echo [4/6] flutter test --concurrency=2
  call flutter test --concurrency=2 || goto echec
)

echo.
echo [5/6] flutter build windows --release
call flutter build windows --release "--dart-define=LOGIALVIA_ENV=%ENV%" || goto echec
set "REL=build\windows\x64\runner\Release"
if not exist "%REL%\logialvia_app.exe" ( echo [ERREUR] %REL%\logialvia_app.exe introuvable. & goto echec )

rem Runtime Visual C++ a cote de l'executable : sinon un poste neuf ne demarre pas.
for %%d in (msvcp140.dll vcruntime140.dll vcruntime140_1.dll) do (
  if not exist "%REL%\%%d" (
    if exist "%SystemRoot%\System32\%%d" (
      copy /y "%SystemRoot%\System32\%%d" "%REL%\" >nul
    ) else (
      echo [ERREUR] %%d absente de System32 : installer le runtime Visual C++ 2015-2022 x64 sur la machine de build.
      goto echec
    )
  )
)

echo.
if "%SANS_INSTALLATEUR%"=="1" (
  echo [6/6] Installateur ignore ^(--sans-installateur^). Dossier pret : %REL%
  goto fin
)
echo [6/6] Inno Setup
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not defined ISCC for /f "delims=" %%i in ('where ISCC.exe 2^>nul') do if not defined ISCC set "ISCC=%%i"
if not defined ISCC (
  echo [ERREUR] Inno Setup 6 introuvable. L'installer, ou relancer avec --sans-installateur.
  goto echec
)

set "SUFFIXE="
if /i not "%ENV%"=="production" set "SUFFIXE=-%ENV%"
set "NOM_SETUP=LogiALVIA-Setup-%VERSION%%SUFFIXE%"

"%ISCC%" /Qp "/DVersion=%VERSION%" "/DEnvironnement=%ENV%" "/DNomInstallateur=%NOM_SETUP%" "/DDossierRelease=..\%REL%" installer\logialvia.iss || goto echec
if not exist "installer\Output\%NOM_SETUP%.exe" ( echo [ERREUR] installer\Output\%NOM_SETUP%.exe non produit. & goto echec )

:fin
echo.
echo [OK] Termine.
if not "%SANS_INSTALLATEUR%"=="1" echo      Installateur : installer\Output\%NOM_SETUP%.exe
exit /b 0

:echec
echo.
echo [ECHEC] Construction interrompue.
exit /b 1
