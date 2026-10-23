import 'dart:async';
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
import '../widgets/coupon_print_dialog.dart';
import '../widgets/import_dialog.dart';
import '../widgets/ui_kit.dart';

/// Susun baris CSV export Data Nasabah (header + satu baris per rekening).
List<List<String>> buildAccountsCsvRows(List<Account> accounts) {
  final rows = <List<String>>[
    [
      'No',
      'Rekening',
      'Rek. Lama',
      'Nama',
      'Alamat',
      'Saldo',
      'Jumlah Kupon',
      'Rentang Kupon',
      'Status',
    ],
  ];
  for (var i = 0; i < accounts.length; i++) {
    final a = accounts[i];
    rows.add([
      '${i + 1}',
      a.rekening,
      a.rekeningLama,
      a.nama,
      a.alamat,
      '${a.saldo}',
      '${a.kuponCount}',
      a.kuponCount > 0
          ? '${Account.formatCoupon(a.couponStart)}-${Account.formatCoupon(a.couponEnd)}'
          : '-',
      a.hasWon ? 'Sudah Menang' : 'Belum Menang',
    ]);
  }
  return rows;
}

/// Tab Data Nasabah: tabel data hasil import (paginasi + pencarian).
/// Import file dilakukan lewat modal dialog dari tombol "Import Data".
class DataTab extends StatefulWidget {
  const DataTab({super.key});

  @override
  State<DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<DataTab> {
  static const _pageSize = 100;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<Account> _rows = [];
  int _total = 0;
  int _page = 0;
  int _totalCoupons = 0;
  String _query = '';
  bool _busy = false;
  final Set<int> _selected = {}; // id rekening terpilih (untuk hapus bulk)

  // Urutan tabel: kolom DataTable -> AccountSort. Default = Rentang Kupon
  // naik (urutan nomor kupon, sama seperti sebelum fitur sort ada).
  int _sortColumn = 5;
  bool _sortAsc = true;
  static const _sortByColumn = <int, AccountSort>{
    1: AccountSort.rekening,
    2: AccountSort.nama,
    3: AccountSort.saldo,
    4: AccountSort.jumlahKupon,
    5: AccountSort.kupon,
    6: AccountSort.status,
  };
  AccountSort get _sort => _sortByColumn[_sortColumn] ?? AccountSort.kupon;

  /// Klik header kolom: kolom baru mulai dari naik (ASC); klik kolom yang
  /// sama membalik arah. Urutan berlaku ke seluruh hasil filter (di SQL),
  /// bukan hanya halaman yang tampil.
  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortAsc = columnIndex == _sortColumn ? ascending : true;
      _sortColumn = columnIndex;
      _page = 0;
    });
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final db = DatabaseHelper.instance;
      final total = await db.countAccountsFiltered(_query);
      final maxPage = total == 0 ? 0 : (total - 1) ~/ _pageSize;
      var page = _page;
      if (page > maxPage) page = maxPage;
      final rows = await db.getAccountsPage(
        limit: _pageSize,
        offset: page * _pageSize,
        query: _query,
        sort: _sort,
        ascending: _sortAsc,
      );
      final coupons = await db.totalCoupons();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _total = total;
        _page = page;
        _totalCoupons = coupons;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _query = v.trim();
        _page = 0;
      });
      _load();
    });
  }

  Future<void> _openImport() async {
    final ok = await showImportDialog(context);
    if (ok && mounted) {
      _searchCtrl.clear();
      setState(() {
        _query = '';
        _page = 0;
        _selected.clear();
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import selesai, tabel diperbarui.')),
        );
      }
    }
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

  void _toggleSelectPage(bool v) {
    setState(() {
      for (final a in _rows) {
        if (v) {
          _selected.add(a.id!);
        } else {
          _selected.remove(a.id);
        }
      }
    });
  }

  /// Hapus 1 rekening (konfirmasi). Nomor kupon sisanya dihitung ulang.
  Future<void> _deleteOne(Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus rekening?'),
        content: Text(
            '"${a.nama}" (${a.rekening}) akan dihapus.\n\n'
            'Nomor kupon rekening lain akan DIHITUNG ULANG berurutan — '
            'kupon kertas yang sudah tercetak TIDAK akan cocok lagi.'),
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
    await _runDelete({a.id!});
  }

  /// Hapus rekening terpilih (bulk).
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus rekening terpilih?'),
        content: Text(
            '$n rekening akan dihapus.\n\n'
            'Nomor kupon rekening lain akan DIHITUNG ULANG berurutan — '
            'kupon kertas yang sudah tercetak TIDAK akan cocok lagi.'),
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
    await _runDelete(Set.of(_selected));
  }

  /// Export CSV Data Nasabah. Bila ada rekening yang diceklis, yang
  /// diexport hanya pilihan itu; bila tidak ada, semua rekening yang
  /// cocok dengan kata pencarian aktif. Pola simpan sama seperti
  /// export Riwayat (tulis ke Documents + tawarkan lokasi lain).
  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final db = DatabaseHelper.instance;
      final accounts = _selected.isNotEmpty
          ? await db.getAccountsByIds(_selected.toList())
          : await db.getAccountsFiltered(_query,
              sort: _sort, ascending: _sortAsc);
      if (accounts.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada data untuk diexport.')),
        );
        return;
      }
      final csv =
          const ListToCsvConverter().convert(buildAccountsCsvRows(accounts));
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path,
          'nasabah_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv'));
      await file.writeAsString(csv);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan data nasabah',
        fileName: p.basename(file.path),
        bytes: await file.readAsBytes(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(savePath != null
                ? '${accounts.length} rekening tersimpan: $savePath'
                : '${accounts.length} rekening tersimpan di: ${file.path}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runDelete(Set<int> ids) async {
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.deleteAccounts(ids.toList());
      if (!mounted) return;
      setState(() => _selected.clear());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ids.length} rekening dihapus.')),
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Format rupiah Indonesia: 6889777 -> "6.889.777".
  static String _rp(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final couponWidth = _totalCoupons.toString().length.clamp(6, 12);
    final pages = _total == 0 ? 1 : ((_total - 1) ~/ _pageSize) + 1;
    final from = _total == 0 ? 0 : _page * _pageSize + 1;
    final to = (_page * _pageSize + _rows.length).clamp(0, _total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(
          title: 'Data Nasabah',
          subtitle:
              '$_total rekening • $_totalCoupons kupon total. Kupon memakai rentang nomor berurutan.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    CouponPrintDialog(db: DatabaseHelper.instance),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Cetak Kupon'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: (_busy || _total == 0) ? null : _exportCsv,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.download, size: 18),
              label: Text(_selected.isEmpty
                  ? 'Export CSV'
                  : 'Export CSV (${_selected.length})'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _openImport,
              style: OpTheme.primaryButton.copyWith(
                padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
              ),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Import Data'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: OpTheme.input('Cari nama / no. rekening…',
                    prefix: const Icon(Icons.search, color: OpTheme.navy)),
                onChanged: _onSearch,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_selected.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: OpTheme.navySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_box, color: OpTheme.navy, size: 20),
                const SizedBox(width: 10),
                Text('${_selected.length} rekening terpilih',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: OpTheme.navy)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selected.clear()),
                  child: const Text('Batal pilih'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _deleteSelected,
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
          const SizedBox(height: 12),
        ],
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _total == 0 && !_busy
              ? const OpCard(
                  child: SizedBox(
                    height: 320,
                    child: EmptyState(
                      icon: Icons.people_outline,
                      title: 'Belum ada data',
                      subtitle:
                          'Import file Excel/CSV dulu lewat tombol Import Data.',
                    ),
                  ),
                )
              : Container(
                  decoration: OpTheme.card(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SingleChildScrollView(
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          // Tabel minimal selebar kartu; kalau isi lebih lebar,
                          // scroll horizontal seperti biasa.
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                minWidth: constraints.maxWidth),
                            child: DataTable(
                          onSelectAll: (v) =>
                              _toggleSelectPage(v == true),
                          sortColumnIndex: _sortColumn,
                          sortAscending: _sortAsc,
                          headingRowColor:
                              WidgetStateProperty.all(OpTheme.navySoft),
                          headingTextStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: OpTheme.navy,
                              fontSize: 13),
                          dataTextStyle: const TextStyle(
                              fontSize: 13, color: Color(0xFF1E2A45)),
                          columns: [
                            const DataColumn(label: Text('No')),
                            DataColumn(
                                label: const Text('No. Rekening'),
                                onSort: _onSort),
                            DataColumn(
                                label: const Text('Nama'), onSort: _onSort),
                            DataColumn(
                                label: const Text('Saldo (Rp)'),
                                numeric: true,
                                onSort: _onSort),
                            DataColumn(
                                label: const Text('Kupon'),
                                numeric: true,
                                onSort: _onSort),
                            DataColumn(
                                label: const Text('Rentang Kupon'),
                                onSort: _onSort),
                            DataColumn(
                                label: const Text('Status'), onSort: _onSort),
                            const DataColumn(label: Text('Aksi')),
                          ],
                          rows: [
                            for (var i = 0; i < _rows.length; i++)
                              _row(_page * _pageSize + i + 1, _rows[i],
                                  couponWidth),
                          ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        // Footer paginasi.
        Row(
          children: [
            Text('Menampilkan $from–$to dari $_total',
                style: const TextStyle(fontSize: 13, color: OpTheme.textMuted)),
            const Spacer(),
            IconButton(
              onPressed: _page > 0
                  ? () {
                      setState(() => _page = 0);
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.first_page),
              tooltip: 'Halaman pertama',
            ),
            IconButton(
              onPressed: _page > 0
                  ? () {
                      setState(() => _page--);
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Sebelumnya',
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: OpTheme.navySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${_page + 1} / $pages',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: OpTheme.navy)),
            ),
            IconButton(
              onPressed: _page < pages - 1
                  ? () {
                      setState(() => _page++);
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Berikutnya',
            ),
            IconButton(
              onPressed: _page < pages - 1
                  ? () {
                      setState(() => _page = pages - 1);
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.last_page),
              tooltip: 'Halaman terakhir',
            ),
          ],
        ),
      ],
    );
  }

  DataRow _row(int no, Account a, int couponWidth) {
    final range = a.kuponCount > 0
        ? '${Account.formatCoupon(a.couponStart, couponWidth)}–${Account.formatCoupon(a.couponEnd, couponWidth)}'
        : '—';
    return DataRow(
      selected: _selected.contains(a.id),
      onSelectChanged: (v) => _toggleSelect(a.id!, v == true),
      cells: [
        DataCell(Text('$no', style: const TextStyle(color: OpTheme.textMuted))),
        DataCell(Text(a.rekening)),
        DataCell(
            Text(a.nama, style: const TextStyle(fontWeight: FontWeight.w700))),
        DataCell(Text(_rp(a.saldo),
            style:
                const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
        DataCell(Text('${a.kuponCount}',
            style: const TextStyle(fontWeight: FontWeight.w700))),
        DataCell(Text(range,
            style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                color: OpTheme.navy))),
        DataCell(a.hasWon
            ? const StatusBadge('Menang',
                fg: OpTheme.goldDark, bg: Color(0xFFFFF3C4))
            : const Text('—', style: TextStyle(color: OpTheme.textMuted))),
        DataCell(IconButton(
          icon: const Icon(Icons.delete_outline,
              size: 20, color: OpTheme.danger),
          tooltip: 'Hapus rekening',
          onPressed: _busy ? null : () => _deleteOne(a),
        )),
      ],
    );
  }
}
