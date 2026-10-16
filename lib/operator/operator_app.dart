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

  @override
  void initState() {
    super.initState();
    _initWindow();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('Undian Bank - Operator');
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
        colorScheme: ColorScheme.fromSeed(seedColor: AudienceTheme.navy800),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Undian Bank — Operator'),
          backgroundColor: AudienceTheme.navy800,
          foregroundColor: Colors.white,
          actions: [
            _audienceOpen
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.monitor, color: Colors.lightGreenAccent),
                      const SizedBox(width: 8),
                      const Text('Layar penonton aktif',
                          style: TextStyle(color: Colors.white70)),
                      IconButton(
                        tooltip: 'Reset ke splash',
                        icon: const Icon(Icons.refresh),
                        onPressed: () =>
                            AudienceChannel.send(AudienceProtocol.showIdle),
                      ),
                      IconButton(
                        tooltip: 'Sembunyikan layar penonton',
                        icon: const Icon(Icons.close),
                        onPressed: _hideAudience,
                      ),
                    ],
                  )
                : TextButton.icon(
                    onPressed: _openAudience,
                    icon: const Icon(Icons.monitor, color: Colors.white),
                    label: const Text('Buka Layar Penonton',
                        style: TextStyle(color: Colors.white)),
                  ),
            const SizedBox(width: 12),
          ],
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final t in tabs)
                  NavigationRailDestination(
                    icon: Icon(t.icon),
                    label: Text(t.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: tabs[_tab].body),
          ],
        ),
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final Widget body;
  const _Tab(this.label, this.icon, this.body);
}
