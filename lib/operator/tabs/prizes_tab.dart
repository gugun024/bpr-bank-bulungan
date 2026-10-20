import 'package:flutter/material.dart';

import '../../core/database.dart';
import '../../core/models.dart';
import '../../shared/theme.dart';
import '../widgets/prize_import_dialog.dart';
import '../widgets/ui_kit.dart';

/// Tab kelola daftar hadiah.
class PrizesTab extends StatefulWidget {
  const PrizesTab({super.key});

  @override
  State<PrizesTab> createState() => _PrizesTabState();
}

class _PrizesTabState extends State<PrizesTab> {
  List<Prize> _prizes = [];
  final Map<int, int> _wonCount = {};
  final Set<int> _selected = {}; // id hadiah terpilih (untuk hapus bulk)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final prizes = await db.getPrizes();
    final counts = <int, int>{};
    for (final p in prizes) {
      counts[p.id!] = await db.winnerCountForPrize(p.id!);
    }
    if (!mounted) return;
    setState(() {
      _prizes = prizes;
      _wonCount
        ..clear()
        ..addAll(counts);
    });
  }

  Future<void> _dialog({Prize? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final qtyCtrl =
        TextEditingController(text: (existing?.qty ?? 1).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Tambah Hadiah' : 'Ubah Hadiah'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Nama hadiah', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Jumlah (unit)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
    if (name.isEmpty) return;
    final db = DatabaseHelper.instance;
    if (existing == null) {
      final urutan = _prizes.isEmpty
          ? 1
          : _prizes.map((p) => p.urutan).reduce((a, b) => a > b ? a : b) + 1;
      await db.insertPrize(Prize(name: name, urutan: urutan, qty: qty));
    } else {
      await db.updatePrize(Prize(
          id: existing.id, name: name, urutan: existing.urutan, qty: qty));
    }
    await _load();
  }

  Future<void> _importCsv() async {
    final ok = await showPrizeImportDialog(context);
    if (ok) await _load();
  }

  void _toggleSelect(int id, bool v) {
    setState(() {
      if (v) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  Future<void> _delete(Prize p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus hadiah?'),
        content: Text('"${p.name}" akan dihapus dari daftar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    await _runDelete([p.id!]);
  }

  /// Hapus hadiah terpilih (bulk).
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus hadiah terpilih?'),
        content: Text('$n hadiah akan dihapus dari daftar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Hapus $n')),
        ],
      ),
    );
    if (ok != true) return;
    await _runDelete(_selected.toList());
  }

  Future<void> _runDelete(List<int> ids) async {
    try {
      if (ids.length == 1) {
        await DatabaseHelper.instance.deletePrize(ids.first);
      } else {
        await DatabaseHelper.instance.deletePrizes(ids);
      }
      if (!mounted) return;
      setState(() => _selected.clear());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ids.length} hadiah dihapus.')),
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: OpTheme.danger),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabHeader(
            title: 'Daftar Hadiah',
            subtitle:
                'Kelola hadiah yang diundi. Urutan mengikuti waktu penambahan.',
            actions: [
              OutlinedButton.icon(
                onPressed: _importCsv,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Import CSV'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _dialog(),
                style: OpTheme.primaryButton.copyWith(
                  padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah Hadiah'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_selected.isNotEmpty) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: OpTheme.navySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_box, color: OpTheme.navy, size: 20),
                  const SizedBox(width: 10),
                  Text('${_selected.length} hadiah terpilih',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: OpTheme.navy)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: const Text('Batal pilih'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _deleteSelected,
                    style: FilledButton.styleFrom(
                      backgroundColor: OpTheme.danger,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('Hapus ${_selected.length}'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _prizes.isEmpty
              ? const SizedBox(
                  height: 320,
                  child: EmptyState(
                    icon: Icons.card_giftcard_outlined,
                    title: 'Belum ada hadiah',
                    subtitle: 'Tambahkan hadiah dulu sebelum memulai undian.',
                  ),
                )
              : Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (var i = 0; i < _prizes.length; i++)
                      _prizeCard(_prizes[i], i),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _prizeCard(Prize p, int index) {
    final won = _wonCount[p.id] ?? 0;
    final left = p.qty - won;
    final done = left <= 0;
    final progress = p.qty > 0 ? (won / p.qty).clamp(0.0, 1.0) : 0.0;
    final selected = _selected.contains(p.id);
    return SizedBox(
      width: 340,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: OpTheme.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => _toggleSelect(p.id!, v == true),
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: done
                          ? [Colors.grey.shade400, Colors.grey.shade500]
                          : [OpTheme.gold, const Color(0xFFF3D27A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.card_giftcard,
                      color: done ? Colors.white : OpTheme.navyDark, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: OpTheme.navy)),
                      Text('Hadiah #${index + 1}',
                          style: const TextStyle(
                              fontSize: 12, color: OpTheme.textMuted)),
                    ],
                  ),
                ),
                if (done)
                  const StatusBadge('HABIS',
                      fg: OpTheme.danger, bg: OpTheme.dangerSoft)
                else
                  StatusBadge('Sisa $left',
                      fg: OpTheme.success, bg: OpTheme.successSoft),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: OpTheme.navySoft,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          done ? Colors.grey : OpTheme.gold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$won / ${p.qty} terundi',
                    style: const TextStyle(
                        fontSize: 12, color: OpTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _dialog(existing: p),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Ubah'),
                ),
                TextButton.icon(
                  onPressed: () => _delete(p),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Hapus'),
                  style: TextButton.styleFrom(foregroundColor: OpTheme.danger),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
