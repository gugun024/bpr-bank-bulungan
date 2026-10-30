; Installer PT. BPR Bank Bulungan (aplikasi undian) — Inno Setup 6.
;
; Dipakai workflow .github/workflows/windows-release.yml:
;   1. Workflow mengunduh vc_redist.x64.exe ke installer/redist/
;      (Visual C++ Redistributable, agar installer bisa memasangnya
;      otomatis bila belum ada di PC target).
;   2. Langkah "Build installer" mengganti __APP_VERSION__ dengan versi
;      dari pubspec.yaml (bagian X.Y.Z, tanpa +build).
;   3. ISCC.exe meng-compile script ini -> installer-output\PT-BPR-Bank-Bulungan-Setup.exe
;
; Build lokal manual: unduh https://aka.ms/vs/17/release/vc_redist.x64.exe
; ke installer/redist/ sebelum menjalankan ISCC, kalau tidak compile gagal.

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
OutputDir={#SourcePath}\..\installer-output
OutputBaseFilename=PT-BPR-Bank-Bulungan-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=PT. BPR Bank Bulungan
SetupMutex=PT-BPR-Bank-Bulungan-Setup

[Languages]
; Bahasa wizard = Inggris (bawaan). Indonesian.isl tidak tersedia di
; instalasi Inno Setup runner, jadi jangan pakai "indonesian" di sini.
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat shortcut di Desktop"; GroupDescription: "Shortcut tambahan:"; Flags: unchecked

[Files]
; Seluruh hasil flutter build windows --release (exe + flutter_windows.dll
; + folder data/). Nama exe sudah diubah jadi BPR_Bank_Bulungan.exe oleh
; patch BINARY_NAME di workflow sebelum build.
; Path sumber juga relatif ke lokasi script, jadi pakai {#SourcePath}
; (folder installer/) + naik satu level ke root repo.
Source: "{#SourcePath}\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Visual C++ Redistributable (x64) — diunduh workflow CI ke installer/redist/
; sebelum compile. Diekstrak ke {tmp} hanya bila dibutuhkan
; (Check: NeedsVCRedist), dihapus otomatis setelah instalasi selesai.
Source: "{#SourcePath}\redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedsVCRedist

[Icons]
Name: "{group}\PT. BPR Bank Bulungan"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\PT. BPR Bank Bulungan"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Pasang Microsoft Visual C++ Redistributable (x64) otomatis bila belum ada
; atau versinya terlalu lama (Check: NeedsVCRedist). Perlu hak admin, jadi
; vc_redist akan memunculkan UAC sendiri saat dijalankan — aplikasi utama
; tetap terpasang per-pengguna tanpa admin.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang Microsoft Visual C++ Redistributable..."; Flags: waituntilterminated; Check: NeedsVCRedist
Filename: "{app}\{#AppExe}"; Description: "Jalankan PT. BPR Bank Bulungan"; Flags: nowait postinstall skipifsilent

[Code]
{ Cek apakah Visual C++ Redistributable 2015-2022 (x64) sudah terpasang dan
  versinya cukup baru. True = perlu dipasang / di-upgrade.
  Registry: HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64
  (Installed=1, Version='v14.XX.xxxxx'). Cukup bila minor >= 30 (VS 2022). }
function NeedsVCRedist(): Boolean;
var
  Installed: Cardinal;
  Version: String;
  P1, P2: Integer;
  Minor: Integer;
begin
  Result := True;
  if not RegQueryDWordValue(HKLM,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed', Installed) then Exit;
  if Installed <> 1 then Exit;
  if not RegQueryStringValue(HKLM,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Version', Version) then
  begin
    Result := False;
    Exit;
  end;
  { Version = 'v14.XX.xxxxx' -> ambil XX sebagai angka. }
  P1 := Pos('.', Version);
  if P1 = 0 then Exit;
  P2 := Pos('.', Copy(Version, P1 + 1, Length(Version)));
  if P2 = 0 then Exit;
  Minor := StrToIntDef(Copy(Version, P1 + 1, P2 - 1), 0);
  Result := Minor < 30;
end;
