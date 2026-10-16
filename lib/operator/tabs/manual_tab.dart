import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/database.dart';
import '../../core/draw_service.dart';
import '../../core/models.dart';
import '../../shared/protocol.dart';
import '../../shared/theme.dart';

/// Tab undian manual: ketik nomor kupon → validasi → pilih hadiah → tampilkan.
class ManualTab extends StatefulWidget {
  const ManualTab({super.key});

  @override
  State<ManualTab> createState() => _ManualTabState();
}

class _ManualTabState extends State<ManualTab> {
  final _couponCtrl = TextEditingController();
  final _svc = DrawService();
  DrawResult? _found;
  String? _error;
  String? _rejectedInfo; // info penolakan (sudah menang)
  List<Prize> _prizes = [];
  Prize? _prize;
  bool _busy = false;
  int _couponWidth = 6;

  @override
  void initState() {
    super.initState();
    _loadPrizes();
  }

  Future<void> _loadPrizes() async {
    final prizes = await DatabaseHelper.instance.getPrizes();
    final total = await DatabaseHelper.instance.totalCoupons();
    if (!mounted) return;
    setState(() {
      _prizes = prizes;
      _couponWidth = total.toString().length.clamp(6, 12);
      if (_prize == null || !prizes.any((p) => p.id == _prize!.id)) {
        _prize = prizes.isNotEmpty ? prizes.first : null;
      }
    });
  }

  Future<void> _lookup() async {
    setState(() {
      _error = null;
      _rejectedInfo = null;
      _found = null;
      _busy = true;
    });
    try {
      final n = DrawService.normalizeCouponInput(_couponCtrl.text);
      if (n == null) {
        setState(() => _error = 'Nomor kupon tidak valid.');
        return;
      }
      final res = await _svc.lookupCoupon(n);
      if (res == null) {
        setState(() => _error =
            'Kupon ${Account.formatCoupon(n, _couponWidth)} tidak dikenal.');
        return;
      }
      if (res.account.hasWon) {
        final db = DatabaseHelper.instance;
        final prize = await db.prizeNameOfAccount(res.account.id!);
        final when = await db.wonAtOfAccount(res.account.id!);
        String whenStr = '';
        if (when != null) {
          try {
            whenStr = DateFormat('d MMM yyyy HH:mm', 'id')
                .format(DateTime.parse(when));
          } catch (_) {
            whenStr = when;
          }
        }
        setState(() => _rejectedInfo =
            'Kupon ${Account.formatCoupon(n, _couponWidth)} milik ${res.account.nama} '
                '(${res.account.rekening}) SUDAH MENANG${prize != null ? ' "$prize"' : ''}'
                '${whenStr.isNotEmpty ? ' pada $whenStr' : ''}. Undi ulang!');
        return;
      }
      setState(() => _found = res);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final found = _found;
    final prize = _prize;
    if (found == null || prize == null) return;
    setState(() => _busy = true);
    try {
      await _svc.recordWinner(
        couponNo: found.couponNo,
        accountId: found.account.id!,
        prizeId: prize.id!,
        mode: 'manual',
      );
      await AudienceChannel.send(AudienceProtocol.showWinner, {
        AudienceProtocol.argCoupon:
            Account.formatCoupon(found.couponNo, _couponWidth),
        AudienceProtocol.argNama: found.account.nama,
        AudienceProtocol.argHadiah: prize.name,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Pemenang dicatat: ${found.account.nama} — ${prize.name}')),
      );
      setState(() {
        _found = null;
        _couponCtrl.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() {
      _found = null;
      _error = null;
      _rejectedInfo = null;
      _couponCtrl.clear();
    });
    _couponCtrl.selection = const TextSelection.collapsed(offset: 0);
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Undian Manual',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
              'Ketik nomor kupon yang keluar dari alat roll, lalu pilih hadiah.'),
          const SizedBox(height: 24),
          Row(
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _couponCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Nomor kupon',
                    hintText: 'cth: 000068',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _lookup(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _lookup,
                icon: const Icon(Icons.search),
                label: const Text('Cari'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                label: const Text('Tolak & Undi Lagi'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            _banner(_error!, Colors.red.shade700, Icons.error),
          if (_rejectedInfo != null)
            _banner(_rejectedInfo!, Colors.red.shade800, Icons.block,
                big: true),
          if (_found != null) _accountCard(_found!),
        ],
      ),
    );
  }

  Widget _banner(String text, Color color, IconData icon, {bool big = false}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(big ? 20 : 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color, width: big ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: big ? 40 : 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: color,
                      fontWeight: big ? FontWeight.bold : FontWeight.normal,
                      fontSize: big ? 18 : 14)),
            ),
          ],
        ),
      );

  Widget _accountCard(DrawResult res) {
    final a = res.account;
    final fmt = NumberFormat('#,###', 'id');
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.confirmation_number,
                    color: AudienceTheme.navy800, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Kupon ${Account.formatCoupon(res.couponNo, _couponWidth)}',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Icon(Icons.verified, color: Colors.green),
                const SizedBox(width: 4),
                const Text('Valid & belum menang',
                    style: TextStyle(color: Colors.green)),
              ],
            ),
            const Divider(height: 32),
            _kv('Nama', a.nama),
            _kv('No. Rekening', a.rekening),
            if (a.rekeningLama.isNotEmpty) _kv('Rek. Lama', a.rekeningLama),
            if (a.alamat.isNotEmpty) _kv('Alamat', a.alamat),
            _kv('Saldo', 'Rp ${fmt.format(a.saldo)}'),
            _kv('Jumlah kupon', '${a.kuponCount}'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Prize>(
                    initialValue: _prize,
                    decoration: const InputDecoration(
                      labelText: 'Hadiah',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final p in _prizes)
                        DropdownMenuItem(value: p, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() => _prize = v),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: (_busy || _prize == null) ? null : () => _submit(),
                  icon: const Icon(Icons.present_to_all),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Tampilkan ke Layar',
                        style: TextStyle(fontSize: 16)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AudienceTheme.navy800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 140,
                child: Text(k, style: const TextStyle(color: Colors.black54))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
