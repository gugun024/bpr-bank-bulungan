import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import 'models.dart';

/// Hasil parsing file import (sebelum disimpan ke DB).
class ImportPreview {
  final List<String> headers;
  final List<List<String>> rows; // semua sel sebagai string
  ImportPreview(this.headers, this.rows);
}

class ColumnMapping {
  int rekening = -1;
  int rekeningLama = -1;
  int nama = -1;
  int alamat = -1;
  int saldo = -1;
  int kupon = -1; // opsional, hanya untuk verifikasi

  bool get valid => rekening >= 0 && nama >= 0 && saldo >= 0;
}

/// Service import Excel/CSV → daftar [Account] siap simpan.
class ImportService {
  static const int rupiahPerKupon = 100000;

  /// Baca file (.xlsx/.xls/.csv) menjadi tabel string.
  static Future<ImportPreview> parseFile(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.csv')) {
      final text = await File(path).readAsString();
      final rows = const CsvToListConverter().convert(text, eol: '\n');
      return _toPreview(rows);
    }
    final bytes = await File(path).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;
    final rows = sheet.rows
        .map((r) => r.map((c) => _cellString(c?.value)).toList())
        .toList();
    return _toPreview(rows);
  }

  static ImportPreview _toPreview(List<List<dynamic>> rows) {
    // Buang baris yang sepenuhnya kosong.
    final clean = rows
        .where((r) => r.any((c) => c.toString().trim().isNotEmpty))
        .map((r) => r.map((c) => c.toString().trim()).toList())
        .toList();
    if (clean.isEmpty) return ImportPreview([], []);
    final width = clean.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final norm =
        clean.map((r) => [...r, ...List.filled(width - r.length, '')]).toList();
    return ImportPreview(norm.first, norm.sublist(1));
  }

  static String _cellString(dynamic v) {
    if (v == null) return '';
    if (v is double && v == v.truncateToDouble()) {
      return v.truncate().toString();
    }
    return v.toString().trim();
  }

  /// Tebak mapping kolom dari nama header (Indonesia).
  static ColumnMapping autoMap(List<String> headers) {
    final m = ColumnMapping();
    for (var i = 0; i < headers.length; i++) {
      var h = headers[i].toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ');
      h = h.replaceAll(RegExp(r'\brek\b'), 'rekening'); // "Rek. Lama"
      final hs = ' $h ';
      if (hs.contains('rekening') && hs.contains('lama')) {
        m.rekeningLama = i;
      } else if (hs.contains('rekening') || hs.contains('account')) {
        if (m.rekening == -1) m.rekening = i;
      } else if (hs.contains('nama') || hs.contains('name')) {
        m.nama = i;
      } else if (hs.contains('alamat') || hs.contains('address')) {
        m.alamat = i;
      } else if (hs.contains('saldo') || hs.contains('balance')) {
        m.saldo = i;
      } else if (hs.contains('kupon') ||
          hs.contains('coupon') ||
          hs.contains('tiket')) {
        m.kupon = i;
      }
    }
    return m;
  }

  /// Parse format saldo Indonesia maupun Inggris:
  /// "6.889.777", "6,889,777", "6889777", "6.889.777,00", "6,889,777.00".
  /// Bila hanya satu jenis pemisah: dianggap ribuan bila tiap grup setelah
  /// grup pertama tepat 3 digit ("6,889,777"), selain itu dianggap desimal
  /// ("6889,77" -> 6889). Desimal selalu dibuang (floor).
  static int parseSaldo(String s) {
    var t = s.trim().replaceAll(RegExp(r'[^0-9.,]'), '');
    if (t.isEmpty) return 0;
    if (t.contains('.') && t.contains(',')) {
      // Kedua pemisah ada: yang TERAKHIR adalah desimal.
      if (t.lastIndexOf('.') > t.lastIndexOf(',')) {
        t = t.replaceAll(',', '').split('.').first; // "6,889,777.00"
      } else {
        t = t.replaceAll('.', '').split(',').first; // "6.889.777,00"
      }
    } else if (t.contains(',') || t.contains('.')) {
      final sep = t.contains(',') ? ',' : '.';
      final parts = t.split(sep).where((p) => p.isNotEmpty).toList();
      final thousands =
          parts.length > 1 && parts.skip(1).every((p) => p.length == 3);
      t = thousands ? parts.join() : parts.first;
    }
    return int.tryParse(t) ?? 0;
  }

  /// Hitung jumlah kupon: floor(saldo / 100.000).
  static int kuponCount(int saldo) => saldo ~/ rupiahPerKupon;

  /// Bangun daftar Account dari preview + mapping.
  /// Penomoran kupon global berurutan mulai dari 1 (dalam urutan baris).
  static List<Account> buildAccounts(ImportPreview preview, ColumnMapping m) {
    final accounts = <Account>[];
    var nextCoupon = 1;
    for (final row in preview.rows) {
      String cell(int i) => (i >= 0 && i < row.length) ? row[i] : '';
      final rekening = cell(m.rekening);
      if (rekening.isEmpty) continue;
      final saldo = parseSaldo(cell(m.saldo));
      final count = kuponCount(saldo);
      final start = count > 0 ? nextCoupon : 0;
      final end = count > 0 ? nextCoupon + count - 1 : 0;
      nextCoupon += count;
      accounts.add(Account(
        rekening: rekening,
        rekeningLama: cell(m.rekeningLama),
        nama: cell(m.nama),
        alamat: cell(m.alamat),
        saldo: saldo,
        kuponCount: count,
        couponStart: start,
        couponEnd: end,
      ));
    }
    return accounts;
  }

  /// Validasi data import sebelum disimpan ke DB.
  ///
  /// - ERROR (blokir import): no. rekening duplikat. Rekening adalah kunci
  ///   eksklusi pemenang ("1 rekening menang 1x"), jadi duplikat = data salah.
  ///   Perbandingan mengabaikan format: titik, spasi, dan huruf besar/kecil
  ///   ("01.13.097863.001" == "0113097863001").
  /// - WARNING (boleh lanjut): kolom kupon pada file tidak sama dengan
  ///   floor(saldo / 100.000). Nilai hitungan ulang yang dipakai saat import.
  static ImportValidation validateImport(
      ImportPreview preview, ColumnMapping m) {
    final duplicates = <ValidationIssue>[];
    final mismatches = <ValidationIssue>[];
    var skippedEmpty = 0;
    var zeroCoupon = 0;
    var validAccounts = 0;
    var totalCoupons = 0;

    final seen = <String, int>{}; // kunci rekening → nomor baris pertama

    for (var i = 0; i < preview.rows.length; i++) {
      final rowNum = i + 2; // baris 1 = header
      final row = preview.rows[i];
      String cell(int c) => (c >= 0 && c < row.length) ? row[c].trim() : '';
      final rekening = cell(m.rekening);
      final nama = cell(m.nama);
      if (rekening.isEmpty) {
        skippedEmpty++;
        continue;
      }
      validAccounts++;

      final stripped =
          rekening.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final key = stripped.isEmpty ? rekening.toLowerCase() : stripped;
      final firstRow = seen[key];
      if (firstRow != null) {
        duplicates.add(ValidationIssue(
          row: rowNum,
          rekening: rekening,
          nama: nama,
          kind: 'duplikat',
          message: 'Baris $rowNum: "$rekening" duplikat (sudah ada di baris '
              '$firstRow).',
        ));
      } else {
        seen[key] = rowNum;
      }

      final saldo = parseSaldo(cell(m.saldo));
      final count = kuponCount(saldo);
      if (count == 0) {
        zeroCoupon++;
      } else {
        totalCoupons += count;
      }

      if (m.kupon >= 0) {
        final raw = cell(m.kupon).replaceAll(RegExp(r'[^0-9]'), '');
        final fileKupon = raw.isEmpty ? null : int.tryParse(raw);
        if (fileKupon != null && fileKupon != count) {
          mismatches.add(ValidationIssue(
            row: rowNum,
            rekening: rekening,
            nama: nama,
            kind: 'kupon',
            message: 'Baris $rowNum: kupon file=$fileKupon ≠ hitungan=$count '
                '(saldo $saldo). Dipakai: $count.',
          ));
        }
      }
    }

    return ImportValidation(
      duplicates: duplicates,
      mismatches: mismatches,
      skippedEmpty: skippedEmpty,
      zeroCoupon: zeroCoupon,
      validAccounts: validAccounts,
      totalCoupons: totalCoupons,
    );
  }

  /// Lebar digit untuk format nomor kupon (min 6 digit).
  static int couponWidth(int totalCoupons) {
    final w = totalCoupons.toString().length;
    return w < 6 ? 6 : w;
  }
}

/// Satu temuan validasi pada sebuah baris data import.
class ValidationIssue {
  final int row; // nomor baris pada file (1-based, baris 1 = header)
  final String rekening;
  final String nama;
  final String kind; // 'duplikat' | 'kupon'
  final String message;

  const ValidationIssue({
    required this.row,
    required this.rekening,
    required this.nama,
    required this.kind,
    required this.message,
  });
}

/// Hasil validasi data import sebelum disimpan ke DB.
class ImportValidation {
  /// ERROR: no. rekening duplikat → import diblokir.
  final List<ValidationIssue> duplicates;

  /// WARNING: kupon di file ≠ floor(saldo/100.000) → boleh lanjut,
  /// nilai hitungan ulang yang dipakai.
  final List<ValidationIssue> mismatches;

  final int skippedEmpty; // baris tanpa no. rekening (dilewati)
  final int zeroCoupon; // rekening valid tapi saldo < 100rb → 0 kupon
  final int validAccounts;
  final int totalCoupons;

  const ImportValidation({
    required this.duplicates,
    required this.mismatches,
    required this.skippedEmpty,
    required this.zeroCoupon,
    required this.validAccounts,
    required this.totalCoupons,
  });

  bool get hasErrors => duplicates.isNotEmpty;
  bool get hasWarnings => mismatches.isNotEmpty;
  bool get isClean => !hasErrors && !hasWarnings;

  static const empty = ImportValidation(
    duplicates: [],
    mismatches: [],
    skippedEmpty: 0,
    zeroCoupon: 0,
    validAccounts: 0,
    totalCoupons: 0,
  );
}

/// Helper baca bytes file (dipakai untuk sniffing sederhana).
Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();
