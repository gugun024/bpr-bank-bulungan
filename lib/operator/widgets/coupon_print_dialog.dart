import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/coupon_export.dart';
import '../../core/database.dart';
import '../../shared/theme.dart';

/// Dialog export kupon fisik ke PDF siap cetak.
///
/// Pilihan: semua batch atau 1 batch tertentu (10.000 kupon/batch).
/// Tiap batch di-render di isolate agar UI tidak freeze.
class CouponPrintDialog extends StatefulWidget {
  final DatabaseHelper db;

  const CouponPrintDialog({super.key, required this.db});

  @override
  State<CouponPrintDialog> createState() => _CouponPrintDialogState();
}

class _CouponPrintDialogState extends State<CouponPrintDialog> {
  bool _loading = true;
  List<CouponPrint> _coupons = const [];
  int _batchIndex = -1; // -1 = semua batch
  bool _busy = false;
  double _progress = 0;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final coupons = await CouponExportService.allCoupons(widget.db);
      if (!mounted) return;
      setState(() {
        _coupons = coupons;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal membaca data kupon: $e';
      });
    }
  }

  int get _batchCount => CouponExportService.batchCount(_coupons.length);
  int get _totalPages => (_coupons.length / CouponExportService.perPage).ceil();
  int get _width => CouponExportService.couponWidth(_coupons.length);

  String _fmt(int n) => n.toString().padLeft(_width, '0');

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Menyiapkan…';
      _error = null;
    });
    try {
      final indices = _batchIndex < 0
          ? List.generate(_batchCount, (i) => i)
          : [_batchIndex];

      // Minta lokasi simpan dulu sebelum render yang berat.
      String? dir;
      String? singlePath;
      if (indices.length > 1) {
        dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Pilih folder untuk $_batchCount file PDF',
        );
        if (dir == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      } else {
        final (from, to) = CouponExportService.batchRange(_coupons, indices.first);
        singlePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan PDF kupon',
          fileName: 'kupon-${_fmt(from)}-${_fmt(to)}.pdf',
        );
        if (singlePath == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }

      final saved = <String>[];
      for (var k = 0; k < indices.length; k++) {
        final bi = indices[k];
        final from = bi * CouponExportService.batchSize;
        final end = (from + CouponExportService.batchSize)
            .clamp(0, _coupons.length);
        final batch = _coupons.sublist(from, end);
        final (cFrom, cTo) = CouponExportService.batchRange(_coupons, bi);

        if (mounted) {
          setState(() {
            _status = indices.length > 1
                ? 'Batch ${k + 1}/${indices.length} (kupon ${_fmt(cFrom)}–${_fmt(cTo)})…'
                : 'Membuat PDF (kupon ${_fmt(cFrom)}–${_fmt(cTo)})…';
            _progress = k / indices.length;
          });
        }

        final bytes = await CouponExportService.buildBatchPdf(
          batch: batch,
          couponWidth: _width,
        );

        final path = indices.length > 1
            ? '$dir${Platform.pathSeparator}kupon-${_fmt(cFrom)}-${_fmt(cTo)}.pdf'
            : singlePath!;
        await File(path).writeAsBytes(bytes);
        saved.add(path);

        if (mounted) setState(() => _progress = (k + 1) / indices.length);
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = saved.length == 1
            ? 'Tersimpan: ${saved.first}'
            : '${saved.length} file tersimpan di:\n${saved.first}\n…\n${saved.last}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Gagal membuat PDF: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.print_outlined, color: OpTheme.navy),
          SizedBox(width: 10),
          Text('Cetak Kupon'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()))
            : _error != null && _coupons.isEmpty
                ? Text(_error!, style: const TextStyle(color: OpTheme.danger))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _infoRow('Total kupon',
                          '${_coupons.length} kupon'),
                      _infoRow('Total halaman A4',
                          '±$_totalPages halaman (10 kupon/hlm)'),
                      _infoRow('Jumlah batch',
                          '$_batchCount file @ ${CouponExportService.batchSize} kupon'),
                      const SizedBox(height: 12),
                      const Text('Batch yang diekspor',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: OpTheme.navy)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        key: ValueKey(_batchIndex),
                        initialValue: _batchIndex,
                        decoration: OpTheme.input(''),
                        items: [
                          const DropdownMenuItem(
                              value: -1, child: Text('Semua batch')),
                          for (var i = 0; i < _batchCount; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                  'Batch ${i + 1} (${_fmt(CouponExportService.batchRange(_coupons, i).$1)}–${_fmt(CouponExportService.batchRange(_coupons, i).$2)})'),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) =>
                                setState(() => _batchIndex = v ?? -1),
                      ),
                      if (_busy) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(value: _progress),
                        const SizedBox(height: 8),
                      ],
                      if (_status != null) ...[
                        const SizedBox(height: 8),
                        Text(_status!,
                            style: const TextStyle(
                                fontSize: 13, color: OpTheme.textMuted)),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!,
                            style: const TextStyle(
                                fontSize: 13, color: OpTheme.danger)),
                      ],
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        FilledButton.icon(
          onPressed: (_busy || _loading || _coupons.isEmpty) ? null : _export,
          style: OpTheme.primaryButton,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('Export PDF'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: OpTheme.textMuted))),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: OpTheme.navy)),
        ],
      ),
    );
  }
}
