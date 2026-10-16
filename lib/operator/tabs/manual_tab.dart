import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/database.dart';
import '../../core/draw_service.dart';
import '../../core/models.dart';
import '../../shared/protocol.dart';
import '../../shared/theme.dart';
import '../widgets/ui_kit.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabHeader(
          title: 'Undian Manual',
          subtitle:
              'Ketik nomor kupon yang keluar dari alat roll, verifikasi, lalu tampilkan ke layar penonton.',
        ),
        const SizedBox(height: 20),
        OpCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _couponCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: OpTheme.navy,
                  ),
                  decoration: OpTheme.input('Nomor kupon',
                      hint: 'cth: 000068',
                      prefix: const Icon(Icons.confirmation_number_outlined,
                          color: OpTheme.navy)),
                  onSubmitted: (_) => _lookup(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _lookup,
                style: OpTheme.primaryButton,
                icon: const Icon(Icons.search),
                label: const Text('Cari'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          _banner(_error!, OpTheme.danger, Icons.error_outline),
        if (_rejectedInfo != null)
          _banner(_rejectedInfo!, OpTheme.danger, Icons.block, big: true),
        if (_found != null) _accountCard(_found!),
      ],
    );
  }

  Widget _banner(String text, Color color, IconData icon, {bool big = false}) {
    const soft = OpTheme.dangerSoft;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(big ? 20 : 14),
      decoration: BoxDecoration(
        color: soft,
        border:
            Border.all(color: color.withValues(alpha: 0.4), width: big ? 2 : 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: big ? 52 : 40,
            height: big ? 52 : 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(big ? 26 : 20),
            ),
            child: Icon(icon, color: Colors.white, size: big ? 30 : 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: OpTheme.danger,
                    fontWeight: big ? FontWeight.w800 : FontWeight.w600,
                    fontSize: big ? 17 : 14,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _accountCard(DrawResult res) {
    final a = res.account;
    final fmt = NumberFormat('#,###', 'id');
    return OpCardHeader(
      icon: Icons.verified_outlined,
      title: 'Kupon Terverifikasi',
      trailing: Account.formatCoupon(res.couponNo, _couponWidth),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const StatusBadge('Valid & belum menang',
                  fg: OpTheme.success, bg: OpTheme.successSoft),
              const Spacer(),
              Text('${a.kuponCount} kupon dimiliki',
                  style:
                      const TextStyle(color: OpTheme.textMuted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Text(a.nama.toUpperCase(),
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: OpTheme.navy,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          DetailRow('No. Rekening', a.rekening, highlight: true),
          if (a.rekeningLama.isNotEmpty) DetailRow('Rek. Lama', a.rekeningLama),
          if (a.alamat.isNotEmpty) DetailRow('Alamat', a.alamat),
          DetailRow('Saldo', 'Rp ${fmt.format(a.saldo)}'),
          DetailRow('Range kupon',
              '${Account.formatCoupon(a.couponStart, _couponWidth)} – ${Account.formatCoupon(a.couponEnd, _couponWidth)}'),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Prize>(
                  initialValue: _prize,
                  decoration: OpTheme.input('Hadiah untuk kupon ini'),
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
                style: OpTheme.goldButton,
                icon: const Icon(Icons.present_to_all),
                label: const Text('Tampilkan ke Layar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
