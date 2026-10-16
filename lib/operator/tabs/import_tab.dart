import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/database.dart';
import '../../core/import_service.dart';

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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import Data', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
              'Data saat ini: $_existing rekening. Format didukung: .xlsx, .xls, .csv. '
              'Kupon dihitung otomatis: floor(saldo / 100.000).'),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Pilih File'),
              ),
              if (_fileName != null) ...[
                const SizedBox(width: 12),
                Expanded(
                    child: Text(_fileName!, overflow: TextOverflow.ellipsis)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_status != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_status!),
            ),
          if (_preview != null) ...[
            const Text('Mapping kolom:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _mapField(
                    'No. Rekening', (v) => _map.rekening = v, _map.rekening),
                _mapField('Rek. Lama', (v) => _map.rekeningLama = v,
                    _map.rekeningLama),
                _mapField('Nama', (v) => _map.nama = v, _map.nama),
                _mapField('Alamat', (v) => _map.alamat = v, _map.alamat),
                _mapField('Saldo', (v) => _map.saldo = v, _map.saldo),
                _mapField(
                    'Kupon (verifikasi)', (v) => _map.kupon = v, _map.kupon),
              ],
            ),
            const SizedBox(height: 16),
            _validationPanel(),
            const Text('Preview (5 baris pertama):',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(child: _previewTable()),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _validation.hasErrors ? null : _import,
              icon: const Icon(Icons.upload),
              label: const Text('Import ke Database'),
            ),
            if (_validation.hasErrors)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Tombol import dikunci sampai rekening duplikat diperbaiki di file sumber.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Panel ringkasan + daftar temuan validasi data.
  Widget _validationPanel() {
    final v = _validation;
    if (_preview == null || !_map.valid) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: v.hasErrors
            ? Colors.red.shade50
            : v.hasWarnings
                ? Colors.orange.shade50
                : Colors.green.shade50,
        border: Border.all(
            color: v.hasErrors
                ? Colors.red.shade300
                : v.hasWarnings
                    ? Colors.orange.shade300
                    : Colors.green.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  v.isClean
                      ? Icons.check_circle
                      : v.hasErrors
                          ? Icons.error
                          : Icons.warning,
                  color: v.isClean
                      ? Colors.green
                      : v.hasErrors
                          ? Colors.red
                          : Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v.isClean
                      ? 'Data valid: ${v.validAccounts} rekening, ${v.totalCoupons} kupon total.'
                      : v.hasErrors
                          ? 'DITEMUKAN ${v.duplicates.length} REKENING DUPLIKAT — import diblokir.'
                          : 'Ada ${v.mismatches.length} kupon tidak cocok (peringatan).',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (v.skippedEmpty > 0 || v.zeroCoupon > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Info: ${v.skippedEmpty} baris tanpa no. rekening (dilewati), '
                '${v.zeroCoupon} rekening saldo < Rp100.000 (0 kupon).',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ),
          for (final issue in [...v.duplicates, ...v.mismatches].take(30))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• ${issue.message}',
                style: TextStyle(
                  fontSize: 12,
                  color: issue.kind == 'duplikat'
                      ? Colors.red.shade800
                      : Colors.brown.shade800,
                ),
              ),
            ),
          if (v.duplicates.length + v.mismatches.length > 30)
            Padding(
              padding: const EdgeInsets.only(top: 4),
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
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final h in preview.headers) DataColumn(label: Text(h)),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [for (final c in r) DataCell(Text(c))]),
        ],
      ),
    );
  }
}
