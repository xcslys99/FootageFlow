#define AppName "FootageFlow"
#ifndef AppVersion
  #define AppVersion "0.5.0"
#endif
#ifndef SourceDirectory
  #define SourceDirectory "..\..\.build\windows-stage"
#endif
#ifndef OutputDirectory
  #define OutputDirectory "..\..\dist\windows"
#endif

[Setup]
AppId={{6A0A5D63-5C64-4B92-A705-492A5B4FD9F1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=FootageFlow contributors
AppPublisherURL=https://github.com/xcslys99/FootageFlow
DefaultDirName={localappdata}\Programs\FootageFlow
DefaultGroupName=FootageFlow
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDirectory}
OutputBaseFilename=FootageFlow-Setup-{#AppVersion}-Windows-x64
SetupIconFile=..\FootageFlow.Windows\Assets\FootageFlow.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\FootageFlow.exe
LicenseFile=..\..\LICENSE
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "chinesetraditional"; MessagesFile: "compiler:Languages\ChineseTraditional.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDirectory}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\FootageFlow"; Filename: "{app}\FootageFlow.exe"
Name: "{autodesktop}\FootageFlow"; Filename: "{app}\FootageFlow.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\FootageFlow.exe"; Description: "Launch FootageFlow"; Flags: nowait postinstall skipifsilent
