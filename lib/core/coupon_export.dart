import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'database.dart';

/// Satu kupon siap cetak.
class CouponPrint {
  final int no; // nomor global 1-based
  final String nama;
  final String rekening;

  const CouponPrint(
      {required this.no, required this.nama, required this.rekening});

  Map<String, dynamic> toMap() =>
      {'no': no, 'nama': nama, 'rekening': rekening};
}

/// Export kupon fisik ke PDF siap cetak.
///
/// Desain plek dengan mockup yang disetujui: A4 LANDSCAPE, 12 kupon per
/// halaman (3 kolom × 4 baris), bingkai ganda emas + ukiran sudut ❧,
/// divider ✦, nomor besar, nama & rekening. Semua vektor (tanpa gambar)
/// + font DejaVu Sans yang di-embed agar ornamen tampil di semua printer.
///
/// Kupon di-export per batch 500 agar tumpukan kertas gampang dicari
/// manual (rentang nomor jelas per file); tiap batch di-render di isolate
/// supaya UI tidak freeze.
class CouponExportService {
  static const int batchSize = 500;
  static const int perPage = 12;

  /// Ambil SEMUA kupon (no, nama, rekening) diurut nomor kupon.
  /// Termasuk milik rekening yang sudah menang — ini arsip kupon fisik.
  static Future<List<CouponPrint>> allCoupons(DatabaseHelper db) async {
    final d = await db.db;
    final rows = await d.query(
      'accounts',
      columns: ['nama', 'rekening', 'coupon_start', 'coupon_end'],
      orderBy: 'coupon_start ASC',
    );
    final out = <CouponPrint>[];
    for (final r in rows) {
      final start = (r['coupon_start'] as int?) ?? 0;
      final end = (r['coupon_end'] as int?) ?? 0;
      if (end < start || start <= 0) continue;
      final nama = (r['nama'] as String?) ?? '';
      final rekening = (r['rekening'] as String?) ?? '';
      for (var no = start; no <= end; no++) {
        out.add(CouponPrint(no: no, nama: nama, rekening: rekening));
      }
    }
    return out;
  }

  /// Jumlah batch untuk [total] kupon.
  static int batchCount(int total) => (total / batchSize).ceil();

  /// Rentang nomor kupon untuk batch ke-[index] (0-based): (dari, sampai).
  static (int, int) batchRange(List<CouponPrint> coupons, int index) {
    final from = index * batchSize;
    final to = min(from + batchSize, coupons.length);
    return (coupons[from].no, coupons[to - 1].no);
  }

  /// Bangun 1 file PDF untuk 1 batch (di isolate).
  static Future<Uint8List> buildBatchPdf({
    required List<CouponPrint> batch,
    required int couponWidth,
  }) async {
    final fontBytes =
        (await rootBundle.load('assets/fonts/DejaVuSans.ttf')).buffer.asUint8List();
    final fontBoldBytes =
        (await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'))
            .buffer
            .asUint8List();
    return compute(
      _buildPdf,
      _PdfJob(
        coupons: batch.map((c) => c.toMap()).toList(),
        fontBytes: fontBytes,
        fontBoldBytes: fontBoldBytes,
        width: couponWidth,
      ),
    );
  }

  /// Lebar digit nomor kupon (min 6), mengikuti total kupon.
  static int couponWidth(int total) => total.toString().length.clamp(6, 12);
}

/// Job untuk isolate — hanya field plain agar bisa ditransfer.
class _PdfJob {
  final List<Map<String, dynamic>> coupons;
  final Uint8List fontBytes;
  final Uint8List fontBoldBytes;
  final int width;

  _PdfJob({
    required this.coupons,
    required this.fontBytes,
    required this.fontBoldBytes,
    required this.width,
  });
}

Future<Uint8List> _buildPdf(_PdfJob job) async {
  final font = pw.Font.ttf(job.fontBytes.buffer.asByteData());
  final fontBold = pw.Font.ttf(job.fontBoldBytes.buffer.asByteData());

  const gold = PdfColor.fromInt(0xFFB8860B);
  const goldSoft = PdfColor.fromInt(0x73B8860B); // ~45% alpha
  const navy = PdfColor.fromInt(0xFF1E3A5F);
  const cream = PdfColor.fromInt(0xFFFFFDF5);
  const gray = PdfColor.fromInt(0xFF6B7280);

  String num(int n) => n.toString().padLeft(job.width, '0');

  pw.Widget coupon(Map<String, dynamic> c) {
    pw.Widget corner(double? top, double? bottom, double? left, double? right) =>
        pw.Positioned(
          top: top,
          bottom: bottom,
          left: left,
          right: right,
          child: pw.Text('❧',
              style: pw.TextStyle(font: font, fontSize: 11, color: gold)),
        );
    return pw.Stack(
      // PENTING: isi penuh sel grid agar semua kupon ukurannya seragam,
      // tidak menciut mengikuti panjang teks.
      fit: pw.StackFit.expand,
      children: [
        pw.Container(
          decoration: pw.BoxDecoration(
            color: cream,
            border: pw.Border.all(color: gold, width: 2),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          padding: const pw.EdgeInsets.symmetric(
              vertical: 10, horizontal: 14),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text('PT. BPR BANK BULUNGAN',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 8.5,
                      color: navy)),
              pw.SizedBox(height: 3),
              pw.Text('✦ ─────── ✦',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: font, fontSize: 8, color: gold)),
              pw.SizedBox(height: 3),
              pw.Text('NOMOR KUPON',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: font, fontSize: 7, color: gray)),
              pw.Text(num(c['no'] as int),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: fontBold, fontSize: 25, color: navy)),
              pw.SizedBox(height: 4),
              pw.Text('${c['nama']}  •  Rek. ${c['rekening']}',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: font, fontSize: 8.5)),
            ],
          ),
        ),
        // Bingkai dalam (inset 1.5mm).
        pw.Positioned.fill(
          child: pw.Container(
            margin: const pw.EdgeInsets.all(4.25),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: goldSoft, width: 1),
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
        ),
        // Ukiran sudut ❧.
        corner(2, null, 3, null),
        corner(2, null, null, 3),
        corner(null, 2, 3, null),
        corner(null, 2, null, 3),
        // Gunting di tepi kanan (penanda potong).
        pw.Positioned(
          right: 1,
          top: 0,
          bottom: 0,
          child: pw.Center(
            child: pw.Text('✂',
                style: pw.TextStyle(font: font, fontSize: 9, color: gray)),
          ),
        ),
      ],
    );
  }

  final doc = pw.Document();
  const perPage = CouponExportService.perPage;
  for (var i = 0; i < job.coupons.length; i += perPage) {
    final pageCoupons =
        job.coupons.sublist(i, min(i + perPage, job.coupons.length));
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28.35), // 10mm
        build: (_) => pw.Column(
          children: [
            for (var r = 0; r < 4; r++) ...[
              if (r > 0) pw.SizedBox(height: 11.34), // gap 4mm
              pw.Expanded(
                child: pw.Row(
                  children: [
                    for (var col = 0; col < 3; col++) ...[
                      if (col > 0) pw.SizedBox(width: 11.34),
                      pw.Expanded(
                        child: (r * 3 + col) < pageCoupons.length
                            ? coupon(pageCoupons[r * 3 + col])
                            : pw.Container(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  return doc.save();
}
