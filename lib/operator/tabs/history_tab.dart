import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database.dart';
import '../../core/models.dart';
import '../../shared/theme.dart';
import '../widgets/ui_kit.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(
          title: 'Riwayat Pemenang',
          subtitle:
              '${_winners.length} pemenang tercatat. Satu rekening hanya bisa menang 1x.',
          actions: [
            OutlinedButton.icon(
              onPressed: _winners.isEmpty ? null : _undo,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Batalkan Terakhir'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: (_winners.isEmpty || _busy) ? null : _export,
              style: OpTheme.primaryButton.copyWith(
                padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
              ),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _winners.isEmpty
              ? const OpCard(
                  child: SizedBox(
                    height: 320,
                    child: EmptyState(
                      icon: Icons.emoji_events_outlined,
                      title: 'Belum ada pemenang',
                      subtitle:
                          'Hasil undian akan tercatat di sini secara otomatis.',
                    ),
                  ),
                )
              : Container(
                  decoration: OpTheme.card(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor:
                            WidgetStateProperty.all(OpTheme.navySoft),
                        headingTextStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: OpTheme.navy,
                            fontSize: 13),
                        dataTextStyle: const TextStyle(
                            fontSize: 13, color: Color(0xFF1E2A45)),
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
                ),
        ),
      ],
    );
  }

  DataRow _row(int no, Winner w) {
    String when = w.drawnAt;
    try {
      when = DateFormat('d MMM yyyy HH:mm', 'id')
          .format(DateTime.parse(w.drawnAt));
    } catch (_) {}
    return DataRow(cells: [
      DataCell(Text('$no', style: const TextStyle(color: OpTheme.textMuted))),
      DataCell(Text(w.accountNama ?? '',
          style: const TextStyle(fontWeight: FontWeight.w700))),
      DataCell(Text(w.accountRekening ?? '')),
      DataCell(Text(
        Account.formatCoupon(w.couponNo),
        style: const TextStyle(
            fontFeatures: [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
            color: OpTheme.navy),
      )),
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.card_giftcard, size: 14, color: OpTheme.goldDark),
          const SizedBox(width: 6),
          Text(w.prizeName ?? ''),
        ],
      )),
      DataCell(ModeBadge(w.mode)),
      DataCell(Text(when, style: const TextStyle(color: OpTheme.textMuted))),
    ]);
  }
}
