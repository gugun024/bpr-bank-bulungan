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
      final h = headers[i].toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ');
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

  /// Parse format saldo Indonesia: "6.889.777", "6889777", "6,889,777", "6.889.777,00".
  static int parseSaldo(String s) {
    var t = s.trim().replaceAll(RegExp(r'[^0-9.,]'), '');
    if (t.isEmpty) return 0;
    if (t.contains(',')) {
      // Format Indonesia: titik = ribuan, koma = desimal → buang desimal.
      t = t.split(',').first.replaceAll('.', '');
    } else if (t.contains('.')) {
      // Hanya titik → anggap pemisah ribuan.
      t = t.replaceAll('.', '');
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

  /// Lebar digit untuk format nomor kupon (min 6 digit).
  static int couponWidth(int totalCoupons) {
    final w = totalCoupons.toString().length;
    return w < 6 ? 6 : w;
  }
}

/// Helper baca bytes file (dipakai untuk sniffing sederhana).
Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();
