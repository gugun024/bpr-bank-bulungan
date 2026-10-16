import 'package:desktop_multi_window/desktop_multi_window.dart';

/// Protokol komunikasi operator → penonton via WindowMethodChannel
/// 'undian_audience' (mode unidirectional: penonton yang handle,
/// operator yang invoke).
class AudienceProtocol {
  static const String channelName = 'undian_audience';

  static const String showIdle = 'showIdle';
  static const String startShuffle = 'startShuffle';
  static const String stopShuffle = 'stopShuffle';

  /// args: {coupon: String, nama: String, hadiah: String}
  static const String showWinner = 'showWinner';

  /// args: {hadiah: String} — tampilkan hadiah yang sedang diundi
  static const String showPrize = 'showPrize';

  static const String argCoupon = 'coupon';
  static const String argNama = 'nama';
  static const String argHadiah = 'hadiah';
}

/// Pengirim perintah ke window penonton (dipakai window operator).
class AudienceChannel {
  AudienceChannel._();

  static const _channel = WindowMethodChannel(
    AudienceProtocol.channelName,
    mode: ChannelMode.unidirectional,
  );

  /// Nyalakan setelah window penonton berhasil dibuka.
  static bool enabled = false;

  static Future<void> send(String method, [Map<String, Object?>? args]) async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod(method, args);
    } catch (_) {
      // window penonton belum siap / sudah ditutup — abaikan
    }
  }
}
