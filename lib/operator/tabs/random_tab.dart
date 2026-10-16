import 'package:flutter/material.dart';

import '../../core/database.dart';
import '../../core/draw_service.dart';
import '../../core/models.dart';
import '../../shared/protocol.dart';
import '../../shared/theme.dart';

/// Tab undian random (berbobot): kocok → konfirmasi → tampilkan.
class RandomTab extends StatefulWidget {
  const RandomTab({super.key});

  @override
  State<RandomTab> createState() => _RandomTabState();
}

class _RandomTabState extends State<RandomTab> {
  final _svc = DrawService();
  List<Prize> _prizes = [];
  Prize? _prize;
  DrawResult? _drawn;
  bool _busy = false;
  int _pool = 0;
  int _couponWidth = 6;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final db = DatabaseHelper.instance;
    final prizes = await db.getPrizes();
    final pool = await db.totalCoupons();
    if (!mounted) return;
    setState(() {
      _prizes = prizes;
      _pool = pool;
      _couponWidth = pool.toString().length.clamp(6, 12);
      if (_prize == null || !prizes.any((p) => p.id == _prize!.id)) {
        _prize = prizes.isNotEmpty ? prizes.first : null;
      }
    });
  }

  Future<void> _shuffle() async {
    if (_prize == null || _busy) return;
    setState(() {
      _busy = true;
      _drawn = null;
    });
    try {
      await AudienceChannel.send(AudienceProtocol.startShuffle, {
        AudienceProtocol.argHadiah: _prize!.name,
      });
      // Beri waktu animasi kocokan di layar penonton, lalu kunci hasil.
      await Future.delayed(const Duration(seconds: 4));
      final res = await _svc.drawRandom();
      await AudienceChannel.send(AudienceProtocol.stopShuffle);
      if (!mounted) return;
      if (res == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pool kosong — semua sudah menang.')),
        );
      } else {
        setState(() => _drawn = res);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final drawn = _drawn;
    final prize = _prize;
    if (drawn == null || prize == null) return;
    setState(() => _busy = true);
    try {
      await _svc.recordWinner(
        couponNo: drawn.couponNo,
        accountId: drawn.account.id!,
        prizeId: prize.id!,
        mode: 'random',
      );
      await AudienceChannel.send(AudienceProtocol.showWinner, {
        AudienceProtocol.argCoupon:
            Account.formatCoupon(drawn.couponNo, _couponWidth),
        AudienceProtocol.argNama: drawn.account.nama,
        AudienceProtocol.argHadiah: prize.name,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Pemenang dicatat: ${drawn.account.nama} — ${prize.name}')),
      );
      setState(() => _drawn = null);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    setState(() => _drawn = null);
    AudienceChannel.send(AudienceProtocol.showIdle);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Undian Random',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
              'Pool saat ini: $_pool kupon eligible (sudah menang otomatis dikecualikan). '
              'Makin banyak kupon, makin besar peluang.'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Prize>(
                  initialValue: _prize,
                  decoration: const InputDecoration(
                    labelText: 'Hadiah yang diundi',
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
                onPressed:
                    (_busy || _prize == null || _pool == 0) ? null : _shuffle,
                icon: const Icon(Icons.casino),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Kocok', style: TextStyle(fontSize: 16)),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AudienceTheme.navy800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_drawn != null) _resultCard(_drawn!),
        ],
      ),
    );
  }

  Widget _resultCard(DrawResult res) {
    final a = res.account;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.emoji_events, color: Colors.amber, size: 32),
                SizedBox(width: 12),
                Text('Hasil kocokan',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Kupon ${Account.formatCoupon(res.couponNo, _couponWidth)}',
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 8),
            Text('Nama: ${a.nama}', style: const TextStyle(fontSize: 18)),
            Text('No. Rekening: ${a.rekening}',
                style: const TextStyle(fontSize: 18)),
            Text('Hadiah: ${_prize?.name ?? '-'}',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _confirm,
                  icon: const Icon(Icons.present_to_all),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Konfirmasi & Tampilkan',
                        style: TextStyle(fontSize: 16)),
                  ),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Batalkan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
