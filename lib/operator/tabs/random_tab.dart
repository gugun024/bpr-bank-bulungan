import 'package:flutter/material.dart';

import '../../core/database.dart';
import '../../core/draw_service.dart';
import '../../core/models.dart';
import '../../shared/protocol.dart';
import '../../shared/sounds.dart';
import '../../shared/theme.dart';
import '../widgets/ui_kit.dart';

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
  Map<int, int> _remaining = {};
  DrawResult? _drawn;
  bool _busy = false;
  int _pool = 0;
  int _winners = 0;
  int _couponWidth = 6;
  // Pilihan hadiah terakhir operator — disimpan per tab agar tidak kereset
  // saat pindah tab (State tab dibuang dari tree tiap ganti halaman).
  static const _kSelectedPrize = 'selected_prize_random';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    // Tab dibuang dari tree saat pindah halaman — pastikan tick kocokan
    // tidak menggantung menyala.
    Sounds.stopShuffleTicks();
    super.dispose();
  }

  int _left(Prize p) => _remaining[p.id] ?? p.qty;

  Future<void> _refresh() async {
    final db = DatabaseHelper.instance;
    final prizes = await db.getPrizes();
    final pool = await db.totalCoupons();
    final winners = (await db.getWinners()).length;
    final remaining = <int, int>{};
    for (final p in prizes) {
      remaining[p.id!] = p.qty - await db.winnerCountForPrize(p.id!);
    }
    // Pilihan hadiah terakhir operator (per tab) — dipulihkan bila masih ada.
    final savedId = int.tryParse(await db.getSetting(_kSelectedPrize) ?? '');
    if (!mounted) return;
    setState(() {
      _prizes = prizes;
      _remaining = remaining;
      _pool = pool;
      _winners = winners;
      _couponWidth = pool.toString().length.clamp(6, 12);
      if (_prize == null ||
          !prizes.any((p) => p.id == _prize!.id) ||
          _left(_prize!) <= 0) {
        _prize = null;
        // 1) Pulihkan pilihan terakhir operator bila masih tersedia.
        if (savedId != null) {
          for (final p in prizes) {
            if (p.id == savedId && _left(p) > 0) {
              _prize = p;
              break;
            }
          }
        }
        // 2) Kalau tidak ada, pilih hadiah pertama yang masih ada sisa.
        if (_prize == null) {
          for (final p in prizes) {
            if (_left(p) > 0) {
              _prize = p;
              break;
            }
          }
        }
      }
    });
  }

  void _onPrizeChanged(Prize? p) {
    setState(() => _prize = p);
    // Ingat pilihan ini (per tab) agar tidak kereset saat pindah tab.
    DatabaseHelper.instance
        .setSetting(_kSelectedPrize, p?.id?.toString() ?? '');
    if (p != null) {
      AudienceChannel.send(AudienceProtocol.showPrize, {
        AudienceProtocol.argHadiah: p.name,
        AudienceProtocol.argGambar: p.imagePath,
      });
    }
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
        AudienceProtocol.argGambar: _prize!.imagePath,
      });
      // Tick kocokan diputar dari window operator selama penonton
      // ng-roll; berhenti saat Konfirmasi / Batal / pool kosong.
      Sounds.startShuffleTicks();
      // Hasil langsung dihitung & ditampilkan ke operator; layar penonton
      // TERUS ng-roll tanpa henti sampai operator Konfirmasi / Batalkan.
      // (Tidak ada stopShuffle di tengah — penonton tidak boleh melihat
      // nomor beku yang bukan hasil asli.)
      final res = await _svc.drawRandom();
      if (!mounted) return;
      if (res == null) {
        Sounds.stopShuffleTicks();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pool kosong — semua sudah menang.')),
        );
        await AudienceChannel.send(AudienceProtocol.showIdle);
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
        AudienceProtocol.argAlamat: drawn.account.alamat,
        AudienceProtocol.argGambar: prize.imagePath,
        AudienceProtocol.argHadiah: prize.name,
      });
      // Kocokan berhenti, ganti urutan reveal (tick melambat + fanfare).
      Sounds.stopShuffleTicks();
      Sounds.playReveal();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Pemenang dicatat: ${drawn.account.nama} — ${prize.name}')),
      );
      setState(() => _drawn = null);
      await _refresh();
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: OpTheme.danger),
        );
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    Sounds.stopShuffleTicks();
    setState(() => _drawn = null);
    AudienceChannel.send(AudienceProtocol.showIdle);
  }

  @override
  Widget build(BuildContext context) {
    // Layout: header + stat tetap di atas; kiri (daftar hadiah) scroll
    // mandiri; kanan: tombol Kocok FIXED, kartu hasil scroll mandiri.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabHeader(
          title: 'Undian Random',
          subtitle:
              'Kocok otomatis berbobot: makin banyak kupon, makin besar peluang. Pemenang lama otomatis dikecualikan.',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            StatTile(
                icon: Icons.confirmation_number_outlined,
                value: '$_pool',
                label: 'Total kupon',
                accent: OpTheme.navy),
            const SizedBox(width: 12),
            StatTile(
                icon: Icons.emoji_events_outlined,
                value: '$_winners',
                label: 'Sudah menang',
                accent: OpTheme.goldDark),
            const SizedBox(width: 12),
            StatTile(
                icon: Icons.card_giftcard_outlined,
                value: '${_prizes.length}',
                label: 'Hadiah terdaftar',
                accent: OpTheme.success),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KIRI: pilih hadiah (scroll mandiri)
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  child: OpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Hadiah yang diundi',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: OpTheme.navy)),
                        const SizedBox(height: 8),
                        PrizePicker(
                          prizes: _prizes,
                          remainingOf: _left,
                          selected: _prize,
                          onChanged: _onPrizeChanged,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // KANAN: tombol Kocok FIXED + hasil (scroll mandiri)
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OpCard(
                      child: FilledButton.icon(
                        onPressed: (_busy || _prize == null || _pool == 0)
                            ? null
                            : _shuffle,
                        style: OpTheme.primaryButton.copyWith(
                          minimumSize: WidgetStateProperty.all(
                              const Size(double.infinity, 56)),
                        ),
                        icon: const Icon(Icons.casino),
                        label: Text(
                            _prize == null ? 'Kocok' : 'Kocok — ${_prize!.name}'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_busy) const LinearProgressIndicator(),
                            if (_drawn != null) _resultCard(_drawn!),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultCard(DrawResult res) {
    final a = res.account;
    return OpCardHeader(
      icon: Icons.emoji_events,
      title: 'Hasil Kocokan',
      trailing: Account.formatCoupon(res.couponNo, _couponWidth),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          DetailRow('Hadiah', _prize?.name ?? '-'),
          DetailRow('Peluang', '${a.kuponCount} dari $_pool kupon'),
          const SizedBox(height: 20),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: OpTheme.success,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                icon: const Icon(Icons.present_to_all),
                label: const Text('Konfirmasi & Tampilkan'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _cancel,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.close),
                label: const Text('Batalkan'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
