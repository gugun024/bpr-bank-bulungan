# PT. BPR Bank Bulungan — Aplikasi Undian Berhadiah (Flutter Windows)

Aplikasi desktop Windows untuk menjalankan undian berhadiah bank:
- **Window Operator** (monitor utama): input kupon manual / kocok random, kelola hadiah, riwayat, import data
- **Window Penonton** (monitor kedua / proyektor, fullscreen): splash, animasi kocokan, pengumuman pemenang

## Cara dapat file .exe (otomatis via GitHub Actions) ⭐

Tidak perlu build manual di PC. Cukup push tag versi, GitHub akan build
dan membuat Release otomatis berisi `PT-BPR-Bank-Bulungan-windows.zip`:

```
git tag v1.0.0
git push origin v1.0.0
```

Tunggu beberapa menit di tab **Actions**, lalu unduh zip-nya di tab
**Releases**. Push biasa ke `main` juga otomatis di-build (hasilnya ada di
tab Actions > Artifacts, tanpa Release).

Isi zip: folder `Release/` — jalankan `undian_bank.exe` di dalamnya.
Folder tersebut portable (bisa dicopy ke flashdisk / PC lain).

## Cara build manual di PC Windows

1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (stable) dan
   jalankan `flutter doctor` sampai centang Windows Desktop.
2. Buka folder ini di terminal, generate runner Windows sekali saja:
   ```
   flutter create --platforms=windows .
   ```
3. **Wajib sekali saja** — daftarkan plugin untuk sub-window (layar penonton).
   Tanpa ini, window penonton tidak bisa fullscreen. Edit file
   `windows/runner/flutter_window.cpp`:
   - Tambahkan include di bagian atas:
     ```cpp
     #include "desktop_multi_window/desktop_multi_window_plugin.h"
     ```
   - Di dalam method `OnCreate()`, tepat setelah baris
     `RegisterPlugins(flutter_controller_->engine());` tambahkan:
     ```cpp
     DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
       auto* flutter_view_controller =
           reinterpret_cast<flutter::FlutterViewController*>(controller);
       auto* registry = flutter_view_controller->engine();
       RegisterPlugins(registry);
     });
     ```
4. Ambil package:
   ```
   flutter pub get
   ```
4. Jalankan:
   ```
   flutter run -d windows
   ```
5. Untuk file .exe rilis:
   ```
   flutter build windows
   ```
   Hasilnya di `build\windows\x64\runner\Release\`.

## Alur pakai

1. Tab **Import Data** → pilih file Excel/CSV → petakan kolom → Import.
   Kupon dihitung otomatis: `floor(saldo / 100.000)`, dinomori global 6 digit (000001, 000002, …).
2. Tab **Hadiah** → tambah daftar hadiah yang diundi.
3. Klik **Buka Layar Penonton** → geser window penonton ke monitor kedua/proyektor
   (otomatis fullscreen).
4. **Undi Manual**: ketik nomor kupon dari alat roll → validasi → pilih hadiah → Tampilkan.
   Kupon milik pemenang lama otomatis **ditolak**.
5. **Undi Random**: pilih hadiah → Kocok (animasi di layar penonton) → Konfirmasi & Tampilkan.
   Pool = kupon milik rekening yang belum pernah menang (berbobot otomatis).
6. Tab **Riwayat**: daftar pemenang, export CSV, batalkan undian terakhir.

## Catatan

- Database SQLite tersimpan di folder Documents pengguna (`undian_bank.db`).
- Satu rekening hanya bisa menang 1x — seluruh kuponnya hangus setelah menang.
- Import baru akan me-reset data rekening & riwayat undian.
