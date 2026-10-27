; Installer PT. BPR Bank Bulungan (aplikasi undian) — Inno Setup 6.
;
; Dipakai workflow .github/workflows/windows-release.yml:
;   1. Langkah "Build installer" mengganti __APP_VERSION__ dengan versi
;      dari pubspec.yaml (bagian X.Y.Z, tanpa +build).
;   2. ISCC.exe meng-compile script ini -> installer-output\PT-BPR-Bank-Bulungan-Setup.exe

#define AppExe "BPR_Bank_Bulungan.exe"
#define AppVersion "__APP_VERSION__"

; Instalasi per-pengguna (tanpa perlu hak admin): program terpasang di
; %LOCALAPPDATA%\Programs\PT. BPR Bank Bulungan, shortcut di Start Menu
; (+ opsional Desktop), dan uninstaller terdaftar di Settings > Apps.
; Data aplikasi (database, gambar hadiah) tetap di Documents seperti biasa
; karena aplikasi tidak menulis apa pun ke folder install-nya sendiri.

[Setup]
AppName=PT. BPR Bank Bulungan
AppVersion={#AppVersion}
AppVerName=PT. BPR Bank Bulungan {#AppVersion}
AppPublisher=PT. BPR Bank Bulungan
AppPublisherURL=
DefaultDirName={localappdata}\Programs\PT. BPR Bank Bulungan
DefaultGroupName=PT. BPR Bank Bulungan
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=installer-output
OutputBaseFilename=PT-BPR-Bank-Bulungan-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=PT. BPR Bank Bulungan
SetupMutex=PT-BPR-Bank-Bulungan-Setup

[Languages]
Name: "indonesian"; MessagesFile: "compiler:Languages\Indonesian.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat shortcut di Desktop"; GroupDescription: "Shortcut tambahan:"; Flags: unchecked

[Files]
; Seluruh hasil flutter build windows --release (exe + flutter_windows.dll
; + folder data/). Nama exe sudah diubah jadi BPR_Bank_Bulungan.exe oleh
; patch BINARY_NAME di workflow sebelum build.
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\PT. BPR Bank Bulungan"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\PT. BPR Bank Bulungan"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Jalankan PT. BPR Bank Bulungan"; Flags: nowait postinstall skipifsilent
