import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/database.dart';
import '../../core/draw_service.dart';
import '../../core/models.dart';
import '../../shared/protocol.dart';
import '../../shared/sounds.dart';
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
  Map<int, int> _remaining = {}; // prizeId -> sisa kuota
  bool _busy = false;
  int _couponWidth = 6;
  // Tampilkan info penolakan (kupon sudah menang) ke layar penonton?
  // Default mati — penolakan hanya tampil di operator. Disimpan di DB.
  static const _kShowRejected = 'show_rejected_on_audience';
  bool _showRejectedOnAudience = false;
  // Pilihan hadiah terakhir operator — disimpan per tab agar tidak kereset
  // saat pindah tab (State tab dibuang dari tree tiap ganti halaman).
  static const _kSelectedPrize = 'selected_prize_manual';

  @override
  void initState() {
    super.initState();
    _loadPrizes();
    _loadToggle();
  }

  /// Muat preferensi toggle dari database.
  Future<void> _loadToggle() async {
    final v =
        await DatabaseHelper.instance.getSetting(_kShowRejected);
    if (!mounted) return;
    setState(() => _showRejectedOnAudience = v == '1');
  }

  /// Simpan preferensi toggle ke database.
  Future<void> _saveToggle(bool v) async {
    setState(() => _showRejectedOnAudience = v);
    await DatabaseHelper.instance.setSetting(_kShowRejected, v ? '1' : '0');
  }

  int _left(Prize p) => _remaining[p.id] ?? p.qty;

  Future<void> _loadPrizes() async {
    final db = DatabaseHelper.instance;
    final prizes = await db.getPrizes();
    final total = await db.totalCoupons();
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
      _couponWidth = total.toString().length.clamp(6, 12);
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
    // Umumkan "hadiah berikutnya" ke layar penonton.
    if (p != null) {
      AudienceChannel.send(AudienceProtocol.showPrize, {
        AudienceProtocol.argHadiah: p.name,
        AudienceProtocol.argGambar: p.imagePath,
      });
    }
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
        final couponStr = Account.formatCoupon(n, _couponWidth);
        setState(() => _error =
            'Kupon $couponStr tidak terdaftar. Periksa ketikan & coba lagi.');
        // Nomor keluar di depan penonton — sampaikan valid/tidaknya
        // bila toggle aktif.
        if (_showRejectedOnAudience) {
          await AudienceChannel.send(AudienceProtocol.showNotFound, {
            AudienceProtocol.argCoupon: couponStr,
          });
        }
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
        // Opsional: teruskan info penolakan ke layar penonton.
        if (_showRejectedOnAudience) {
          await AudienceChannel.send(AudienceProtocol.showRejected, {
            AudienceProtocol.argCoupon:
                Account.formatCoupon(n, _couponWidth),
            AudienceProtocol.argNama: res.account.nama,
            AudienceProtocol.argRekening: res.account.rekening,
            AudienceProtocol.argHadiah: prize ?? '',
            AudienceProtocol.argWaktu: whenStr,
          });
        }
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
        AudienceProtocol.argAlamat: found.account.alamat,
        AudienceProtocol.argGambar: prize.imagePath,
        AudienceProtocol.argHadiah: prize.name,
      });
      // Suara reveal (tick melambat 2,6 dtk + fanfare) diputar dari
      // window operator — sinkron dengan animasi slot di penonton.
      Sounds.playReveal();
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
      await _loadPrizes(); // refresh sisa kuota hadiah
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: OpTheme.danger),
        );
        await _loadPrizes();
      }
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
    Sounds.stopReveal();
    _couponCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Layout: header tetap di atas; kiri (daftar hadiah) scroll mandiri;
    // kanan: kartu input kupon FIXED (tidak ikut scroll), hasil di bawahnya
    // scroll mandiri bila kontennya panjang.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabHeader(
          title: 'Undian Manual',
          subtitle:
              'Pilih hadiah dulu, lalu ketik nomor kupon dari alat roll dan tampilkan ke layar penonton.',
        ),
        const SizedBox(height: 20),
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
              // KANAN: input kupon FIXED + hasil (scroll mandiri)
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        TextField(
                          controller: _couponCtrl,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            // Batasi 6 digit — cegah ketikan kepanjangan.
                            LengthLimitingTextInputFormatter(6),
                          ],
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6,
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: OpTheme.navy,
                          ),
                          decoration: OpTheme.input('Nomor kupon',
                              hint: 'cth: 000068',
                              prefix: const Icon(
                                  Icons.confirmation_number_outlined,
                                  color: OpTheme.navy)),
                          onSubmitted: (_) => _lookup(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed:
                                    (_busy || _prize == null) ? null : _lookup,
                                style: OpTheme.primaryButton,
                                icon: const Icon(Icons.search),
                                label: const Text('Cari'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _reset,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 18),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reset'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Opsi: tampilkan penolakan (kupon sudah menang)
                        // ke layar penonton atau hanya di operator.
                        Row(
                          children: [
                            const Icon(Icons.monitor_outlined,
                                size: 18, color: OpTheme.textMuted),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Tampilkan hasil validasi di layar penonton',
                                style: TextStyle(
                                    fontSize: 13, color: OpTheme.textMuted),
                              ),
                            ),
                            Switch(
                              value: _showRejectedOnAudience,
                              activeThumbColor: OpTheme.navy,
                              onChanged: _saveToggle,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Hasil: banner error/penolakan & kartu akun — scroll
                  // mandiri, input kupon di atas tetap tidak bergerak.
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_busy) const LinearProgressIndicator(),
                          if (_error != null)
                            _banner(_error!, OpTheme.danger,
                                Icons.error_outline),
                          if (_rejectedInfo != null)
                            _banner(_rejectedInfo!, OpTheme.danger,
                                Icons.block,
                                big: true),
                          if (_found != null) _accountCard(_found!),
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
    ]);
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
          FilledButton.icon(
            onPressed: (_busy || _prize == null) ? null : () => _submit(),
            style: OpTheme.goldButton.copyWith(
              minimumSize:
                  WidgetStateProperty.all(const Size(double.infinity, 56)),
            ),
            icon: const Icon(Icons.present_to_all),
            label: Text(_prize == null
                ? 'Tampilkan ke Layar'
                : 'Tampilkan ke Layar — ${_prize!.name}'),
          ),
        ],
      ),
    );
  }
}
