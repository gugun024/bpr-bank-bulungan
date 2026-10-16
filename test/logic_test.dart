import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:undian_bank/core/database.dart';
import 'package:undian_bank/core/draw_service.dart';
import 'package:undian_bank/core/import_service.dart';
import 'package:undian_bank/core/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.debugDbPath = inMemoryDatabasePath;
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeForTest();
  });

  test('parse saldo Indonesia & hitung kupon', () {
    expect(ImportService.parseSaldo('6.889.777'), 6889777);
    expect(ImportService.parseSaldo('190.000'), 190000);
    expect(ImportService.parseSaldo('1.234.567.890'), 1234567890);
    expect(ImportService.parseSaldo(''), 0);
    expect(ImportService.kuponCount(6889777), 68);
    expect(ImportService.kuponCount(190000), 1);
    expect(ImportService.kuponCount(199999), 1);
    expect(ImportService.kuponCount(99999), 0);
    expect(ImportService.kuponCount(0), 0);
  });

  test('format & normalisasi nomor kupon', () {
    expect(Account.formatCoupon(68), '000068');
    expect(Account.formatCoupon(1), '000001');
    expect(DrawService.normalizeCouponInput('68'), 68);
    expect(DrawService.normalizeCouponInput('000068'), 68);
    expect(DrawService.normalizeCouponInput('  000123  '), 123);
    expect(DrawService.normalizeCouponInput('abc'), isNull);
    expect(DrawService.normalizeCouponInput('0'), isNull);
  });

  test('alur undian: import -> lookup -> menang -> eksklusi -> random',
      () async {
    final db = DatabaseHelper.instance;
    await db.replaceAllAccounts([]);

    Future<bool> hasWonCoupon(int coupon) async =>
        (await db.findByCoupon(coupon))?.hasWon ?? false;

    await db.replaceAllAccounts([
      Account(
          rekening: '01.13.097863.001',
          rekeningLama: '01.13.097863.01',
          nama: 'fazli',
          alamat: 'jl. Kamboja',
          saldo: 6889777,
          kuponCount: 68,
          couponStart: 1,
          couponEnd: 68),
      Account(
          rekening: '02.22.000001.001',
          rekeningLama: '',
          nama: 'budi',
          alamat: '',
          saldo: 190000,
          kuponCount: 1,
          couponStart: 69,
          couponEnd: 69),
      Account(
          rekening: '03.33.000002.001',
          rekeningLama: '',
          nama: 'siti',
          alamat: '',
          saldo: 50000,
          kuponCount: 0,
          couponStart: 0,
          couponEnd: 0),
    ]);
    expect(await db.countAccounts(), 3);
    expect(await db.totalCoupons(), 69);

    final svc = DrawService();
    final found = await svc.lookupCoupon(68);
    expect(found?.account.nama, 'fazli');
    expect((await svc.lookupCoupon(69))?.account.nama, 'budi');
    expect(await svc.lookupCoupon(70), isNull);
    expect(await svc.lookupCoupon(1), isNotNull);

    final prizeId =
        await db.insertPrize(const Prize(name: 'Kulkas', urutan: 1, qty: 2));
    await svc.recordWinner(
        couponNo: 5,
        accountId: found!.account.id!,
        prizeId: prizeId,
        mode: 'manual');
    expect(await hasWonCoupon(1), isTrue);

    // Kupon lain milik pemenang terdeteksi sudah menang.
    final again = await svc.lookupCoupon(42);
    expect(again?.account.hasWon, isTrue);

    // Random draw tidak pernah mengembalikan fazli.
    for (var i = 0; i < 20; i++) {
      final r = await svc.drawRandom();
      expect(r?.account.nama, 'budi');
    }

    // Undo: fazli bisa menang lagi.
    await db.undoLastWinner();
    expect(await hasWonCoupon(1), isFalse);

    // Riwayat & pool kosong.
    final found2 = await svc.lookupCoupon(69);
    await svc.recordWinner(
        couponNo: 69,
        accountId: found2!.account.id!,
        prizeId: prizeId,
        mode: 'random');
    final winners = await db.getWinners();
    expect(winners.length, 1);
    expect(winners.first.accountNama, 'budi');

    await svc.recordWinner(
        couponNo: 1,
        accountId: found.account.id!,
        prizeId: prizeId,
        mode: 'manual');
    expect(await svc.drawRandom(), isNull);
  });
}
