; LogiALVIA - installateur Inno Setup 6.
; Appel : ISCC.exe /DVersion=1.0.0 /DEnvironnement=production /DNomInstallateur=LogiALVIA-Setup-1.0.0 /DDossierRelease=..\build\windows\x64\runner\Release installer\logialvia.iss
;
; REGLES :
;  - AppId : GUID propre a LogiALVIA, NE JAMAIS le changer apres la premiere livraison, ni reutiliser celui de LogiAgriERP.
;  - Le nom de societe / produit de windows\runner\Runner.rc (ALLMANY ET COMPAGNIE / LogiALVIA) fixe le dossier des donnees
;    du poste (%APPDATA%\ALLMANY ET COMPAGNIE\LogiALVIA) : ne plus les modifier une fois en service.

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
AppPublisher=Dr MASSENON Rhodes
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
// Une mise a jour ne touche jamais aux donnees : la base vit hors du dossier d'installation.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Donnees, Sauvegarde: String;
  Code: Integer;
begin
  if CurUninstallStep <> usUninstall then Exit;
  Donnees := ExpandConstant('{#DonneesPoste}');
  if not DirExists(Donnees) then Exit;
  if UninstallSilent then Exit; // jamais de suppression de donnees en silence
  if MsgBox('Supprimer aussi les donnees locales de LogiALVIA (ventes, fiches, comptabilite) ?' + #13#10 +
            'Les saisies non envoyees au serveur seraient PERDUES.', mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
  begin
    if MsgBox('Faire d''abord une sauvegarde dans Documents\LogiALVIA-Sauvegarde ?', mbConfirmation, MB_YESNO) = IDYES then
    begin
      Sauvegarde := ExpandConstant('{userdocs}\LogiALVIA-Sauvegarde-' + GetDateTimeString('yyyymmdd-hhnnss', '-', ':'));
      Exec(ExpandConstant('{cmd}'), '/C xcopy "' + Donnees + '" "' + Sauvegarde + '\" /E /I /Y /Q', '', SW_HIDE, ewWaitUntilTerminated, Code);
    end;
    DelTree(Donnees, True, True, True);
  end;
end;
