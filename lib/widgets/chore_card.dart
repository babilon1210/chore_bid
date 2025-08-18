import 'dart:math';
import 'package:chore_bid/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChoreCard extends StatelessWidget {
  final String title;
  final String reward;
  final String status; // may be 'expired'
  final Map<String, String>? progress; // childId -> status
  final List<String> assignedTo;
  final VoidCallback? onTap;
  final DateTime deadline;
  final bool isExclusive;

  final int colorSeed;

  const ChoreCard({
    super.key,
    required this.title,
    required this.reward,
    required this.deadline,
    required this.status,
    required this.isExclusive,
    required this.assignedTo,
    required this.progress,
    this.onTap,
    int? seed,
  }) : colorSeed = seed ?? 0;

  static final List<Color> happyColors = [
    const Color(0xFFFFF59D),
    const Color.fromARGB(255, 237, 176, 157),
    const Color.fromARGB(255, 153, 227, 237),
    const Color.fromARGB(255, 157, 218, 159),
    const Color.fromARGB(255, 184, 162, 224),
    const Color(0xFFFFF176),
    const Color.fromARGB(255, 237, 161, 169),
    const Color.fromARGB(255, 255, 206, 140), // soft orange
    const Color.fromARGB(255, 190, 231, 226), // pale teal
    const Color.fromARGB(255, 200, 232, 200), // minty green
    const Color.fromARGB(255, 210, 190, 235), // light lavender
    const Color.fromARGB(255, 255, 220, 164), // warm butter
    const Color.fromARGB(255, 245, 180, 188), // rosy blush
    const Color.fromARGB(255, 186, 220, 245), // baby blue
  ];

  bool _any(String s) => progress?.containsValue(s) ?? false;

  Color getCardColor() {
    // Make expired visually distinct.
    if (status == 'expired') {
      if (_any('paid') || _any('verified') || _any('complete')) {
        // expired but with progress → a very light green
        return Colors.green[50]!;
      }
      // expired with no completion → neutral grey
      return Colors.grey[200]!;
    }
    // Non-expired colors
    if (_any('paid')) return Colors.green[200]!;
    if (_any('verified')) return Colors.green[100]!;
    final random = Random(title.hashCode + colorSeed);
    return happyColors[random.nextInt(happyColors.length)];
  }

  String get formattedDeadline {
    final timeFormat = DateFormat.jm();
    return 'Before ${timeFormat.format(deadline)}';
  }

  // Child-only status (raw from progress; default 'assigned')
  String getCurrentUserRawStatus() {
    final uid = UserService.currentUser!.uid;
    return progress?[uid] ?? 'assigned';
  }

  String labelForChildStatus(String s) =>
      s == 'assigned' ? 'Available' : _titleCase(s);

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  // --- Parent counts computed ONLY from progress map ------------------------
  Map<String, int> computeParentCountsFromProgress() {
    final counts = <String, int>{
      'claimed': 0,
      'complete': 0,
      'verified': 0,
      'paid': 0,
    };
    if (progress == null) return counts;
    for (final s in progress!.values) {
      if (counts.containsKey(s)) counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  // --- UI helpers -----------------------------------------------------------
  Widget _pill({
    required Widget leading,
    required String text,
    required Color bg,
    required Color fg,
    EdgeInsets margin = const EdgeInsets.only(top: 6),
  }) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(blurRadius: 2, offset: Offset(0, 1), color: Color(0x22000000))
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        leading,
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }

  (Color bg, Color fg, IconData icon) _styleFor(String status) {
    switch (status) {
      case 'claimed':
        return (const Color(0xFFB3E5FC), const Color(0xFF01579B), Icons.back_hand_rounded);
      case 'complete':
        return (const Color(0xFFFFF9C4), const Color(0xFF795548), Icons.check_circle_rounded);
      case 'verified':
        return (const Color(0xFFC8E6C9), const Color(0xFF1B5E20), Icons.verified_rounded);
      case 'paid':
        return (const Color(0xFFDCEFD6), const Color(0xFF2E7D32), Icons.attach_money_rounded);
      case 'assigned':
        return (const Color(0xFFE0E0E0), const Color(0xFF424242), Icons.group_rounded);
      default:
        return (const Color(0xFFE0E0E0), const Color(0xFF424242), Icons.info_outline_rounded);
    }
  }

  Widget _parentRightPanel() {
    final counts = computeParentCountsFromProgress();
    final items = <Widget>[];

    // Natural flow
    for (final s in const ['claimed', 'complete', 'verified', 'paid']) {
      final n = counts[s] ?? 0;
      if (n <= 0) continue;
      final (bg, fg, icon) = _styleFor(s);
      items.add(_pill(
        leading: Icon(icon, size: 16, color: fg),
        text: '${_titleCase(s)}: $n',
        bg: bg,
        fg: fg,
        margin: items.isEmpty ? EdgeInsets.zero : const EdgeInsets.only(top: 6),
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: items,
    );
  }

  Widget _childRightBadge(String raw) {
    final label = labelForChildStatus(raw);
    final (bg, fg, icon) = _styleFor(raw);
    return _pill(
      leading: Icon(icon, size: 16, color: fg),
      text: label,
      bg: raw == 'assigned' ? const Color.fromARGB(255, 243, 117, 86) : bg,
      fg: raw == 'assigned' ? Colors.white : fg,
      margin: EdgeInsets.zero,
    );
  }

  Widget _expiredBadge() {
    if (status != 'expired') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBDBDBD)),
      ),
      child: const Text(
        'Expired',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF616161),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = UserService.currentUser!.role;
    final isChild = role == 'child';
    final childRawStatus = isChild ? getCurrentUserRawStatus() : null;

    return Card(
      color: getCardColor(),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // LEFT: title + meta
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 30, 2, 49),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '₪$reward',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(255, 30, 2, 49),
                          ),
                        ),
                        Text(
                          ' • $formattedDeadline',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color.fromARGB(255, 30, 2, 49),
                          ),
                        ),
                      ],
                    ),
                    _expiredBadge(), // <-- small pill if expired
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // RIGHT: parent breakdown (from progress only) OR child status badge
              Flexible(
                flex: 0,
                child: isChild ? _childRightBadge(childRawStatus!) : _parentRightPanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
