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

  /// operator → penonton: tampilkan info penolakan
  /// (kupon sudah pernah menang — opsional, dikontrol toggle operator).
  /// args: {coupon: String, nama: String, rekening: String,
  ///         hadiah: String, waktu: String}
  /// TIDAK memicu fanfare/confetti — murni tampilan peringatan.
  static const String showRejected = 'showRejected';

  /// audience → operator: window penonton disembunyikan (mis. Alt+F4).
  /// Tidak ada args.
  static const String audienceHidden = 'audienceHidden';

  /// operator → penonton: bisukan / nyalakan efek suara.
  /// args: {muted: bool}
  static const String audienceMute = 'audienceMute';

  static const String argCoupon = 'coupon';
  static const String argNama = 'nama';
  static const String argHadiah = 'hadiah';
  static const String argMuted = 'muted';
  static const String argRekening = 'rekening';
  static const String argWaktu = 'waktu';
}

/// Pengirim perintah ke window penonton (dipakai window operator).
/// Channel dua arah: operator juga menerima notifikasi dari penonton
/// (mis. penonton disembunyikan) via [initReceiver].
class AudienceChannel {
  AudienceChannel._();

  static final _channel = WindowMethodChannel(
    AudienceProtocol.channelName,
    mode: ChannelMode.bidirectional,
  );

  /// Nyalakan setelah window penonton berhasil dibuka.
  static bool enabled = false;

  /// Daftarkan penerima pesan dari window penonton. Dipanggil sekali
  /// saat aplikasi operator mulai.
  static Future<void> initReceiver(
      Future<void> Function(String method) onMessage) async {
    try {
      await _channel.setMethodCallHandler((call) async {
        await onMessage(call.method);
      });
    } catch (_) {
      // Gagal registrasi — status penonton tetap ditracking manual.
    }
  }

  static Future<void> send(String method, [Map<String, Object?>? args]) async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod(method, args);
    } catch (_) {
      // window penonton belum siap / sudah ditutup — abaikan
    }
  }
}
