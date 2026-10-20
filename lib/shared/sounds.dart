import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Efek suara undian: tick saat mengocok & fanfare saat pemenang dikunci.
///
/// PEMUTARAN dilakukan dari window OPERATOR (engine utama). Alasan:
/// plugin audioplayers terbukti tidak bunyi di sub-window penonton
/// (desktop_multi_window) — padahal registrasi plugin-nya ada. Window
/// operator & penonton berada di PC + speaker yang sama, jadi suara
/// dari operator terdengar identik oleh penonton.
///
/// Catatan Windows: PlayerMode.lowLatency hanya untuk Android
/// (SoundPool); di Windows pakai mediaPlayer agar bunyi keluar.
class Sounds {
  Sounds._();

  static AudioPool? _tickPool;
  static final AudioPlayer _fanfarePlayer = AudioPlayer();
  static bool _muted = false;
  static bool _poolFailed = false;
  static Timer? _shuffleTimer;
  static Timer? _revealTimer;

  /// Hook pelaporan error (dipakai window penonton untuk meneruskan
  /// hasil self-test / error ke operator). Args: (sumber, error).
  static void Function(String source, Object error)? onError;

  static void setMuted(bool v) => _muted = v;
  static bool get muted => _muted;

  /// Pemanasan audio — buat AudioPool lebih dulu agar tick pertama
  /// tidak delay. Mengembalikan teks error bila gagal, null bila OK.
  static Future<String?> warmUp() async {
    await _ensureTickPool();
    return _poolFailed ? 'AudioPool gagal dibuat' : null;
  }

  static Future<void> _ensureTickPool() async {
    if (_tickPool != null || _poolFailed) return;
    try {
      _tickPool = await AudioPool.createFromAsset(
        path: 'assets/sounds/tick.wav',
        maxPlayers: 4,
        // mediaPlayer: kompatibel semua platform (lowLatency = Android saja).
        playerMode: PlayerMode.mediaPlayer,
      );
    } catch (e) {
      _poolFailed = true;
      debugPrint('[Sounds] AudioPool gagal dibuat: $e');
      onError?.call('pool', e);
    }
  }

  /// Tick pendek — panggil tiap frame roll kocokan / slot.
  /// Tidak perlu di-await oleh pemanggil.
  static Future<void> tick() async {
    if (_muted) return;
    try {
      await _ensureTickPool();
      await _tickPool?.start(volume: 0.6);
    } catch (e) {
      debugPrint('[Sounds] tick gagal: $e');
      onError?.call('tick', e);
    }
  }

  /// Fanfare kemenangan — dipanggil sekali saat nomor dikunci.
  static Future<void> fanfare() async {
    if (_muted) return;
    try {
      await _fanfarePlayer.play(AssetSource('assets/sounds/fanfare.wav'));
    } catch (e) {
      debugPrint('[Sounds] fanfare gagal: $e');
      onError?.call('fanfare', e);
    }
  }

  // ---------- Pola putar untuk window operator ----------

  /// Tick berulang selama layar penonton ng-roll tanpa henti
  /// (mode random, sebelum Konfirmasi/Batal).
  static void startShuffleTicks() {
    stopShuffleTicks();
    _shuffleTimer =
        Timer.periodic(const Duration(milliseconds: 70), (_) => tick());
  }

  static void stopShuffleTicks() {
    _shuffleTimer?.cancel();
    _shuffleTimer = null;
  }

  /// Urutan suara reveal pemenang, meniru layar penonton: tick slot
  /// 2,6 detik yang melambat (easeOutQuart, 44 frame) lalu fanfare
  /// tepat saat nomor mengunci.
  static void playReveal() {
    stopReveal();
    final sw = Stopwatch()..start();
    var lastIdx = -1;
    _revealTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      final ms = sw.elapsedMilliseconds;
      if (ms >= 2600) {
        t.cancel();
        _revealTimer = null;
        fanfare();
        return;
      }
      // easeOutQuart: 1 - (1-x)^4
      final x = (ms / 2600).clamp(0.0, 1.0);
      final p = 1 - (1 - x) * (1 - x) * (1 - x) * (1 - x);
      final idx = (p * 44).floor();
      if (idx != lastIdx) {
        lastIdx = idx;
        tick();
      }
    });
  }

  static void stopReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
  }

  // ---------- Diagnostik ----------

  /// Uji pemutaran di engine INI: buat pool + putar fanfare sekali
  /// dengan volume 0 (tidak terdengar, tapi menjalankan jalur native
  /// penuh). Mengembalikan null bila semua OK, atau teks error asli
  /// dari platform (untuk ditampilkan ke operator).
  static Future<String?> selfTest() async {
    final warmErr = await warmUp();
    if (warmErr != null) return warmErr;
    final p = AudioPlayer();
    try {
      await p.setVolume(0);
      await p.play(AssetSource('assets/sounds/fanfare.wav'));
      await p.stop();
      return null;
    } catch (e) {
      return 'play: $e';
    } finally {
      await p.dispose();
    }
  }
}
