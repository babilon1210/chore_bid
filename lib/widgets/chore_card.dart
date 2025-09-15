// lib/widgets/chore_card.dart
import 'dart:math';
import 'package:chore_bid/services/user_service.dart';
import 'package:chore_bid/services/family_service.dart'; // <-- added
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChoreCard extends StatelessWidget {
  final String title;
  final String reward;
  final String status; // may be 'expired'
  /// childId -> either a String status (legacy) OR a Map {status, time}
  final Map<String, dynamic>? progress;
  final List<String> assignedTo;
  final VoidCallback? onTap;
  final DateTime deadline;
  final bool isExclusive;

  /// optional description to show under the title
  final String description;

  /// If provided, we’ll use happyColors[paletteIndex % N] for active chores
  /// so the color stays consistent across list moves (e.g., Available -> Claimed).
  final int? paletteIndex;

  /// When true (and status == 'expired'), the card shows ONLY an "Expired" pill
  /// on the RIGHT side (with date+time) and hides the usual right-side status
  /// and bottom expired badge. Also removes the bottom "Before ..." time, leaving only price.
  final bool rightExpiredOnly;

  /// When true, the bottom “Expired” pill is always hidden (useful for Active tab).
  final bool suppressBottomExpiredPill;

  /// For ACTIVE chores on the child's home page:
  /// - If status is complete/verified -> hide deadline entirely.
  /// - Otherwise, move "Before\nDate\nTime" under the right-side status capsule,
  ///   and suppress the bottom "Before ..." next to the price.
  final bool showRightDeadlineForActive;

  /// For PARENT pages: when true, always show the deadline under the right-side widget
  /// (regardless of child/parent role and status). Also suppresses the bottom deadline.
  final bool showRightDeadline;

  /// Inline actions (child view)
  final Future<void> Function()? onClaim;
  final Future<void> Function()? onUnclaim;
  final Future<void> Function()? onDone;

  const ChoreCard({
    super.key,
    required this.title,
    required this.reward,
    required this.deadline,
    required this.status,
    required this.isExclusive,
    required this.assignedTo,
    required this.progress,
    required this.description,
    this.onTap,
    this.paletteIndex,
    this.rightExpiredOnly = false,
    this.suppressBottomExpiredPill = false,
    this.showRightDeadlineForActive = false,
    this.showRightDeadline = false,
    this.onClaim,
    this.onUnclaim,
    this.onDone,
  });

  // ---------------- helpers for new/old progress shapes ----------------

  /// Extracts a status string from either a legacy String or a `{status,time}` map.
  String? _statusFrom(dynamic v) {
    if (v is String) return v; // legacy
    if (v is Map<String, dynamic>) return v['status'] as String?;
    if (v is Map) return v['status'] as String?;
    return null;
  }

  DateTime? _timeFrom(dynamic v) {
    if (v is Map<String, dynamic>) {
      final t = v['time'];
      if (t is DateTime) return t;
      if (t is String) {
        try {
          return DateTime.parse(t);
        } catch (_) {}
      }
      // Firestore Timestamp compatibility (best-effort, without importing Timestamp)
      try {
        // ignore: avoid_dynamic_calls
        if (t != null && t is dynamic && t.millisecondsSinceEpoch is int) {
          return DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch as int);
        }
      } catch (_) {}
    } else if (v is Map) {
      final t = v['time'];
      if (t is DateTime) return t;
    }
    return null;
  }

  DateTime? _myStatusTime() {
    final uid = UserService.currentUser!.uid;
    final v = progress?[uid];
    return _timeFrom(v);
  }

  bool _any(String s) => progress?.values.any((v) => _statusFrom(v) == s) ?? false;

  // --- “available for me” detection (mirrors page logic) ---
  bool _someoneElseAdvanced(String myId) {
    final prog = progress;
    if (prog == null) return false;
    for (final e in prog.entries) {
      if (e.key == myId) continue;
      final s = _statusFrom(e.value);
      if (s != null && s != 'assigned') return true;
    }
    return false;
  }

  bool _isAvailableForMe() {
    if (status == 'expired') return false;
    final uid = UserService.currentUser!.uid;

    if (!assignedTo.contains(uid)) return false;

    final myStatus = _statusFrom(progress?[uid]);
    final mineOpen = (myStatus == null || myStatus == 'assigned');
    if (!mineOpen) return false;

    if (isExclusive && _someoneElseAdvanced(uid)) return false;

    return true;
  }

  // ---------------------------------------------------------------------

  static final List<Color> happyColors = [
    const Color(0xFFFFF59D),
    const Color.fromARGB(255, 237, 176, 157),
    const Color.fromARGB(255, 153, 227, 237),
    const Color.fromARGB(255, 157, 218, 159),
    const Color.fromARGB(255, 184, 162, 224),
    const Color(0xFFFFF176),
    const Color.fromARGB(255, 237, 161, 169),
    const Color.fromARGB(255, 255, 206, 140),
    const Color.fromARGB(255, 190, 231, 226),
    const Color.fromARGB(255, 200, 232, 200),
    const Color.fromARGB(255, 210, 190, 235),
    const Color.fromARGB(255, 255, 220, 164),
    const Color.fromARGB(255, 245, 180, 188),
    const Color.fromARGB(255, 186, 220, 245),
  ];

  Color getCardColor() {
    // 1) Expired -> greys / very light green if “done-ish”
    if (status == 'expired') {
      if (_any('paid') || _any('verified') || _any('complete')) {
        return Colors.green[50]!;
      }
      return Colors.grey[200]!;
    }

    // 2) Achieved states for any child -> greens
    if (_any('paid')) return Colors.green[200]!;
    if (_any('verified')) return Colors.green[100]!;

    // 3) Active: if a paletteIndex was provided, honor it for consistency
    if (paletteIndex != null) {
      final idx = paletteIndex! % happyColors.length;
      return happyColors[idx];
    }

    // 4) Fallback for other active chores -> deterministic but may repeat
    final random = Random(title.hashCode);
    return happyColors[random.nextInt(happyColors.length)];
  }

  String get formattedDeadline {
    // DATE + TIME
    final df = DateFormat.yMMMd();
    final tf = DateFormat.jm();
    return 'Before ${df.format(deadline)} ${tf.format(deadline)}';
  }

  String _formatDate(DateTime? t) {
    if (t == null) return '';
    final df = DateFormat.yMMMd();
    return df.format(t);
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '';
    final tf = DateFormat.jm();
    return tf.format(t);
  }

  /// Returns the current user's status string (defaults to 'assigned').
  String getCurrentUserRawStatus() {
    final uid = UserService.currentUser!.uid;
    final v = progress?[uid];
    return _statusFrom(v) ?? 'assigned';
  }

  String labelForChildStatus(String s) => s == 'assigned' ? 'Available' : _titleCase(s);

  String _titleCase(String s) =>
      s.isNotEmpty ? (s[0].toUpperCase() + s.substring(1).toLowerCase()) : s;

  Map<String, int> computeParentCountsFromProgress() {
    final counts = <String, int>{
      'claimed': 0,
      'complete': 0,
      'verified': 0,
      'paid': 0,
    };
    if (progress == null) return counts;
    for (final val in progress!.values) {
      final s = _statusFrom(val);
      if (s != null && counts.containsKey(s)) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
    }
    return counts;
  }

  Widget _pill({
    required Widget leading,
    required Widget textWidget,
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          DefaultTextStyle(
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
            child: textWidget,
          ),
        ],
      ),
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

    for (final s in const ['claimed', 'complete', 'verified', 'paid']) {
      final n = counts[s] ?? 0;
      if (n <= 0) continue;
      final (bg, fg, icon) = _styleFor(s);
      items.add(_pill(
        leading: Icon(icon, size: 16, color: fg),
        textWidget: Text('${_titleCase(s)}: $n'),
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

  Widget _rightDeadlineLines(Color fg) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Before',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: fg.withOpacity(0.9),
            height: 1.1,
          ),
        ),
        Text(
          _formatDate(deadline),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: fg.withOpacity(0.85),
            height: 1.1,
          ),
        ),
        Text(
          _formatTime(deadline),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: fg.withOpacity(0.85),
            height: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _childRightBadge(String raw) {
    final (bg, fg, icon) = _styleFor(raw);

    // Special: for PAID, show date (line 2) and time (line 3) under the "Paid" title.
    if (raw == 'paid') {
      final paidAt = _myStatusTime();
      final dateStr = _formatDate(paidAt);
      final timeStr = _formatTime(paidAt);
      return _pill(
        leading: Icon(icon, size: 16, color: fg),
        textWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Paid'),
            if (dateStr.isNotEmpty)
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fg.withOpacity(0.85),
                  height: 1.15,
                ),
              ),
            if (timeStr.isNotEmpty)
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fg.withOpacity(0.85),
                  height: 1.15,
                ),
              ),
          ],
        ),
        bg: bg,
        fg: fg,
        margin: EdgeInsets.zero,
      );
    }

    // Default one-line badge for other statuses
    final label = labelForChildStatus(raw);
    return _pill(
      leading: Icon(icon, size: 16, color: fg),
      textWidget: Text(label),
      bg: raw == 'assigned' ? const Color.fromARGB(255, 243, 117, 86) : bg,
      fg: raw == 'assigned' ? Colors.white : fg,
      margin: EdgeInsets.zero,
    );
  }

  Widget _expiredBadgeBottom() {
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

  Widget _expiredBadgeRight() {
    final date = _formatDate(deadline);
    final time = _formatTime(deadline);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBDBDBD)),
        boxShadow: const [
          BoxShadow(blurRadius: 2, offset: Offset(0, 1), color: Color(0x22000000))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Expired',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF616161),
            ),
          ),
          if (date.isNotEmpty)
            Text(
              date,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF616161),
                height: 1.15,
              ),
            ),
          if (time.isNotEmpty)
            Text(
              time,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF616161),
                height: 1.15,
              ),
            ),
        ],
      ),
    );
  }

  // ------- Inline action buttons (child view) -------
  Widget _childActionButtons({required bool isChild}) {
    if (!isChild) return const SizedBox.shrink();
    if (status == 'expired') return const SizedBox.shrink();

    final myRaw = getCurrentUserRawStatus();
    final available = _isAvailableForMe();

    // Available → Claim
    if (available && onClaim != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: onClaim,
              icon: const Icon(Icons.how_to_reg, size: 18),
              label: const Text(
                'Claim',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ),
      );
    }

    // Claimed → Unclaim + Done
    if (myRaw == 'claimed' && (onUnclaim != null || onDone != null)) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (onUnclaim != null)
                SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: onUnclaim,
                    child: const Text(
                      'Unclaim',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      side: const BorderSide(color: Colors.indigo, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ),
              if (onDone != null)
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    onPressed: onDone,
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // For complete/verified/paid (or unavailable), no buttons
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final role = UserService.currentUser!.role;
    final isChild = role == 'child';
    final childRawStatus = isChild ? getCurrentUserRawStatus() : null;

    final showRightExpiredOnly = rightExpiredOnly && status == 'expired';
    final hideBottomExpiredForPaid = isChild && childRawStatus == 'paid';

    final isChildCompleteOrVerified =
        isChild && (childRawStatus == 'complete' || childRawStatus == 'verified');

    // bottom deadline should be hidden when:
    // - rightExpiredOnly (expired view),
    // - child's paid,
    // - we are rendering deadline on the right (either child-active or parent).
    final showBottomDeadline =
        !(showRightExpiredOnly && status == 'expired') &&
        !(isChild && childRawStatus == 'paid') &&
        !showRightDeadlineForActive &&
        !showRightDeadline;

    // Should we show the right-side deadline?
    final shouldShowRightDeadlineChild =
        showRightDeadlineForActive && isChild && !isChildCompleteOrVerified;
    final shouldShowRightDeadline =
        showRightDeadline || shouldShowRightDeadlineChild;

    // Currency from FamilyService (fallback to "$" if not yet loaded)
    final currencySymbol = FamilyService().currentCurrency;

    // Build right-side widget
    Widget buildRightWidget() {
      if (showRightExpiredOnly) return _expiredBadgeRight();

      // Parent view (aggregate panel)
      if (!isChild) {
        final panel = _parentRightPanel();
        if (!shouldShowRightDeadline) return panel;

        // Use a neutral FG color under the parent panel
        const fg = Color(0xFF424242);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            panel,
            const SizedBox(height: 6),
            _rightDeadlineLines(fg),
          ],
        );
      }

      // Child view:
      final badge = _childRightBadge(childRawStatus!);

      if (!shouldShowRightDeadlineChild) return badge;

      final (_, fg, __) = _styleFor(childRawStatus);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          badge,
          const SizedBox(height: 6),
          _rightDeadlineLines(fg),
        ],
      );
    }

    return Card(
      color: getCardColor(),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap, // not used for child in Active tab anymore
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // LEFT: title + description + meta
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

                    // description (up to 2 lines)
                    if (description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description.trim(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color.fromARGB(255, 30, 2, 49),
                        ),
                      ),
                    ],

                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$currencySymbol$reward', // <-- currency from FamilyService
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(255, 30, 2, 49),
                          ),
                        ),
                        if (showBottomDeadline) ...[
                          Text(
                            ' • $formattedDeadline',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color.fromARGB(255, 30, 2, 49),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Inline action buttons (child)
                    _childActionButtons(isChild: isChild),

                    // Bottom "Expired" badge is suppressed in these cases:
                    // - rightExpiredOnly mode, OR
                    // - paid items for child view, OR
                    // - explicit suppression via prop.
                    if (!showRightExpiredOnly &&
                        !hideBottomExpiredForPaid &&
                        !suppressBottomExpiredPill)
                      _expiredBadgeBottom(),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // RIGHT
              Flexible(
                flex: 0,
                child: buildRightWidget(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
