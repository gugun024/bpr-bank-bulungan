import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/protocol.dart';
import '../shared/theme.dart';
import 'tabs/history_tab.dart';
import 'tabs/import_tab.dart';
import 'tabs/manual_tab.dart';
import 'tabs/prizes_tab.dart';
import 'tabs/random_tab.dart';

/// Window operator: kontrol penuh jalannya undian.
class OperatorApp extends StatefulWidget {
  const OperatorApp({super.key});

  @override
  State<OperatorApp> createState() => _OperatorAppState();
}

class _OperatorAppState extends State<OperatorApp> {
  int _tab = 0;
  WindowController? _audienceController;
  bool _audienceOpen = false;
  bool _openingAudience = false; // cegah klik ganda -> window dobel

  @override
  void initState() {
    super.initState();
    _initWindow();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('PT. BPR Bank Bulungan - Operator');
    await windowManager.setMinimumSize(const Size(1100, 720));
  }

  /// Cari window penonton yang sudah ada (biar tidak dobel).
  Future<WindowController?> _findAudience() async {
    try {
      final all = await WindowController.getAll();
      for (final c in all) {
        if (c.arguments == 'audience') return c;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _openAudience() async {
    if (_openingAudience) return; // cegah race: klik ganda
    if (mounted) setState(() => _openingAudience = true);
    try {
      var controller = await _findAudience();
      controller ??= await WindowController.create(
        const WindowConfiguration(arguments: 'audience'),
      );
      _audienceController = controller;
      await controller.show();
      AudienceChannel.enabled = true;
      // Kirim splash awal.
      await AudienceChannel.send(AudienceProtocol.showIdle);
      if (mounted) setState(() => _audienceOpen = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka layar penonton: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingAudience = false);
    }
  }

  Future<void> _hideAudience() async {
    final controller = _audienceController;
    if (controller != null) {
      try {
        await controller.hide();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _audienceOpen = false;
        _audienceController = null;
        AudienceChannel.enabled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const _Tab('Undi Manual', Icons.keyboard, ManualTab()),
      const _Tab('Undi Random', Icons.casino, RandomTab()),
      const _Tab('Hadiah', Icons.card_giftcard, PrizesTab()),
      const _Tab('Riwayat', Icons.history, HistoryTab()),
      const _Tab('Import Data', Icons.upload_file, ImportTab()),
    ];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: OpTheme.navy),
        useMaterial3: true,
        scaffoldBackgroundColor: OpTheme.bg,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              _BankMark(),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PT. BPR Bank Bulungan',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('Aplikasi Undian Berhadiah — Operator',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: OpTheme.textMuted)),
                ],
              ),
            ],
          ),
          backgroundColor: Colors.white,
          foregroundColor: OpTheme.navy,
          elevation: 0,
          shape: const Border(bottom: BorderSide(color: OpTheme.cardBorder)),
          actions: [
            _audienceOpen
                ? Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: OpTheme.successSoft,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: OpTheme.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: OpTheme.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Layar Penonton Aktif',
                            style: TextStyle(
                                color: OpTheme.success,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Reset ke splash',
                          icon: const Icon(Icons.refresh, size: 18),
                          color: OpTheme.success,
                          onPressed: () =>
                              AudienceChannel.send(AudienceProtocol.showIdle),
                        ),
                        IconButton(
                          tooltip: 'Sembunyikan layar penonton',
                          icon: const Icon(Icons.close, size: 18),
                          color: OpTheme.success,
                          onPressed: _hideAudience,
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: FilledButton.icon(
                      onPressed: _openingAudience ? null : _openAudience,
                      style: OpTheme.primaryButton.copyWith(
                        padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 0)),
                      ),
                      icon: _openingAudience
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white70),
                            )
                          : const Icon(Icons.monitor, size: 18),
                      label: Text(_openingAudience
                          ? 'Membuka...'
                          : 'Buka Layar Penonton'),
                    ),
                  ),
            const SizedBox(width: 16),
          ],
        ),
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: OpTheme.navyDark,
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -1.0,
              leading: const Padding(
                padding: EdgeInsets.only(top: 20, bottom: 12),
                child: _BankMark(size: 46),
              ),
              unselectedIconTheme:
                  const IconThemeData(color: Colors.white38, size: 24),
              selectedIconTheme:
                  const IconThemeData(color: OpTheme.gold, size: 24),
              unselectedLabelTextStyle:
                  const TextStyle(color: Colors.white38, fontSize: 11),
              selectedLabelTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
              indicatorColor: OpTheme.gold.withValues(alpha: 0.16),
              indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              destinations: [
                for (final t in tabs)
                  NavigationRailDestination(
                    icon: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Icon(t.icon)),
                    label: Text(t.label),
                  ),
              ],
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: tabs[_tab].body,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo mini "BPR" gold di sidebar & appbar.
class _BankMark extends StatelessWidget {
  final double size;
  const _BankMark({this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [OpTheme.gold, Color(0xFFF3D27A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: Text('BPR',
          style: TextStyle(
              color: OpTheme.navyDark,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.26,
              letterSpacing: 0.5)),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final Widget body;
  const _Tab(this.label, this.icon, this.body);
}
