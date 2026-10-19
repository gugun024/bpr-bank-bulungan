import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/database.dart';
import '../../core/import_service.dart';
import '../../shared/theme.dart';
import 'sample_download.dart';

/// Dialog import Excel/CSV → SQLite dengan mapping kolom manual.
///
/// Mengembalikan `true` bila import berhasil — pemanggil (tab Data Nasabah)
/// memakai itu untuk me-refresh tabel.
Future<bool> showImportDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ImportDialog(),
  );
  return ok == true;
}

class ImportDialog extends StatefulWidget {
  const ImportDialog({super.key});

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  ImportPreview? _preview;
  ColumnMapping _map = ColumnMapping();
  ImportValidation _validation = ImportValidation.empty;
  String? _fileName;
  bool _busy = false;
  String? _status;

  void _runValidation() {
    final preview = _preview;
    if (preview == null || !_map.valid) {
      _validation = ImportValidation.empty;
      return;
    }
    _validation = ImportService.validateImport(preview, _map);
  }

  Future<void> _downloadSample() async {
    setState(() => _status = null);
    final path = await downloadSampleCsv(
      assetPath: 'assets/samples/contoh-nasabah.csv',
      suggestedName: 'contoh-nasabah.csv',
    );
    if (!mounted) return;
    setState(() => _status =
        path == null ? null : 'Contoh tersimpan: $path');
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );
    final path = res?.files.single.path;
    if (path == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final preview = await ImportService.parseFile(path);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _fileName = res!.files.single.name;
        _map = ImportService.autoMap(preview.headers);
        _runValidation();
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Gagal membaca file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null || !_map.valid) {
      setState(() => _status =
          'Mapping belum lengkap: kolom Rekening, Nama, dan Saldo wajib dipetakan.');
      return;
    }
    _runValidation();
    if (_validation.hasErrors) {
      setState(() => _status =
          'Import DIBLOKIR: ada ${_validation.duplicates.length} no. rekening duplikat. '
              'Perbaiki file Excel/CSV-nya dulu, lalu pilih ulang filenya.');
      return;
    }
    final warnNote = _validation.hasWarnings
        ? '\n\nPerhatian: ${_validation.mismatches.length} baris kuponnya tidak cocok — '
            'nilai hitungan ulang (floor(saldo/100.000)) yang akan dipakai.'
        : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import data?'),
        content: Text(
            'Data rekening & riwayat undian yang lama akan DIHAPUS dan diganti data baru. '
            '${_validation.validAccounts} rekening, ${_validation.totalCoupons} kupon.$warnNote\n\nLanjutkan?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya, import')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final accounts = ImportService.buildAccounts(preview, _map);
      await DatabaseHelper.instance.replaceAllAccounts(accounts);
      if (!mounted) return;
      Navigator.pop(context, true); // sukses → tutup dialog
    } catch (e) {
      if (mounted) setState(() => _status = 'Gagal import: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header dialog.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                color: OpTheme.navy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.upload_file, color: OpTheme.gold, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Import Data',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        Text(
                            'Excel / CSV — kupon dihitung floor(saldo / 100.000)',
                            style:
                                TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _busy ? null : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Tutup',
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            // Isi (scrollable).
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _pick,
                          style: OpTheme.primaryButton,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Pilih File'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _downloadSample,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Contoh CSV'),
                        ),
                        const SizedBox(width: 12),
                        if (_fileName != null)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: OpTheme.navySoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.table_chart_outlined,
                                      color: OpTheme.navy, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_fileName!,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: OpTheme.navy,
                                            fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: OpTheme.navySoft,
                          border: Border.all(
                              color: OpTheme.navy.withValues(alpha: 0.2)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: OpTheme.navy),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_status!)),
                          ],
                        ),
                      ),
                    ],
                    if (_preview != null) ...[
                      const SizedBox(height: 20),
                      const Text('Mapping Kolom',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: OpTheme.navy)),
                      const SizedBox(height: 4),
                      const Text(
                          'Sesuaikan kolom file dengan data yang dibutuhkan.',
                          style: TextStyle(
                              fontSize: 12, color: OpTheme.textMuted)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _mapField('No. Rekening', (v) => _map.rekening = v,
                              _map.rekening),
                          _mapField('Rek. Lama', (v) => _map.rekeningLama = v,
                              _map.rekeningLama),
                          _mapField('Nama', (v) => _map.nama = v, _map.nama),
                          _mapField(
                              'Alamat', (v) => _map.alamat = v, _map.alamat),
                          _mapField('Saldo', (v) => _map.saldo = v, _map.saldo),
                          _mapField('Kupon (verifikasi)', (v) => _map.kupon = v,
                              _map.kupon),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _validationPanel(),
                    ],
                  ],
                ),
              ),
            ),
            // Footer: tombol import selalu terlihat.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: OpTheme.cardBorder)),
              ),
              child: Row(
                children: [
                  if (_validation.hasErrors)
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Text(
                          'Terkunci: perbaiki rekening duplikat di file sumber, lalu pilih ulang filenya.',
                          style: TextStyle(color: OpTheme.danger, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  OutlinedButton(
                    onPressed:
                        _busy ? null : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed:
                        (_busy || _preview == null || _validation.hasErrors)
                            ? null
                            : _import,
                    style: OpTheme.goldButton,
                    icon: const Icon(Icons.upload),
                    label: const Text('Import ke Database'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapField(String label, void Function(int) set, int current) {
    final headers = _preview?.headers ?? [];
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<int>(
        initialValue: current >= 0 ? current : -1,
        decoration: OpTheme.input(label),
        items: [
          const DropdownMenuItem(value: -1, child: Text('— kosong —')),
          for (var i = 0; i < headers.length; i++)
            DropdownMenuItem(
                value: i,
                child: Text(
                    headers[i].isEmpty ? '(kolom ${i + 1})' : headers[i],
                    overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() {
          set(v ?? -1);
          _runValidation();
        }),
      ),
    );
  }

  /// Panel ringkasan + daftar temuan validasi data.
  Widget _validationPanel() {
    final v = _validation;
    if (_preview == null || !_map.valid) return const SizedBox.shrink();
    final base = v.hasErrors
        ? OpTheme.danger
        : v.hasWarnings
            ? OpTheme.warning
            : OpTheme.success;
    final soft = v.hasErrors
        ? OpTheme.dangerSoft
        : v.hasWarnings
            ? OpTheme.warningSoft
            : OpTheme.successSoft;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: soft,
        border: Border.all(color: base.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Icon(
                    v.isClean
                        ? Icons.check_circle
                        : v.hasErrors
                            ? Icons.error
                            : Icons.warning,
                    color: Colors.white,
                    size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.isClean
                          ? 'Data valid, siap import'
                          : v.hasErrors
                              ? 'DITEMUKAN ${v.duplicates.length} REKENING DUPLIKAT'
                              : 'Ada ${v.mismatches.length} kupon tidak cocok',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: base),
                    ),
                    Text(
                      v.isClean
                          ? '${v.validAccounts} rekening • ${v.totalCoupons} kupon total'
                          : v.hasErrors
                              ? 'Import diblokir sampai file diperbaiki.'
                              : 'Peringatan: nilai hitungan ulang yang dipakai.',
                      style: const TextStyle(
                          fontSize: 12, color: OpTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (v.skippedEmpty > 0 || v.zeroCoupon > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Info: ${v.skippedEmpty} baris tanpa no. rekening (dilewati) • '
                '${v.zeroCoupon} rekening saldo < Rp100.000 (0 kupon).',
                style: const TextStyle(color: OpTheme.textMuted, fontSize: 12),
              ),
            ),
          for (final issue in [...v.duplicates, ...v.mismatches].take(30))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                      issue.kind == 'duplikat'
                          ? Icons.content_copy
                          : Icons.warning_amber,
                      size: 14,
                      color: base),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      issue.message,
                      style: TextStyle(fontSize: 12, color: base),
                    ),
                  ),
                ],
              ),
            ),
          if (v.duplicates.length + v.mismatches.length > 30)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '…dan ${v.duplicates.length + v.mismatches.length - 30} temuan lainnya.',
                style:
                    const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}
