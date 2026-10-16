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

  test('validasi import: duplikat rekening & kupon tidak cocok', () {
    // Header: rekening | rekening lama | nama | alamat | saldo | kupon
    final preview = ImportPreview(
      ['rekening', 'rekening lama', 'nama', 'alamat', 'saldo', 'kupon'],
      [
        // baris 2: valid, kupon cocok (6.889.777 -> 68)
        [
          '01.13.097863.001',
          '01.13.097863.01',
          'fazli',
          'jl. Kamboja',
          '6.889.777',
          '68'
        ],
        // baris 3: duplikat rekening (beda format titik) -> ERROR
        ['0113097863001', '', 'fazli 2', '', '200.000', '2'],
        // baris 4: kupon file (5) != hitungan (190.000 -> 1) -> WARNING
        ['02.22.000001.001', '', 'budi', '', '190.000', '5'],
        // baris 5: saldo < 100rb -> 0 kupon, info saja
        ['03.33.000002.001', '', 'siti', '', '50.000', '0'],
        // baris 6: tanpa rekening -> dilewati
        ['', '', 'tanpa rekening', '', '1.000.000', '10'],
      ],
    );
    final m = ImportService.autoMap(preview.headers);
    expect(m.valid, isTrue);
    expect(m.kupon, 5);

    final v = ImportService.validateImport(preview, m);

    // Duplikat: 1 temuan, menunjuk baris 3 & baris pertama (2).
    expect(v.duplicates.length, 1);
    expect(v.duplicates.first.row, 3);
    expect(v.duplicates.first.message, contains('baris 2'));
    expect(v.hasErrors, isTrue);

    // Kupon mismatch: 1 temuan di baris 4.
    expect(v.mismatches.length, 1);
    expect(v.mismatches.first.row, 4);
    expect(v.mismatches.first.message, contains('file=5'));
    expect(v.mismatches.first.message, contains('hitungan=1'));

    // Ringkasan.
    expect(v.validAccounts, 4);
    expect(v.skippedEmpty, 1);
    expect(v.zeroCoupon, 1);
    expect(v.totalCoupons, 68 + 2 + 1); // duplikat ikut dihitung di preview
    expect(v.isClean, isFalse);
  });

  test('validasi import: file bersih lolos tanpa temuan', () {
    final preview = ImportPreview(
      ['rekening', 'nama', 'saldo'],
      [
        ['01.13.097863.001', 'fazli', '6.889.777'],
        ['02.22.000001.001', 'budi', '190.000'],
      ],
    );
    final m = ImportService.autoMap(preview.headers);
    final v = ImportService.validateImport(preview, m);
    expect(v.isClean, isTrue);
    expect(v.validAccounts, 2);
    expect(v.totalCoupons, 69);
  });

  test('recordWinner menolak hadiah yang sudah habis', () async {
    final db = DatabaseHelper.instance;
    await db.replaceAllAccounts([
      Account(
          rekening: '01.13.097863.001',
          rekeningLama: '',
          nama: 'fazli',
          alamat: '',
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
    ]);
    final prizeId =
        await db.insertPrize(const Prize(name: 'Sepeda', urutan: 1, qty: 1));
    final svc = DrawService();
    final acc1 = (await db.findByCoupon(1))!;
    final acc2 = (await db.findByCoupon(69))!;

    // Kuota 1: pemenang pertama lolos.
    await svc.recordWinner(
        couponNo: 1, accountId: acc1.id!, prizeId: prizeId, mode: 'manual');
    expect(await db.winnerCountForPrize(prizeId), 1);

    // Pemenang kedua untuk hadiah yang sama DITOLAK.
    await expectLater(
      svc.recordWinner(
          couponNo: 69, accountId: acc2.id!, prizeId: prizeId, mode: 'manual'),
      throwsA(isA<StateError>()),
    );
    expect(await db.winnerCountForPrize(prizeId), 1);
    expect((await db.findByCoupon(69))?.hasWon, isFalse);
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
