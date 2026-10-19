import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/database.dart';
import '../../core/import_service.dart';
import '../../core/models.dart';
import '../../shared/theme.dart';
import 'sample_download.dart';

/// Dialog import hadiah dari CSV/Excel → SQLite.
///
/// Format file: 2 kolom (nama hadiah, jumlah unit), misal:
///   nama,qty
///   Sepeda,6
///   Kulkas,2
///
/// Daftar hadiah lama DIGANTI seluruhnya. Import diblokir bila sudah ada
/// pemenang tercatat (agar riwayat tidak rusak).
///
/// Mengembalikan `true` bila import berhasil.
Future<bool> showPrizeImportDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PrizeImportDialog(),
  );
  return ok == true;
}

class PrizeImportDialog extends StatefulWidget {
  const PrizeImportDialog({super.key});

  @override
  State<PrizeImportDialog> createState() => _PrizeImportDialogState();
}

class _PrizeImportDialogState extends State<PrizeImportDialog> {
  ImportPreview? _preview;
  PrizeColumnMapping _map = PrizeColumnMapping();
  String? _fileName;
  bool _busy = false;
  String? _status;
  int _winnerCount = -1; // -1 = belum dicek

  @override
  void initState() {
    super.initState();
    _checkWinners();
  }

  Future<void> _checkWinners() async {
    final n = await DatabaseHelper.instance.countWinners();
    if (mounted) setState(() => _winnerCount = n);
  }

  Future<void> _downloadSample() async {
    setState(() => _status = null);
    final path = await downloadSampleCsv(
      assetPath: 'assets/samples/contoh-hadiah.csv',
      suggestedName: 'contoh-hadiah.csv',
    );
    if (!mounted) return;
    setState(() => _status = path == null
        ? null
        : 'Contoh tersimpan: $path');
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
        _map = PrizeImportService.autoMap(preview.headers);
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Gagal membaca file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Prize> _prizes() {
    final preview = _preview;
    if (preview == null || !_map.valid) return [];
    return PrizeImportService.buildPrizes(preview, _map);
  }

  Future<void> _import() async {
    final prizes = _prizes();
    if (prizes.isEmpty) {
      setState(() => _status =
          'Tidak ada hadiah valid. Pastikan kolom Nama & Jumlah terpetakan.');
      return;
    }
    final totalUnit = prizes.fold<int>(0, (s, p) => s + p.qty);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import hadiah?'),
        content: Text(
            'Daftar hadiah yang lama akan DIGANTI seluruhnya.\n'
            '${prizes.length} hadiah, $totalUnit unit total.\n\nLanjutkan?'),
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
      await DatabaseHelper.instance.replaceAllPrizes(prizes);
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
    final blocked = _winnerCount > 0;
    final prizes = _prizes();
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                color: OpTheme.navy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard, color: OpTheme.gold, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Import Hadiah',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        Text('CSV / Excel — kolom: nama, jumlah (qty)',
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_winnerCount == -1)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator()))
                    else if (blocked)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: OpTheme.dangerSoft,
                          border: Border.all(
                              color:
                                  OpTheme.danger.withValues(alpha: 0.35)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.block, color: OpTheme.danger),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Import DIBLOKIR: sudah ada $_winnerCount pemenang tercatat. '
                                'Hapus riwayat undian dulu sebelum mengganti daftar hadiah.',
                                style: const TextStyle(
                                    color: OpTheme.danger,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
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
                              child: Text(_fileName!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: OpTheme.navy,
                                      fontSize: 13)),
                            ),
                        ],
                      ),
                      if (_status != null) ...[
                        const SizedBox(height: 12),
                        Text(_status!,
                            style:
                                const TextStyle(color: OpTheme.danger)),
                      ],
                      if (_preview != null) ...[
                        const SizedBox(height: 20),
                        const Text('Mapping Kolom',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: OpTheme.navy)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _mapField(
                                'Nama hadiah', (v) => _map.nama = v, _map.nama),
                            _mapField('Jumlah (qty)', (v) => _map.qty = v,
                                _map.qty),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (prizes.isNotEmpty) ...[
                          Text(
                              'Preview: ${prizes.length} hadiah akan diimport',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: OpTheme.navy)),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: OpTheme.cardBorder),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                for (var i = 0;
                                    i < prizes.length && i < 20;
                                    i++)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      border: i < prizes.length - 1 &&
                                              i < 19
                                          ? const Border(
                                              bottom: BorderSide(
                                                  color:
                                                      OpTheme.cardBorder))
                                          : null,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: OpTheme.navySoft,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Center(
                                              child: Text('${i + 1}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: OpTheme.navy,
                                                      fontSize: 13))),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Text(prizes[i].name,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600))),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: OpTheme.successSoft,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text('${prizes[i].qty} unit',
                                              style: const TextStyle(
                                                  color: OpTheme.success,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (prizes.length > 20)
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                        '…dan ${prizes.length - 20} hadiah lainnya.',
                                        style: const TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: OpTheme.textMuted)),
                                  ),
                              ],
                            ),
                          ),
                        ] else
                          const Text(
                              'Tidak ada baris valid — periksa mapping kolom.',
                              style: TextStyle(color: OpTheme.danger)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: OpTheme.cardBorder)),
              ),
              child: Row(
                children: [
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
                    onPressed: (_busy ||
                            blocked ||
                            _winnerCount == -1 ||
                            prizes.isEmpty)
                        ? null
                        : _import,
                    style: OpTheme.goldButton,
                    icon: const Icon(Icons.upload),
                    label: const Text('Import Hadiah'),
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
        onChanged: (v) => setState(() => set(v ?? -1)),
      ),
    );
  }
}
