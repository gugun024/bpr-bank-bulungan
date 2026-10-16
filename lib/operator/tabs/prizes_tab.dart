import 'package:flutter/material.dart';

import '../../core/database.dart';
import '../../core/models.dart';

/// Tab kelola daftar hadiah.
class PrizesTab extends StatefulWidget {
  const PrizesTab({super.key});

  @override
  State<PrizesTab> createState() => _PrizesTabState();
}

class _PrizesTabState extends State<PrizesTab> {
  List<Prize> _prizes = [];
  final Map<int, int> _wonCount = {};

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
    if (ok == true) {
      await DatabaseHelper.instance.deletePrize(p.id!);
      await _load();
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
              Text('Daftar Hadiah',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _dialog(),
                icon: const Icon(Icons.add),
                label: const Text('Tambah Hadiah'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _prizes.isEmpty
                ? const Center(child: Text('Belum ada hadiah. Tambahkan dulu.'))
                : ListView.separated(
                    itemCount: _prizes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final p = _prizes[i];
                      final won = _wonCount[p.id] ?? 0;
                      final left = p.qty - won;
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(p.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            'Terundi: $won / ${p.qty}${left <= 0 ? ' — HABIS' : ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Ubah',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _dialog(existing: p),
                            ),
                            IconButton(
                              tooltip: 'Hapus',
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _delete(p),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
