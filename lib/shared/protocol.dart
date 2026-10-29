import 'package:desktop_multi_window/desktop_multi_window.dart';

/// Protokol komunikasi operator → penonton via WindowMethodChannel
/// 'undian_audience' (mode unidirectional: penonton yang handle,
/// operator yang invoke).
class AudienceProtocol {
  static const String channelName = 'undian_audience';

  static const String showIdle = 'showIdle';
  static const String startShuffle = 'startShuffle';
  static const String stopShuffle = 'stopShuffle';

  /// args: {coupon: String, nama: String, alamat: String, hadiah: String,
  ///         gambar: String}
  /// alamat ditampilkan di kartu nama pemenang (pembedaan nama yang sama);
  /// boleh kosong — baris alamat disembunyikan.
  /// gambar = path file gambar hadiah ('' = tanpa gambar).
  static const String showWinner = 'showWinner';

  /// args: {hadiah: String, gambar: String} — tampilkan hadiah yang
  /// sedang diundi (gambar boleh kosong).
  static const String showPrize = 'showPrize';

  /// operator → penonton: tampilkan info penolakan
  /// (kupon sudah pernah menang — opsional, dikontrol toggle operator).
  /// args: {coupon: String, nama: String, rekening: String,
  ///         hadiah: String, waktu: String}
  /// TIDAK memicu fanfare/confetti — murni tampilan peringatan.
  static const String showRejected = 'showRejected';

  /// operator → penonton: kupon tidak terdaftar di database.
  /// args: {coupon: String}
  /// Dipakai di undi manual: nomor keluar di depan penonton, operator
  /// wajib menyampaikan valid/tidaknya. Tanpa fanfare/confetti.
  static const String showNotFound = 'showNotFound';

  /// audience → operator: window penonton disembunyikan (mis. Alt+F4).
  /// Tidak ada args.
  static const String audienceHidden = 'audienceHidden';

  /// operator → penonton: bisukan / nyalakan efek suara.
  /// args: {muted: bool}
  static const String audienceMute = 'audienceMute';

  /// audience → operator: laporan hasil self-test audio di window
  /// penonton. args: {detail: String} — 'ok' bila jalur audio sehat,
  /// selain itu teks error asli dari platform.
  static const String soundReport = 'soundReport';

  /// audience → operator: laporan hasil usaha pindah display
  /// (auto-pindah layar penonton ke monitor kedua/TV).
  /// args: {detail: String} — ringkasan mudah dibaca, mis.
  /// "Display: 2, target: 2 @ (1920,0), pindah: ya".
  /// Dikirim SEKALI setelah usaha awal + retry selesai, agar kegagalan
  /// pindah tidak lagi bisu seperti sebelumnya.
  static const String displayReport = 'displayReport';

  static const String argCoupon = 'coupon';
  static const String argNama = 'nama';
  static const String argAlamat = 'alamat';
  static const String argGambar = 'gambar';
  static const String argHadiah = 'hadiah';
  static const String argMuted = 'muted';
  static const String argRekening = 'rekening';
  static const String argWaktu = 'waktu';
  static const String argDetail = 'detail';
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
  /// saat aplikasi operator mulai. Callback menerima nama method +
  /// arguments-nya (Map atau null).
  static Future<void> initReceiver(
      Future<void> Function(String method, Map? args) onMessage) async {
    try {
      await _channel.setMethodCallHandler((call) async {
        final args = (call.arguments as Map?)?.cast<String, Object?>();
        await onMessage(call.method, args);
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
