import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database.dart';
import '../../core/models.dart';
import '../../shared/theme.dart';
import '../widgets/coupon_print_dialog.dart';
import '../widgets/import_dialog.dart';
import '../widgets/ui_kit.dart';

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
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import selesai, tabel diperbarui.')),
        );
      }
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
                            DataColumn(label: Text('No. Rekening')),
                            DataColumn(label: Text('Nama')),
                            DataColumn(
                                label: Text('Saldo (Rp)'), numeric: true),
                            DataColumn(label: Text('Kupon'), numeric: true),
                            DataColumn(label: Text('Rentang Kupon')),
                            DataColumn(label: Text('Status')),
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
    return DataRow(cells: [
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
    ]);
  }
}
