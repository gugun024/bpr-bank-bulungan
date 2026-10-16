// Model data aplikasi undian bank.

class Account {
  final int? id;
  final String rekening;
  final String rekeningLama;
  final String nama;
  final String alamat;
  final int saldo;
  final int kuponCount;
  final int couponStart; // nomor kupon pertama (1-based)
  final int couponEnd; // nomor kupon terakhir (inklusif)
  final bool hasWon;

  const Account({
    this.id,
    required this.rekening,
    required this.rekeningLama,
    required this.nama,
    required this.alamat,
    required this.saldo,
    required this.kuponCount,
    required this.couponStart,
    required this.couponEnd,
    this.hasWon = false,
  });

  /// Format nomor kupon global menjadi 6 digit (atau lebih bila perlu).
  static String formatCoupon(int n, [int width = 6]) =>
      n.toString().padLeft(width, '0');

  Map<String, Object?> toMap() => {
        'id': id,
        'rekening': rekening,
        'rekening_lama': rekeningLama,
        'nama': nama,
        'alamat': alamat,
        'saldo': saldo,
        'kupon_count': kuponCount,
        'coupon_start': couponStart,
        'coupon_end': couponEnd,
        'has_won': hasWon ? 1 : 0,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        rekening: (m['rekening'] ?? '') as String,
        rekeningLama: (m['rekening_lama'] ?? '') as String,
        nama: (m['nama'] ?? '') as String,
        alamat: (m['alamat'] ?? '') as String,
        saldo: (m['saldo'] ?? 0) as int,
        kuponCount: (m['kupon_count'] ?? 0) as int,
        couponStart: (m['coupon_start'] ?? 0) as int,
        couponEnd: (m['coupon_end'] ?? 0) as int,
        hasWon: ((m['has_won'] ?? 0) as int) == 1,
      );
}

class Prize {
  final int? id;
  final String name;
  final int urutan;
  final int qty;

  const Prize(
      {this.id, required this.name, required this.urutan, this.qty = 1});

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'urutan': urutan, 'qty': qty};

  factory Prize.fromMap(Map<String, Object?> m) => Prize(
        id: m['id'] as int?,
        name: (m['name'] ?? '') as String,
        urutan: (m['urutan'] ?? 0) as int,
        qty: (m['qty'] ?? 1) as int,
      );
}

class Winner {
  final int? id;
  final int couponNo;
  final int accountId;
  final int prizeId;
  final String mode; // 'manual' | 'random'
  final String drawnAt;

  // Join fields (diisi saat query dengan JOIN)
  final String? accountNama;
  final String? accountRekening;
  final String? prizeName;

  const Winner({
    this.id,
    required this.couponNo,
    required this.accountId,
    required this.prizeId,
    required this.mode,
    required this.drawnAt,
    this.accountNama,
    this.accountRekening,
    this.prizeName,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'coupon_no': couponNo,
        'account_id': accountId,
        'prize_id': prizeId,
        'mode': mode,
        'drawn_at': drawnAt,
      };

  factory Winner.fromMap(Map<String, Object?> m) => Winner(
        id: m['id'] as int?,
        couponNo: (m['coupon_no'] ?? 0) as int,
        accountId: (m['account_id'] ?? 0) as int,
        prizeId: (m['prize_id'] ?? 0) as int,
        mode: (m['mode'] ?? '') as String,
        drawnAt: (m['drawn_at'] ?? '') as String,
        accountNama: m['account_nama'] as String?,
        accountRekening: m['account_rekening'] as String?,
        prizeName: m['prize_name'] as String?,
      );
}
