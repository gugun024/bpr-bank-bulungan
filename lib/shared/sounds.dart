import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef _PlaySoundNative = ffi.Int32 Function(
    ffi.Pointer<pkgffi.Utf16> pszSound,
    ffi.Pointer<ffi.Void> hmod,
    ffi.Uint32 fdwSound);
typedef _PlaySoundDart = int Function(
    ffi.Pointer<pkgffi.Utf16> pszSound,
    ffi.Pointer<ffi.Void> hmod,
    int fdwSound);

/// Efek suara undian: FANFARE SAJA. Roll/kocokan dalam keadaan apa
/// pun SENYAP total — tidak ada suara tick sama sekali, termasuk
/// selama roll reveal. Satu-satunya suara acara adalah fanfare tepat
/// saat nomor pemenang mengunci di layar penonton ([playReveal]
/// menjadwalkannya di ujung roll visual 2,6 detik), plus putar manual
/// dari tombol Tes Suara ([fanfare]).
///
/// PEMUTARAN dilakukan dari window OPERATOR (engine utama). Alasan:
/// plugin audioplayers terbukti tidak bunyi di sub-window penonton
/// (desktop_multi_window) — padahal registrasi plugin-nya ada. Window
/// operator & penonton berada di PC + speaker yang sama, jadi suara
/// dari operator terdengar identik oleh penonton.
///
/// DUA JALUR PUTAR di Windows:
/// 1. Utama: plugin audioplayers (mode mediaPlayer) — untuk fanfare.
/// 2. Cadangan: API Windows langsung (winmm PlaySound via FFI) —
///    tidak tergantung plugin / Media Foundation sama sekali.
///    Dipakai OTOMATIS bila jalur utama gagal. PlaySound tanpa
///    antrean: bunyi baru memotong bunyi sebelumnya, berhenti ya
///    langsung senyap — dipakai juga untuk memotong fanfare.
///    Kegagalan jalur utama DILAPORKAN lewat [onError] +
///    [initMessage] agar terlihat di layar operator.
///
/// Catatan Windows: PlayerMode.lowLatency hanya untuk Android
/// (SoundPool); di Windows pakai mediaPlayer agar bunyi keluar.
class Sounds {
  Sounds._();

  /// Durasi roll visual penonton (slot roll di audience_app.dart —
  /// AnimationController 2600ms). [playReveal] menjadwalkan fanfare
  /// tepat di ujung durasi ini, saat nomor pemenang mengunci.
  static const Duration revealRollDuration = Duration(milliseconds: 2600);

  static AudioPool? _tickPool;
  static final AudioPlayer _fanfarePlayer = AudioPlayer();
  static bool _muted = false;
  static bool _poolFailed = false;
  static Object? _poolError;
  static Timer? _revealFanfareTimer;

  // --- Jalur cadangan winmm ---
  static bool _fallbackActive = false;
  static bool _fallbackFailed = false;
  static bool _audioBroken = false;
  static String? _initMessage;
  static String? _tickPath;
  static String? _fanfarePath;

  /// Hook pelaporan error — dipasang window operator agar error audio
  /// tampil sebagai SnackBar. Args: (sumber, error).
  static void Function(String source, Object error)? onError;

  /// True bila sedang memakai jalur cadangan Windows (winmm).
  static bool get usingFallback => _fallbackActive;

  /// True bila SEMUA jalur audio gagal.
  static bool get audioBroken => _audioBroken;

  /// Pesan hasil pemanasan (notice jalur cadangan / error), null = sehat.
  static String? get initMessage => _initMessage;

  /// Label jalur aktif untuk ditampilkan ke operator.
  static String get backendLabel => _audioBroken
      ? 'tidak tersedia'
      : _fallbackActive
          ? 'cadangan Windows (winmm)'
          : 'utama (audioplayers)';

  static void setMuted(bool v) {
    _muted = v;
    if (v) {
      // Fanfare reveal yang masih tertunda ikut dibatalkan — operator
      // membisukan berarti reveal ini tidak boleh bunyi sama sekali.
      _revealFanfareTimer?.cancel();
      _revealFanfareTimer = null;
      // Potong bunyi yang sedang jalan di jalur cadangan.
      if (_fallbackActive) _playWinmm(null);
    }
  }

  static bool get muted => _muted;

  /// Pemanasan audio: uji jalur utama (buat pool + putar uji senyap).
  /// Bila gagal di Windows, siapkan jalur cadangan winmm.
  /// Mengembalikan pesan (notice/error) atau null bila jalur utama sehat;
  /// pesan yang sama tersedia di [initMessage].
  static Future<String?> warmUp() async {
    // Di Windows siapkan selalu file WAV winmm sebagai cadangan
    // fanfare (lihat fanfare()).
    if (Platform.isWindows) await _prepareWinmm();
    final err = await _probePrimary();
    if (err == null) {
      _fallbackActive = false;
      _audioBroken = false;
      _initMessage = null;
      return null;
    }
    if (Platform.isWindows) {
      final werr = await _prepareWinmm();
      if (werr == null) {
        _fallbackActive = true;
        _audioBroken = false;
        _initMessage =
            'Audio utama gagal ($err) — memakai jalur cadangan Windows.';
        return _initMessage;
      }
      _audioBroken = true;
      _initMessage = 'Audio utama gagal ($err); cadangan gagal ($werr)';
      return _initMessage;
    }
    _audioBroken = true;
    _initMessage = err;
    return err;
  }

  /// Uji jalur utama saja: pool + putar fanfare volume 0.
  /// Null = sehat; selain itu teks error asli dari platform.
  static Future<String?> _probePrimary() async {
    await _ensureTickPool();
    if (_poolFailed) return 'AudioPool gagal dibuat: $_poolError';
    final p = AudioPlayer();
    try {
      await p.setVolume(0);
      await p.play(AssetSource('sounds/fanfare.wav'));
      await p.stop();
      return null;
    } catch (e) {
      return 'play: $e';
    } finally {
      await p.dispose();
    }
  }

  static Future<void> _ensureTickPool() async {
    if (_tickPool != null || _poolFailed) return;
    try {
      // PENTING: path audioplayers TANPA awalan 'assets/' — AudioCache
      // menambahkannya sendiri. 'assets/sounds/...' menjadi
      // 'assets/assets/sounds/...' dan file tidak ditemukan (bug lama
      // yang membuat semua suara bisu sejak awal).
      _tickPool = await AudioPool.createFromAsset(
        path: 'sounds/tick.wav',
        maxPlayers: 4,
        // mediaPlayer: kompatibel semua platform (lowLatency = Android saja).
        playerMode: PlayerMode.mediaPlayer,
      );
    } catch (e) {
      _poolFailed = true;
      _poolError = e;
      debugPrint('[Sounds] AudioPool gagal dibuat: $e');
      onError?.call('pool', e);
    }
  }

  /// Aktifkan jalur cadangan sekali saja; true bila siap dipakai.
  static Future<bool> _activateFallback() async {
    if (_fallbackActive) return true;
    if (_fallbackFailed || !Platform.isWindows) return false;
    final err = await _prepareWinmm();
    if (err == null) {
      _fallbackActive = true;
      return true;
    }
    _fallbackFailed = true;
    debugPrint('[Sounds] jalur cadangan gagal disiapkan: $err');
    return false;
  }

  /// Fanfare kemenangan — SATU-SATUNYA suara acara. Diputar oleh
  /// [playReveal] tepat saat nomor mengunci, dan langsung (instan)
  /// oleh tombol Tes Suara di operator.
  static Future<void> fanfare() async {
    if (_muted) return;
    if (_fallbackActive) {
      _playWinmm(_fanfarePath);
      return;
    }
    try {
      await _fanfarePlayer.play(AssetSource('sounds/fanfare.wav'));
    } catch (e) {
      debugPrint('[Sounds] fanfare gagal: $e');
      onError?.call('fanfare', e);
      if (await _activateFallback()) _playWinmm(_fanfarePath);
    }
  }

  // ---------- Pola putar untuk window operator ----------

  /// Urutan suara reveal pemenang: SENYAP total selama roll visual
  /// penonton ([revealRollDuration]), lalu fanfare tepat saat nomor
  /// mengunci. Tidak ada tick dalam bentuk apa pun.
  static void playReveal() {
    stopReveal();
    _revealFanfareTimer = Timer(revealRollDuration, () {
      _revealFanfareTimer = null;
      // Operator bisa membisukan selagi fanfare tertunda; setMuted
      // juga membatalkan timer ini — cek di sini sebagai pengaman.
      if (_muted) return;
      fanfare();
    });
  }

  /// Batalkan fanfare reveal yang masih tertunda DAN potong fanfare
  /// yang sedang bunyi di kedua jalur.
  static void stopReveal() {
    _revealFanfareTimer?.cancel();
    _revealFanfareTimer = null;
    // Potong fanfare jalur utama yang sedang bunyi.
    _fanfarePlayer.stop().catchError((_) => null);
    // Potong bunyi yang sedang jalan di jalur cadangan.
    if (Platform.isWindows) _playWinmm(null);
  }

  // ---------- Diagnostik ----------

  /// Uji pemutaran jalur UTAMA di engine ini (dipakai window penonton
  /// untuk lapor kesehatan audio ke operator). Null = sehat, selain
  /// itu teks error asli dari platform.
  static Future<String?> selfTest() => _probePrimary();

  // ---------- Jalur cadangan: winmm PlaySound (Windows) ----------

  /// Ekstrak WAV dari aset ke folder temp agar bisa diputar PlaySound.
  /// Null = siap; selain itu teks error.
  static Future<String?> _prepareWinmm() async {
    if (_tickPath != null && _fanfarePath != null) return null;
    try {
      final dir = await getTemporaryDirectory();
      _tickPath =
          await _extract('assets/sounds/tick.wav', dir, 'undian_tick.wav');
      _fanfarePath = await _extract(
          'assets/sounds/fanfare.wav', dir, 'undian_fanfare.wav');
      return null;
    } catch (e) {
      return 'ekstrak wav: $e';
    }
  }

  static Future<String> _extract(String asset, Directory dir, String name) async {
    final data = await rootBundle.load(asset);
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true);
    return f.path;
  }

  static ffi.DynamicLibrary? _winmmLib;
  static _PlaySoundDart? _playSoundFn;

  /// Putar file WAV lewat API Windows PlaySoundW (async). Path null =
  /// hentikan bunyi yang sedang jalan. PlaySound satu kanal: bunyi
  /// baru memotong bunyi sebelumnya — pas untuk fanfare cadangan.
  static bool _playWinmm(String? path) {
    try {
      _winmmLib ??= ffi.DynamicLibrary.open('winmm.dll');
      final fn = _playSoundFn ??= _winmmLib!
          .lookupFunction<_PlaySoundNative, _PlaySoundDart>('PlaySoundW');
      final nullPtr = ffi.Pointer<pkgffi.Utf16>.fromAddress(0);
      final nullMod = ffi.Pointer<ffi.Void>.fromAddress(0);
      if (path == null) {
        return fn(nullPtr, nullMod, 0) != 0;
      }
      // SND_ASYNC(0x1) | SND_NODEFAULT(0x2) | SND_FILENAME(0x20000)
      const flags = 0x0001 | 0x0002 | 0x00020000;
      final ptr = path.toNativeUtf16();
      try {
        return fn(ptr, nullMod, flags) != 0;
      } finally {
        pkgffi.malloc.free(ptr);
      }
    } catch (e) {
      debugPrint('[Sounds] winmm gagal: $e');
      return false;
    }
  }
}
