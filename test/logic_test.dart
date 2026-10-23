import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:undian_bank/audience/audience_app.dart';
import 'package:undian_bank/core/coupon_export.dart';
import 'package:undian_bank/core/database.dart';
import 'package:undian_bank/core/draw_service.dart';
import 'package:undian_bank/core/import_service.dart';
import 'package:undian_bank/core/models.dart';
import 'package:undian_bank/operator/tabs/data_tab.dart';
import 'package:undian_bank/operator/tabs/history_tab.dart';

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
    // Format Inggris (koma = ribuan) — dipakai file kupon_SIMAPAN.csv.
    expect(ImportService.parseSaldo('6,889,777'), 6889777);
    expect(ImportService.parseSaldo('190,000'), 190000);
    expect(ImportService.parseSaldo('1,234,567,890'), 1234567890);
    // Campuran + desimal selalu dibuang.
    expect(ImportService.parseSaldo('6.889.777,00'), 6889777);
    expect(ImportService.parseSaldo('6,889,777.00'), 6889777);
    expect(ImportService.parseSaldo('6889777'), 6889777);
    expect(ImportService.parseSaldo('6889,77'), 6889);
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

  test('autoMap mengenali header singkatan Rek. Lama', () {
    final m = ImportService.autoMap(
        ['No', 'Rekening', 'Rek. Lama', 'Nama', 'Alamat', 'Saldo', 'Kupon']);
    expect(m.rekening, 1);
    expect(m.rekeningLama, 2);
    expect(m.nama, 3);
    expect(m.alamat, 4);
    expect(m.saldo, 5);
    expect(m.kupon, 6);
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

  test('skala responsif layar penonton', () {
    // 1080p fullscreen -> 1.0 (tidak berubah dari desain awal)
    expect(audienceScaleFor(const Size(1920, 1080)), 1.0);
    // Proyektor 720p -> mengecil proporsional
    expect(audienceScaleFor(const Size(1280, 720)), closeTo(0.6667, 0.001));
    // Laptop 1366x768 -> ikut sisi terkecil
    expect(audienceScaleFor(const Size(1366, 768)), closeTo(0.7111, 0.001));
    // 4K -> dibatasi 1.6
    expect(audienceScaleFor(const Size(3840, 2160)), 1.6);
    // Jendela sangat kecil -> dibatasi 0.5
    expect(audienceScaleFor(const Size(800, 600)), 0.5);
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

  test('paginasi & pencarian Data Nasabah', () async {
    final db = DatabaseHelper.instance;
    await db.replaceAllAccounts([
      for (var i = 0; i < 5; i++)
        Account(
            rekening: '01.13.00000$i.00',
            rekeningLama: '',
            nama: i == 3 ? 'Budi Santoso' : 'Nasabah $i',
            alamat: '',
            saldo: (i + 1) * 100000,
            kuponCount: i + 1,
            couponStart: i * 10 + 1,
            couponEnd: (i + 1) * 10),
    ]);

    expect(await db.countAccountsFiltered(''), 5);
    expect(await db.countAccountsFiltered('budi'), 1);
    expect(await db.countAccountsFiltered('01.13.000002'), 1);
    expect(await db.countAccountsFiltered('tidak-ada'), 0);

    final p1 = await db.getAccountsPage(limit: 2, offset: 0);
    final p2 = await db.getAccountsPage(limit: 2, offset: 2);
    final p3 = await db.getAccountsPage(limit: 2, offset: 4);
    expect(p1.length, 2);
    expect(p2.length, 2);
    expect(p3.length, 1);
    // Urut mengikuti nomor kupon, tidak ada yang terlewat/ganda.
    final all = [...p1, ...p2, ...p3].map((a) => a.rekening).toList();
    expect(all.toSet().length, 5);

    final cari = await db.getAccountsPage(
        limit: 10, offset: 0, query: 'santoso');
    expect(cari.length, 1);
    expect(cari.first.nama, 'Budi Santoso');
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

  test('settings: simpan & baca preferensi toggle', () async {
    final db = DatabaseHelper.instance;
    // Belum pernah disimpan → null.
    expect(await db.getSetting('show_rejected_on_audience'), isNull);
    // Simpan & baca kembali.
    await db.setSetting('show_rejected_on_audience', '1');
    expect(await db.getSetting('show_rejected_on_audience'), '1');
    // Update nilai.
    await db.setSetting('show_rejected_on_audience', '0');
    expect(await db.getSetting('show_rejected_on_audience'), '0');
    // Key lain tidak terganggu.
    expect(await db.getSetting('tidak_ada'), isNull);
  });

  test('gambar hadiah: kolom image_path + setPrizeImage', () async {
    final db = DatabaseHelper.instance;
    final id = await db.insertPrize(
        Prize(name: 'Kulkas', urutan: 0, qty: 1, imagePath: '/tmp/a.png'));
    var prizes = await db.getPrizes();
    expect(prizes.singleWhere((p) => p.id == id).imagePath, '/tmp/a.png');

    await db.setPrizeImage(id, '/gambar/hadiah_1.jpg');
    prizes = await db.getPrizes();
    expect(prizes.singleWhere((p) => p.id == id).imagePath,
        '/gambar/hadiah_1.jpg');

    await db.setPrizeImage(id, '');
    prizes = await db.getPrizes();
    expect(prizes.singleWhere((p) => p.id == id).imagePath, '');

    // Default: tanpa gambar.
    final id2 = await db.insertPrize(Prize(name: 'TV', urutan: 1, qty: 1));
    prizes = await db.getPrizes();
    expect(prizes.singleWhere((p) => p.id == id2).imagePath, '');
  });

  test('import hadiah: autoMap + buildPrizes + replaceAllPrizes', () async {
    // AutoMap mengenali header Indonesia/Inggris.
    var m = PrizeImportService.autoMap(['Nama Hadiah', 'Jumlah']);
    expect(m.nama, 0);
    expect(m.qty, 1);
    m = PrizeImportService.autoMap(['prize', 'qty']);
    expect(m.nama, 0);
    expect(m.qty, 1);
    // Fallback: 2 kolom tanpa header dikenali.
    m = PrizeImportService.autoMap(['A', 'B']);
    expect(m.nama, 0);
    expect(m.qty, 1);

    // buildPrizes: baris tanpa nama dilewati, qty invalid → 1.
    final preview = ImportPreview(
      ['nama', 'qty'],
      [
        ['Sepeda', '6'],
        ['Kulkas', '2'],
        ['', '5'], // tanpa nama → dilewati
        ['TV', 'abc'], // qty invalid → 1
        ['Motor', '0'], // qty 0 → 1
      ],
    );
    final prizes = PrizeImportService.buildPrizes(
        preview, PrizeColumnMapping(nama: 0, qty: 1));
    expect(prizes.length, 4);
    expect(prizes[0].name, 'Sepeda');
    expect(prizes[0].qty, 6);
    expect(prizes[2].qty, 1);
    expect(prizes[3].qty, 1);

    // replaceAllPrizes: mengganti seluruh daftar, urutan 1-based.
    final db = DatabaseHelper.instance;
    await db.replaceAllPrizes(prizes);
    final saved = await db.getPrizes();
    expect(saved.length, 4);
    expect(saved[0].name, 'Sepeda');
    expect(saved[0].urutan, 1);
    expect(saved[3].urutan, 4);
    // countWinners = 0 (belum ada undian).
    expect(await db.countWinners(), 0);
  });

  test('parseFile CSV: fallback latin1 bila bukan UTF-8', () async {
    // Simulasi CSV simpanan Excel Indonesia (Windows-1252): byte 0xE9
    // ("é") tidak valid sebagai UTF-8.
    final dir = await Directory.systemTemp.createTemp('csv_test');
    final path = '${dir.path}/hadiah.csv';
    final bytes = <int>[
      ...utf8.encode('nama,qty\n'),
      ...latin1.encode('Kipas Anginé,3\n'),
    ];
    await File(path).writeAsBytes(bytes);
    // Tanpa fallback, ini akan throw "failed to decode using utf-8".
    final preview = await ImportService.parseFile(path);
    expect(preview.headers, ['nama', 'qty']);
    expect(preview.rows.length, 1);
    expect(preview.rows.first.first, 'Kipas Anginé');
    await dir.delete(recursive: true);
  });

  test('coupon export: batch count, range & lebar nomor', () {
    expect(CouponExportService.batchCount(0), 0);
    expect(CouponExportService.batchCount(500), 1);
    expect(CouponExportService.batchCount(501), 2);
    expect(CouponExportService.batchCount(109801), 220);

    final coupons = List.generate(
      25000,
      (i) => CouponPrint(no: i + 1, nama: 'A', rekening: 'R'),
    );
    expect(CouponExportService.batchRange(coupons, 0), (1, 500));
    expect(CouponExportService.batchRange(coupons, 2), (1001, 1500));

    expect(CouponExportService.couponWidth(109801), 6);
    expect(CouponExportService.couponWidth(1500000), 7);
    expect(CouponExportService.couponWidth(5), 6);
  });

  test('export nasabah: filter pencarian, byIds & format CSV', () async {
    final db = DatabaseHelper.instance;
    await db.replaceAllAccounts([
      const Account(
          rekening: '01.13.000001.00',
          rekeningLama: 'L-1',
          nama: 'Budi Santoso',
          alamat: 'Jl. A',
          saldo: 500000,
          kuponCount: 5,
          couponStart: 1,
          couponEnd: 5),
      const Account(
          rekening: '01.13.000002.00',
          rekeningLama: '',
          nama: 'Siti Rahayu',
          alamat: 'Jl. B',
          saldo: 0,
          kuponCount: 0,
          couponStart: 0,
          couponEnd: 0),
      const Account(
          rekening: '01.13.000003.00',
          rekeningLama: '',
          nama: 'Budi Lain',
          alamat: '',
          saldo: 200000,
          kuponCount: 2,
          couponStart: 6,
          couponEnd: 7),
    ]);
    final all = await db.getAccountsFiltered('');
    expect(all.length, 3);
    // Filter pencarian sama seperti tabel (nama/rekening, tak peka kapital).
    final budi = await db.getAccountsFiltered('budi');
    expect(budi.map((a) => a.nama), ['Budi Santoso', 'Budi Lain']);
    Account byName(String n) => all.firstWhere((a) => a.nama == n);
    // ByIds: hanya yang dipilih, urutan mengikuti nomor kupon.
    final byIds = await db
        .getAccountsByIds([byName('Budi Lain').id!, byName('Budi Santoso').id!]);
    expect(byIds.map((a) => a.nama), ['Budi Santoso', 'Budi Lain']);
    expect(await db.getAccountsByIds([]), isEmpty);

    final rows =
        buildAccountsCsvRows([byName('Budi Santoso'), byName('Siti Rahayu')]);
    expect(rows.first, [
      'No',
      'Rekening',
      'Rek. Lama',
      'Nama',
      'Alamat',
      'Saldo',
      'Jumlah Kupon',
      'Rentang Kupon',
      'Status'
    ]);
    expect(rows[1][7], '000001-000005'); // rentang kupon terformat
    expect(rows[1][8], 'Belum Menang');
    expect(rows[2][7], '-'); // tanpa kupon
  });

  testWidgets('Data Nasabah: tabel selebar kartu', (tester) async {
    final db = DatabaseHelper.instance;
    // Operasi DB asli harus di luar zona FakeAsync testWidgets.
    await tester.runAsync(() async {
      await db.replaceAllAccounts([
        const Account(
          rekening: '01.13.000001.00',
          rekeningLama: '',
          nama: 'A',
          alamat: '',
          saldo: 100000,
          kuponCount: 1,
          couponStart: 1,
          couponEnd: 1,
        ),
      ]);
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 1200, child: DataTab())),
      ),
    );
    // Beri waktu _load() selesai (DB asli), lalu pump sekali.
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    final tableW = tester.getSize(find.byType(DataTable)).width;
    // Tabel memenuhi lebar area kartu: 1200 dikurangi scrollbar vertikal.
    expect(tableW, greaterThanOrEqualTo(1180));
  });

  testWidgets('Riwayat: tabel selebar kartu', (tester) async {
    final db = DatabaseHelper.instance;
    // Surface lebih tinggi dari default 600px (jendela operator asli
    // minimal 720px) agar header tab tidak overflow vertikal.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Operasi DB asli harus di luar zona FakeAsync testWidgets.
    await tester.runAsync(() async {
      await db.replaceAllAccounts([
        const Account(
          rekening: '01.13.000001.00',
          rekeningLama: '',
          nama: 'Pemenang Uji',
          alamat: '',
          saldo: 100000,
          kuponCount: 1,
          couponStart: 1,
          couponEnd: 1,
        ),
      ]);
      final prizeId = await db
          .insertPrize(const Prize(name: 'Hadiah Uji', urutan: 1, qty: 1));
      final acc = (await db.findByCoupon(1))!;
      await DrawService().recordWinner(
          couponNo: 1, accountId: acc.id!, prizeId: prizeId, mode: 'manual');
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 1200, child: HistoryTab())),
      ),
    );
    // Beri waktu _load() selesai (DB asli), lalu pump sekali.
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    final tableW = tester.getSize(find.byType(DataTable)).width;
    // Konsisten dengan Data Nasabah: tabel memenuhi lebar area kartu.
    expect(tableW, greaterThanOrEqualTo(1180));
    // Bersihkan agar test lain tidak terganggu.
    await tester.runAsync(() async {
      await db.clearAllWinners();
    });
  });

  group('sistem hapus + bulk', () {
    Account acc(String rek, String nama, int kupon, int start, int end) =>
        Account(
          rekening: rek,
          rekeningLama: '',
          nama: nama,
          alamat: '',
          saldo: kupon * 100000,
          kuponCount: kupon,
          couponStart: start,
          couponEnd: end,
        );

    Future<List<int>> seedAccounts() async {
      final db = DatabaseHelper.instance;
      await db.replaceAllAccounts([
        acc('1', 'A', 2, 1, 2), // kupon 1-2
        acc('2', 'B', 1, 3, 3), // kupon 3
        acc('3', 'C', 3, 4, 6), // kupon 4-6
      ]);
      final rows =
          await db.getAccountsPage(limit: 100, offset: 0, query: '');
      return rows.map((a) => a.id!).toList();
    }

    test('deleteAccounts: hapus + hitung ulang rentang kupon', () async {
      final db = DatabaseHelper.instance;
      final ids = await seedAccounts();
      await db.deleteAccounts([ids[1]]); // hapus B (kupon 3)
      final rows =
          await db.getAccountsPage(limit: 100, offset: 0, query: '');
      expect(rows.length, 2);
      // A tetap 1-2, C bergeser jadi 3-5.
      expect(rows[0].nama, 'A');
      expect(rows[0].couponStart, 1);
      expect(rows[0].couponEnd, 2);
      expect(rows[1].nama, 'C');
      expect(rows[1].couponStart, 3);
      expect(rows[1].couponEnd, 5);
      expect(await db.totalCoupons(), 5);
    });

    test('deleteAccounts: tolak bila ada yang sudah menang', () async {
      final db = DatabaseHelper.instance;
      final ids = await seedAccounts();
      await db.markWon(ids[0]);
      await expectLater(
          db.deleteAccounts([ids[0], ids[1]]), throwsStateError);
      // Tidak ada yang terhapus (transaksi rollback).
      expect(await db.countAccounts(), 3);
    });

    test('deleteAccounts: daftar kosong = no-op', () async {
      final db = DatabaseHelper.instance;
      await seedAccounts();
      await db.deleteAccounts([]);
      expect(await db.countAccounts(), 3);
    });

    test('deletePrizes: bulk + guard hadiah yang sudah diundi', () async {
      final db = DatabaseHelper.instance;
      final id1 = await db.insertPrize(
          const Prize(name: 'H1', urutan: 1, qty: 2));
      final id2 = await db.insertPrize(
          const Prize(name: 'H2', urutan: 2, qty: 1));
      final id3 = await db.insertPrize(
          const Prize(name: 'H3', urutan: 3, qty: 1));
      // Bulk hapus H1 + H3.
      await db.deletePrizes([id1, id3]);
      var prizes = await db.getPrizes();
      expect(prizes.length, 1);
      expect(prizes.first.id, id2);
      // H2 sudah diundi -> tidak bisa dihapus (satuan maupun bulk).
      final aids = await seedAccounts();
      await db.insertWinner(Winner(
        couponNo: 1,
        accountId: aids[0],
        prizeId: id2,
        mode: 'manual',
        drawnAt: DateTime.now().toIso8601String(),
      ));
      await expectLater(db.deletePrize(id2), throwsStateError);
      await expectLater(db.deletePrizes([id2]), throwsStateError);
      prizes = await db.getPrizes();
      expect(prizes.length, 1);
    });

    test('clearAllWinners: hapus riwayat + kembalikan flag menang',
        () async {
      final db = DatabaseHelper.instance;
      final aids = await seedAccounts();
      final pid = await db.insertPrize(
          const Prize(name: 'H', urutan: 1, qty: 5));
      await db.markWon(aids[0]);
      await db.insertWinner(Winner(
        couponNo: 1,
        accountId: aids[0],
        prizeId: pid,
        mode: 'random',
        drawnAt: DateTime.now().toIso8601String(),
      ));
      expect(await db.countWinners(), 1);
      await db.clearAllWinners();
      expect(await db.countWinners(), 0);
      final rows =
          await db.getAccountsPage(limit: 100, offset: 0, query: '');
      expect(rows.every((a) => !a.hasWon), true);
      // Setelah reset, hadiah & rekening boleh dihapus.
      await db.deletePrize(pid);
      await db.deleteAccounts([aids[0]]);
      expect((await db.getPrizes()).isEmpty, true);
      expect(await db.countAccounts(), 2);
    });
  });
}
