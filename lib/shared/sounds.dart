import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Efek suara layar penonton: tick saat mengocok & fanfare saat pemenang
/// dikunci.
///
/// Catatan Windows: PlayerMode.lowLatency hanya untuk Android (SoundPool);
/// di Windows pakai mediaPlayer agar bunyi keluar.
class Sounds {
  Sounds._();

  static AudioPool? _tickPool;
  static final AudioPlayer _fanfarePlayer = AudioPlayer();
  static bool _muted = false;
  static bool _poolFailed = false;

  static void setMuted(bool v) => _muted = v;

  /// Panggil sekali saat aplikasi penonton dibuka — pemanasan audio
  /// supaya tick pertama tidak delay/gagal.
  static Future<void> warmUp() async {
    await _ensureTickPool();
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
    }
  }

  /// Fanfare kemenangan — dipanggil sekali saat nomor dikunci.
  static Future<void> fanfare() async {
    if (_muted) return;
    try {
      await _fanfarePlayer.play(AssetSource('assets/sounds/fanfare.wav'));
    } catch (e) {
      debugPrint('[Sounds] fanfare gagal: $e');
    }
  }
}
