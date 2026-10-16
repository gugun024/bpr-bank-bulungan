import 'dart:math';

import 'database.dart';
import 'models.dart';

/// Hasil lookup / undian satu kupon.
class DrawResult {
  final int couponNo;
  final Account account;
  DrawResult(this.couponNo, this.account);
}

/// Logika undian: lookup kupon manual & random berbobot.
class DrawService {
  final _rand = Random.secure();

  /// Normalisasi input operator: "68" / "000068" / " 68 " → 68.
  static int? normalizeCouponInput(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final n = int.tryParse(digits);
    if (n == null || n <= 0) return null;
    return n;
  }

  /// Mode manual: cari pemilik nomor kupon.
  /// Mengembalikan null bila nomor tidak dikenal.
  Future<DrawResult?> lookupCoupon(int couponNo) async {
    final acc = await DatabaseHelper.instance.findByCoupon(couponNo);
    if (acc == null) return null;
    return DrawResult(couponNo, acc);
  }

  /// Mode random: pilih 1 nomor kupon acak dari pool eligible (berbobot).
  /// Mengembalikan null bila pool kosong.
  Future<DrawResult?> drawRandom() async {
    final eligible = await DatabaseHelper.instance.eligibleAccounts();
    if (eligible.isEmpty) return null;
    var total = 0;
    for (final a in eligible) {
      total += a.kuponCount;
    }
    if (total <= 0) return null;
    final r = _rand.nextInt(total) + 1; // 1..total
    var acc = 0;
    for (final a in eligible) {
      acc += a.kuponCount;
      if (r <= acc) {
        final couponNo = a.couponStart + (a.kuponCount - (acc - r)) - 1;
        return DrawResult(couponNo, a);
      }
    }
    return null;
  }

  /// Catat pemenang: insert winners + tandai rekening menang.
  /// Menolak (StateError) bila kuota hadiah sudah habis — pengaman
  /// lapis kedua selain dropdown yang menonaktifkan hadiah habis.
  Future<void> recordWinner({
    required int couponNo,
    required int accountId,
    required int prizeId,
    required String mode,
  }) async {
    final db = DatabaseHelper.instance;
    final prizes = await db.getPrizes();
    final prize = prizes.where((p) => p.id == prizeId).firstOrNull;
    if (prize == null) {
      throw StateError('Hadiah tidak ditemukan.');
    }
    final won = await db.winnerCountForPrize(prizeId);
    if (won >= prize.qty) {
      throw StateError('Hadiah "${prize.name}" sudah habis.');
    }
    await db.insertWinner(Winner(
      couponNo: couponNo,
      accountId: accountId,
      prizeId: prizeId,
      mode: mode,
      drawnAt: DateTime.now().toIso8601String(),
    ));
    await db.markWon(accountId);
  }
}
