import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/database.dart';
import '../../core/import_service.dart';
import '../../shared/theme.dart';
import '../widgets/ui_kit.dart';

/// Tab import Excel/CSV → SQLite dengan mapping kolom manual.
class ImportTab extends StatefulWidget {
  const ImportTab({super.key});

  @override
  State<ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<ImportTab> {
  ImportPreview? _preview;
  ColumnMapping _map = ColumnMapping();
  ImportValidation _validation = ImportValidation.empty;
  String? _fileName;
  bool _busy = false;
  String? _status;
  int _existing = 0;

  @override
  void initState() {
    super.initState();
    _countExisting();
  }

  void _runValidation() {
    final preview = _preview;
    if (preview == null || !_map.valid) {
      _validation = ImportValidation.empty;
      return;
    }
    _validation = ImportService.validateImport(preview, _map);
  }

  Future<void> _countExisting() async {
    final c = await DatabaseHelper.instance.countAccounts();
    if (mounted) setState(() => _existing = c);
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
      final total = accounts.fold<int>(0, (s, a) => s + a.kuponCount);
      if (!mounted) return;
      setState(() {
        _status =
            'Import selesai: ${accounts.length} rekening, $total kupon total.';
        _preview = null;
        _fileName = null;
      });
      await _countExisting();
    } catch (e) {
      if (mounted) setState(() => _status = 'Gagal import: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(
          title: 'Import Data',
          subtitle:
              'Data saat ini: $_existing rekening. Format: .xlsx, .xls, .csv. Kupon dihitung otomatis floor(saldo / 100.000).',
          actions: [
            FilledButton.icon(
              onPressed: _busy ? null : _pick,
              style: OpTheme.primaryButton.copyWith(
                padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
              ),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Pilih File'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_fileName != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: OpTheme.navySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.table_chart_outlined,
                    color: OpTheme.navy, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_fileName!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: OpTheme.navy))),
              ],
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_status != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OpTheme.navySoft,
              border: Border.all(color: OpTheme.navy.withValues(alpha: 0.2)),
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
        if (_preview != null) ...[
          OpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mapping Kolom',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: OpTheme.navy)),
                const SizedBox(height: 4),
                const Text('Sesuaikan kolom file dengan data yang dibutuhkan.',
                    style: TextStyle(fontSize: 12, color: OpTheme.textMuted)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _mapField('No. Rekening', (v) => _map.rekening = v,
                        _map.rekening),
                    _mapField('Rek. Lama', (v) => _map.rekeningLama = v,
                        _map.rekeningLama),
                    _mapField('Nama', (v) => _map.nama = v, _map.nama),
                    _mapField('Alamat', (v) => _map.alamat = v, _map.alamat),
                    _mapField('Saldo', (v) => _map.saldo = v, _map.saldo),
                    _mapField('Kupon (verifikasi)', (v) => _map.kupon = v,
                        _map.kupon),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _validationPanel(),
          const Text('Preview Data (5 baris pertama)',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: OpTheme.navy)),
          const SizedBox(height: 8),
          Container(
            decoration: OpTheme.card(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _previewTable(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy || _validation.hasErrors ? null : _import,
                style: OpTheme.goldButton,
                icon: const Icon(Icons.upload),
                label: const Text('Import ke Database'),
              ),
              if (_validation.hasErrors)
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Text(
                      'Terkunci: perbaiki rekening duplikat di file sumber, lalu pilih ulang filenya.',
                      style: TextStyle(color: OpTheme.danger, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
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
      margin: const EdgeInsets.only(bottom: 16),
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

  Widget _previewTable() {
    final preview = _preview!;
    final rows = preview.rows.take(5).toList();
    return DataTable(
      headingRowColor: WidgetStateProperty.all(OpTheme.navySoft),
      headingTextStyle: const TextStyle(
          fontWeight: FontWeight.w800, color: OpTheme.navy, fontSize: 13),
      dataTextStyle: const TextStyle(fontSize: 13, color: Color(0xFF1E2A45)),
      columns: [
        for (final h in preview.headers) DataColumn(label: Text(h)),
      ],
      rows: [
        for (final r in rows)
          DataRow(cells: [for (final c in r) DataCell(Text(c))]),
      ],
    );
  }
}
