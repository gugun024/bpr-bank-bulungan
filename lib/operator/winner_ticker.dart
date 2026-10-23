import '../core/database.dart';
import '../core/models.dart';

/// Bangun daftar nomor kupon untuk ticker "PEMENANG TERAKHIR" di
/// layar penonton: pemenang TERBARU dulu, maksimal 8 nomor.
///
/// Nomor diformat persis seperti argumen kupon showWinner di tab
/// manual/random: [Account.formatCoupon] dengan lebar = jumlah digit
/// total kupon, dibatasi 6–12. [DatabaseHelper.getWinners] sudah
/// terurut id DESC sehingga urutan terbaru-dulu tinggal diambil.
Future<List<String>> buildWinnerTicker(DatabaseHelper db) async {
  final winners = await db.getWinners();
  if (winners.isEmpty) return const [];
  final total = await db.totalCoupons();
  final width = total.toString().length.clamp(6, 12);
  return winners
      .take(8)
      .map((w) => Account.formatCoupon(w.couponNo, width))
      .toList();
}
