import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pth;
import 'package:path_provider/path_provider.dart';

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

  /// Pilih file gambar, salin ke folder aplikasi, simpan path-nya.
  /// Mengembalikan path tujuan, atau null bila batal.
  Future<String?> _pickAndStoreImage(Prize p) async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    final src = res?.files.single.path;
    if (src == null) return null;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(pth.join(docs.path, 'gambar_hadiah'));
    await dir.create(recursive: true);
    var ext = pth.extension(src).toLowerCase();
    if (ext.isEmpty) ext = '.png';
    // Bersihkan salinan berekstensi lain dari gambar sebelumnya.
    for (final e in ['.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif']) {
      if (e == ext) continue;
      final old = File(pth.join(dir.path, 'hadiah_${p.id}$e'));
      if (await old.exists()) await old.delete();
    }
    final dest = pth.join(dir.path, 'hadiah_${p.id}$ext');
    await File(src).copy(dest);
    await DatabaseHelper.instance.setPrizeImage(p.id!, dest);
    return dest;
  }

  /// Dialog kelola gambar satu hadiah: pratinjau + pasang/ganti/hapus.
  Future<void> _imageDialog(Prize p) async {
    var current = p.imagePath;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Gambar — ${p.name}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'Gambar tampil di kiri & kanan layar penonton saat '
                    'hadiah ini diundi. Pakai gambar produk berlatar polos '
                    'untuk hasil terbaik.',
                    style:
                        TextStyle(fontSize: 12.5, color: OpTheme.textMuted)),
                const SizedBox(height: 14),
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: OpTheme.cardBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: current.isNotEmpty && File(current).existsSync()
                      ? Image.file(File(current), fit: BoxFit.contain)
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_not_supported_outlined,
                                  size: 40, color: OpTheme.textMuted),
                              SizedBox(height: 8),
                              Text('Belum ada gambar',
                                  style: TextStyle(color: OpTheme.textMuted)),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            if (current.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await DatabaseHelper.instance.setPrizeImage(p.id!, '');
                  final f = File(current);
                  if (await f.exists()) await f.delete();
                  setDlg(() => current = '');
                  _load();
                },
                style:
                    TextButton.styleFrom(foregroundColor: OpTheme.danger),
                child: const Text('Hapus Gambar'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final stored = await _pickAndStoreImage(p);
                if (stored != null) {
                  setDlg(() => current = stored);
                  _load();
                }
              },
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(current.isEmpty ? 'Pilih Gambar' : 'Ganti Gambar'),
            ),
          ],
        ),
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
            if (p.imagePath.isNotEmpty && File(p.imagePath).existsSync()) ...[
              const SizedBox(height: 12),
              Container(
                height: 110,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: OpTheme.cardBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(File(p.imagePath), fit: BoxFit.contain),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _imageDialog(p),
                  icon: Icon(
                      p.imagePath.isEmpty
                          ? Icons.add_photo_alternate_outlined
                          : Icons.image_outlined,
                      size: 16),
                  label: const Text('Gambar'),
                ),
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
