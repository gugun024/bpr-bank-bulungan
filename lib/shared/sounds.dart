import 'package:audioplayers/audioplayers.dart';

/// Efek suara layar penonton: tick saat mengocok & fanfare saat pemenang
/// dikunci. Semua pemanggilan aman — gagal diam-diam bila plugin audio
/// belum siap (mis. sub-window tanpa registrasi plugin).
class Sounds {
  Sounds._();

  static AudioPool? _tickPool;
  static final AudioPlayer _fanfarePlayer = AudioPlayer();
  static bool _muted = false;

  static void setMuted(bool v) => _muted = v;

  static Future<void> _ensureTickPool() async {
    if (_tickPool != null) return;
    try {
      _tickPool = await AudioPool.createFromAsset(
        path: 'assets/sounds/tick.wav',
        maxPlayers: 4,
        playerMode: PlayerMode.lowLatency,
      );
    } catch (_) {}
  }

  /// Tick pendek — panggil tiap frame roll kocokan / slot.
  /// Tidak perlu di-await oleh pemanggil.
  static Future<void> tick() async {
    if (_muted) return;
    try {
      await _ensureTickPool();
      await _tickPool?.start(volume: 0.6);
    } catch (_) {}
  }

  /// Fanfare kemenangan — dipanggil sekali saat nomor dikunci.
  static Future<void> fanfare() async {
    if (_muted) return;
    try {
      await _fanfarePlayer.play(AssetSource('assets/sounds/fanfare.wav'));
    } catch (_) {}
  }
}
