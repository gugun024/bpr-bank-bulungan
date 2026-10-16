import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../shared/theme.dart';

/// Header standar tiap tab: judul + subjudul + tombol aksi di kanan.
class TabHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const TabHeader(
      {super.key,
      required this.title,
      required this.subtitle,
      this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: OpTheme.tabTitle),
              const SizedBox(height: 4),
              Text(subtitle, style: OpTheme.tabSubtitle),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

/// Kartu putih standar dengan padding 20.
class OpCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;

  const OpCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20),
      this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: OpTheme.card(),
      child: child,
    );
  }
}

/// Kartu dengan header navy (judul putih) + body.
class OpCardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final Widget body;

  const OpCardHeader(
      {super.key,
      required this.icon,
      required this.title,
      this.trailing,
      required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: OpTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: OpTheme.cardHeader(),
            child: Row(
              children: [
                Icon(icon, color: OpTheme.gold, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
                if (trailing != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: OpTheme.gold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(trailing!,
                        style: const TextStyle(
                            color: OpTheme.navyDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(20), child: body),
        ],
      ),
    );
  }
}

/// Kotak statistik kecil: ikon + angka besar + label.
class StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  const StatTile(
      {super.key,
      required this.icon,
      required this.value,
      required this.label,
      this.accent = OpTheme.navy});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: OpTheme.card(),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: OpTheme.navy)),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, color: OpTheme.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status kosong: ikon dalam lingkaran + pesan.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: OpTheme.navySoft,
              borderRadius: BorderRadius.circular(36),
            ),
            child: Icon(icon, size: 34, color: OpTheme.navy),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: OpTheme.navy)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(fontSize: 13, color: OpTheme.textMuted),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Badge mode undian: manual (navy) / random (gold).
class ModeBadge extends StatelessWidget {
  final String mode; // 'manual' | 'random'
  const ModeBadge(this.mode, {super.key});

  @override
  Widget build(BuildContext context) {
    final isManual = mode == 'manual';
    final bg = isManual ? OpTheme.navySoft : OpTheme.goldSoft;
    final fg = isManual ? OpTheme.navy : OpTheme.goldDark;
    final icon = isManual ? Icons.keyboard : Icons.casino;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(mode == 'manual' ? 'Manual' : 'Random',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

/// Badge status kecil (mis. HABIS, valid).
class StatusBadge extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;

  const StatusBadge(this.text, {super.key, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Baris label : nilai untuk detail.
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const DetailRow(this.label, this.value, {super.key, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 150,
              child: Text(label,
                  style:
                      const TextStyle(color: OpTheme.textMuted, fontSize: 13))),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: highlight ? 15 : 14,
                    color: highlight ? OpTheme.navy : const Color(0xFF1E2A45))),
          ),
        ],
      ),
    );
  }
}

/// Pemilih hadiah sekali klik (chip): lebih cepat dari dropdown untuk
/// operator saat acara live. Hadiah habis tampil abu-abu & tak bisa diklik.
class PrizePicker extends StatelessWidget {
  final List<Prize> prizes;
  final int Function(Prize) remainingOf;
  final Prize? selected;
  final ValueChanged<Prize?> onChanged;

  const PrizePicker({
    super.key,
    required this.prizes,
    required this.remainingOf,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (prizes.isEmpty) {
      return const Text('Belum ada hadiah. Tambahkan di tab Hadiah.',
          style: TextStyle(color: OpTheme.textMuted, fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < prizes.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _chip(prizes[i]),
        ],
      ],
    );
  }

  Widget _chip(Prize p) {
    final left = remainingOf(p);
    final done = left <= 0;
    final sel = selected;
    final isSel = sel != null && sel.id == p.id;
    final String name = p.name;
    return InkWell(
      onTap: done ? null : () => onChanged(p),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: isSel
              ? OpTheme.navy
              : done
                  ? const Color(0xFFF1F4F9)
                  : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSel
                ? OpTheme.gold
                : done
                    ? OpTheme.cardBorder
                    : OpTheme.navy.withValues(alpha: 0.25),
            width: isSel ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.card_giftcard,
                size: 20,
                color: isSel
                    ? OpTheme.gold
                    : done
                        ? Colors.grey
                        : OpTheme.navy),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isSel
                          ? Colors.white
                          : done
                              ? Colors.grey
                              : OpTheme.navy)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSel
                    ? OpTheme.gold
                    : done
                        ? Colors.grey.shade300
                        : OpTheme.navySoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(done ? 'HABIS' : 'Sisa $left',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isSel
                          ? OpTheme.navyDark
                          : done
                              ? Colors.grey.shade700
                              : OpTheme.navy)),
            ),
          ],
        ),
      ),
    );
  }
}
