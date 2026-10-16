import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database.dart';
import '../../core/models.dart';

/// Tab riwayat pemenang + export + undo.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<Winner> _winners = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await DatabaseHelper.instance.getWinners();
    if (!mounted) return;
    setState(() => _winners = w);
  }

  Future<void> _undo() async {
    final last = await DatabaseHelper.instance.lastWinner();
    if (last == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan undian terakhir?'),
        content: Text(
            '${last.accountNama} (${Account.formatCoupon(last.couponNo)}) — "${last.prizeName}" akan dibatalkan dan rekeningnya bisa menang lagi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya, batalkan')),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseHelper.instance.undoLastWinner();
      await _load();
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final rows = <List<String>>[
        ['No', 'Nama', 'No. Rekening', 'No. Kupon', 'Hadiah', 'Mode', 'Waktu'],
      ];
      final dt = DateFormat('d MMM yyyy HH:mm', 'id');
      for (var i = 0; i < _winners.length; i++) {
        final w = _winners[i];
        String when = w.drawnAt;
        try {
          when = dt.format(DateTime.parse(w.drawnAt));
        } catch (_) {}
        rows.add([
          '${i + 1}',
          w.accountNama ?? '',
          w.accountRekening ?? '',
          Account.formatCoupon(w.couponNo),
          w.prizeName ?? '',
          w.mode,
          when,
        ]);
      }
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path,
          'pemenang_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv'));
      await file.writeAsString(csv);
      // Tawarkan simpan ke lokasi lain.
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan daftar pemenang',
        fileName: p.basename(file.path),
        bytes: await file.readAsBytes(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(savePath != null
                ? 'Tersimpan: $savePath'
                : 'Tersimpan di: ${file.path}')),
      );
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
          Row(
            children: [
              Text('Riwayat Pemenang',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _winners.isEmpty ? null : _undo,
                icon: const Icon(Icons.undo),
                label: const Text('Batalkan Terakhir'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (_winners.isEmpty || _busy) ? null : _export,
                icon: const Icon(Icons.download),
                label: const Text('Export CSV'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _winners.isEmpty
                ? const Center(child: Text('Belum ada pemenang.'))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('No')),
                        DataColumn(label: Text('Nama')),
                        DataColumn(label: Text('No. Rekening')),
                        DataColumn(label: Text('No. Kupon')),
                        DataColumn(label: Text('Hadiah')),
                        DataColumn(label: Text('Mode')),
                        DataColumn(label: Text('Waktu')),
                      ],
                      rows: [
                        for (var i = 0; i < _winners.length; i++)
                          _row(i + 1, _winners[i]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  DataRow _row(int no, Winner w) {
    String when = w.drawnAt;
    try {
      when = DateFormat('d MMM yyyy HH:mm', 'id')
          .format(DateTime.parse(w.drawnAt));
    } catch (_) {}
    return DataRow(cells: [
      DataCell(Text('$no')),
      DataCell(Text(w.accountNama ?? '')),
      DataCell(Text(w.accountRekening ?? '')),
      DataCell(Text(Account.formatCoupon(w.couponNo))),
      DataCell(Text(w.prizeName ?? '')),
      DataCell(Text(w.mode)),
      DataCell(Text(when)),
    ]);
  }
}
