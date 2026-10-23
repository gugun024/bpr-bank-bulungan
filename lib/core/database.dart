import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models.dart';

/// Kolom urutan untuk daftar rekening (tabel Data Nasabah & export).
enum AccountSort { kupon, rekening, nama, saldo, jumlahKupon, status }

/// Lapisan database SQLite (dipakai HANYA dari window operator).
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();
  Database? _db;

  /// Override path database (untuk test). Null = pakai Documents.
  static String? debugDbPath;

  Future<Database> get db async {
    final d = _db;
    if (d != null) return d;
    return _db = await _open();
  }

  Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final override = debugDbPath;
    final String path;
    if (override != null) {
      path = override;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, 'undian_bank.db');
    }
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await _createV1(db);
          await _createSettings(db);
          await _addPrizeImageColumn(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // v1 → v2: tambah tabel settings (tanpa mengganggu data).
          if (oldVersion < 2) await _createSettings(db);
          // v2 → v3: kolom gambar hadiah.
          if (oldVersion < 3) await _addPrizeImageColumn(db);
        },
      ),
    );
  }

  /// v3: kolom path gambar pada tabel prizes ('' = tanpa gambar).
  static Future<void> _addPrizeImageColumn(Database db) async {
    await db.execute(
        "ALTER TABLE prizes ADD COLUMN image_path TEXT NOT NULL DEFAULT ''");
  }

  /// Skema awal (v1): accounts, prizes, winners.
  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rekening TEXT UNIQUE NOT NULL,
        rekening_lama TEXT NOT NULL DEFAULT '',
        nama TEXT NOT NULL DEFAULT '',
        alamat TEXT NOT NULL DEFAULT '',
        saldo INTEGER NOT NULL DEFAULT 0,
        kupon_count INTEGER NOT NULL DEFAULT 0,
        coupon_start INTEGER NOT NULL DEFAULT 0,
        coupon_end INTEGER NOT NULL DEFAULT 0,
        has_won INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
        'CREATE INDEX idx_accounts_coupon ON accounts(coupon_start, coupon_end)');
    await db.execute('''
      CREATE TABLE prizes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        urutan INTEGER NOT NULL DEFAULT 0,
        qty INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE winners(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        coupon_no INTEGER NOT NULL,
        account_id INTEGER NOT NULL,
        prize_id INTEGER NOT NULL,
        mode TEXT NOT NULL,
        drawn_at TEXT NOT NULL
      )''');
  }

  /// Tabel settings (v2): key-value untuk preferensi operator.
  static Future<void> _createSettings(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT ''
      )''');
  }

  // ---------- settings ----------

  /// Ambil nilai setting; null bila belum pernah disimpan.
  Future<String?> getSetting(String key) async {
    final d = await db;
    final r = await d.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (r.isEmpty) return null;
    return r.first['value'] as String?;
  }

  /// Simpan nilai setting (insert atau update).
  Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- accounts ----------

  Future<void> replaceAllAccounts(List<Account> accounts) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('accounts');
      await txn.delete('winners'); // import baru = undian di-reset
      final batch = txn.batch();
      for (final a in accounts) {
        batch.insert('accounts', a.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<int> countAccounts() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) AS c FROM accounts');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Hapus rekening terpilih (satuan/bulk) + hitung ulang rentang kupon
  /// global berurutan (aturan sama seperti import: mulai dari 1).
  /// Melempar StateError bila ada rekening yang sudah menang — riwayat
  /// harus dibatalkan dulu agar tidak rusak.
  Future<void> deleteAccounts(List<int> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    await d.transaction((txn) async {
      final ph = ids.map((_) => '?').join(',');
      final won = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM accounts WHERE id IN ($ph) AND has_won = 1',
        ids,
      );
      if (((won.first['c'] as int?) ?? 0) > 0) {
        throw StateError(
            'Ada rekening yang sudah menang — batalkan undiannya dulu di tab Riwayat.');
      }
      await txn.delete('accounts', where: 'id IN ($ph)', whereArgs: ids);
      final rows = await txn.query(
        'accounts',
        columns: ['id', 'kupon_count'],
        orderBy: 'coupon_start ASC',
      );
      var next = 1;
      final batch = txn.batch();
      for (final r in rows) {
        final count = (r['kupon_count'] as int?) ?? 0;
        final start = count > 0 ? next : 0;
        final end = count > 0 ? next + count - 1 : 0;
        next += count;
        batch.update(
          'accounts',
          {'coupon_start': start, 'coupon_end': end},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Jumlah rekening dengan filter pencarian (nama / no. rekening).
  Future<int> countAccountsFiltered(String query) async {
    final d = await db;
    final q = query.trim();
    if (q.isEmpty) return countAccounts();
    final r = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM accounts WHERE nama LIKE ? OR rekening LIKE ?',
      ['%$q%', '%$q%'],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Satu halaman data rekening untuk tabel Data Nasabah,
  /// diurutkan mengikuti nomor kupon.
  Future<List<Account>> getAccountsPage({
    required int limit,
    required int offset,
    String query = '',
    AccountSort sort = AccountSort.kupon,
    bool ascending = true,
  }) async {
    final d = await db;
    final q = query.trim();
    final r = await d.query(
      'accounts',
      where: q.isEmpty ? null : 'nama LIKE ? OR rekening LIKE ?',
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%'],
      orderBy: _accountOrderBy(sort, ascending),
      limit: limit,
      offset: offset,
    );
    return r.map(Account.fromMap).toList();
  }

  /// Klausa ORDER BY (whitelist) untuk [AccountSort]; tiebreak deterministik
  /// agar paginasi stabil antar-halaman.
  static String _accountOrderBy(AccountSort sort, bool ascending) {
    final dir = ascending ? 'ASC' : 'DESC';
    return switch (sort) {
      AccountSort.kupon => 'coupon_start $dir, id $dir',
      AccountSort.rekening => 'LENGTH(rekening) $dir, rekening $dir, id $dir',
      AccountSort.nama => 'nama COLLATE NOCASE $dir, coupon_start ASC',
      AccountSort.saldo => 'saldo $dir, coupon_start ASC',
      AccountSort.jumlahKupon => 'kupon_count $dir, coupon_start ASC',
      AccountSort.status => 'has_won $dir, coupon_start ASC',
    };
  }

  /// Semua rekening yang cocok dengan pencarian (tanpa paginasi),
  /// untuk export CSV. Semantik filter sama persis dengan tabel.
  Future<List<Account>> getAccountsFiltered(String query,
          {AccountSort sort = AccountSort.kupon, bool ascending = true}) =>
      getAccountsPage(
          limit: 1 << 30,
          offset: 0,
          query: query,
          sort: sort,
          ascending: ascending);

  /// Rekening berdasarkan daftar id (untuk export pilihan/ceklis),
  /// diurutkan mengikuti nomor kupon.
  Future<List<Account>> getAccountsByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final d = await db;
    final marks = List.filled(ids.length, '?').join(',');
    final r = await d.query(
      'accounts',
      where: 'id IN ($marks)',
      whereArgs: ids,
      orderBy: 'coupon_start ASC',
    );
    return r.map(Account.fromMap).toList();
  }

  Future<int> totalCoupons() async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COALESCE(SUM(kupon_count),0) AS s FROM accounts WHERE has_won = 0');
    return (r.first['s'] as int?) ?? 0;
  }

  /// Cari pemilik nomor kupon (nomor global 1-based).
  Future<Account?> findByCoupon(int couponNo) async {
    final d = await db;
    final r = await d.query(
      'accounts',
      where: '? BETWEEN coupon_start AND coupon_end',
      whereArgs: [couponNo],
      limit: 1,
    );
    if (r.isEmpty) return null;
    return Account.fromMap(r.first);
  }

  /// Ambil daftar range kupon milik rekening yang BELUM menang (untuk pool random).
  Future<List<Account>> eligibleAccounts() async {
    final d = await db;
    final r = await d.query(
      'accounts',
      where: 'has_won = 0 AND kupon_count > 0',
      orderBy: 'coupon_start ASC',
    );
    return r.map(Account.fromMap).toList();
  }

  Future<void> markWon(int accountId) async {
    final d = await db;
    await d.update('accounts', {'has_won': 1},
        where: 'id = ?', whereArgs: [accountId]);
  }

  Future<void> unmarkWon(int accountId) async {
    final d = await db;
    await d.update('accounts', {'has_won': 0},
        where: 'id = ?', whereArgs: [accountId]);
  }

  // ---------- prizes ----------

  Future<List<Prize>> getPrizes() async {
    final d = await db;
    final r = await d.query('prizes', orderBy: 'urutan ASC, id ASC');
    return r.map(Prize.fromMap).toList();
  }

  Future<int> insertPrize(Prize prize) async {
    final d = await db;
    return d.insert('prizes', prize.toMap());
  }

  Future<void> updatePrize(Prize prize) async {
    final d = await db;
    await d.update('prizes', prize.toMap(),
        where: 'id = ?', whereArgs: [prize.id]);
  }

  /// Set / kosongkan path gambar hadiah (update parsial).
  Future<void> setPrizeImage(int id, String path) async {
    final d = await db;
    await d.update('prizes', {'image_path': path},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePrize(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      final r = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM winners WHERE prize_id = ?', [id]);
      if (((r.first['c'] as int?) ?? 0) > 0) {
        throw StateError(
            'Hadiah sudah pernah diundi — batalkan riwayatnya dulu di tab Riwayat.');
      }
      await txn.delete('prizes', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Hapus beberapa hadiah sekaligus (bulk). Guard sama seperti satuan:
  /// hadiah yang sudah pernah diundi tidak boleh dihapus.
  Future<void> deletePrizes(List<int> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    await d.transaction((txn) async {
      final ph = ids.map((_) => '?').join(',');
      final r = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM winners WHERE prize_id IN ($ph)', ids);
      if (((r.first['c'] as int?) ?? 0) > 0) {
        throw StateError(
            'Ada hadiah yang sudah pernah diundi — batalkan riwayatnya dulu di tab Riwayat.');
      }
      await txn.delete('prizes', where: 'id IN ($ph)', whereArgs: ids);
    });
  }

  Future<int> winnerCountForPrize(int prizeId) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) AS c FROM winners WHERE prize_id = ?', [prizeId]);
    return (r.first['c'] as int?) ?? 0;
  }

  /// Jumlah seluruh pemenang tercatat (untuk guard import hadiah).
  Future<int> countWinners() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) AS c FROM winners');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Ganti seluruh daftar hadiah (dipakai import CSV).
  /// Urutan mengikuti urutan baris file (1-based).
  Future<void> replaceAllPrizes(List<Prize> prizes) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('prizes');
      final batch = txn.batch();
      for (var i = 0; i < prizes.length; i++) {
        final p = prizes[i];
        batch.insert('prizes',
            {'name': p.name, 'urutan': i + 1, 'qty': p.qty < 1 ? 1 : p.qty});
      }
      await batch.commit(noResult: true);
    });
  }

  // ---------- winners ----------

  Future<int> insertWinner(Winner w) async {
    final d = await db;
    return d.insert('winners', w.toMap());
  }

  Future<List<Winner>> getWinners() async {
    final d = await db;
    final r = await d.rawQuery('''
      SELECT w.*, a.nama AS account_nama, a.rekening AS account_rekening,
             pr.name AS prize_name
      FROM winners w
      JOIN accounts a ON a.id = w.account_id
      JOIN prizes pr ON pr.id = w.prize_id
      ORDER BY w.id DESC
    ''');
    return r.map(Winner.fromMap).toList();
  }

  Future<Winner?> lastWinner() async {
    final d = await db;
    final r = await d.rawQuery('''
      SELECT w.*, a.nama AS account_nama, a.rekening AS account_rekening,
             pr.name AS prize_name
      FROM winners w
      JOIN accounts a ON a.id = w.account_id
      JOIN prizes pr ON pr.id = w.prize_id
      ORDER BY w.id DESC LIMIT 1
    ''');
    if (r.isEmpty) return null;
    return Winner.fromMap(r.first);
  }

  /// Batalkan undian terakhir (undo): hapus winner + kembalikan flag rekening.
  Future<void> undoLastWinner() async {
    final d = await db;
    final w = await lastWinner();
    if (w == null) return;
    await d.transaction((txn) async {
      await txn.delete('winners', where: 'id = ?', whereArgs: [w.id]);
      await txn.update('accounts', {'has_won': 0},
          where: 'id = ?', whereArgs: [w.accountId]);
    });
  }

  /// Hapus SEMUA riwayat pemenang + kembalikan flag menang semua rekening.
  /// Dipakai tombol "Reset Undian" di tab Riwayat.
  Future<void> clearAllWinners() async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('winners');
      await txn.update('accounts', {'has_won': 0});
    });
  }

  Future<String?> prizeNameOfAccount(int accountId) async {
    final d = await db;
    final r = await d.rawQuery('''
      SELECT pr.name FROM winners w
      JOIN prizes pr ON pr.id = w.prize_id
      WHERE w.account_id = ? ORDER BY w.id DESC LIMIT 1
    ''', [accountId]);
    if (r.isEmpty) return null;
    return r.first['name'] as String?;
  }

  Future<String?> wonAtOfAccount(int accountId) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT drawn_at FROM winners WHERE account_id = ? ORDER BY id DESC LIMIT 1',
        [accountId]);
    if (r.isEmpty) return null;
    return r.first['drawn_at'] as String?;
  }
}
