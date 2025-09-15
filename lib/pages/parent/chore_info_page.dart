import 'dart:async';

import 'package:chore_bid/services/family_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/chore_model.dart';
import '../../services/chore_service.dart';
import '../../services/user_service.dart';

class ChoreInfoPage extends StatefulWidget {
  final Chore chore;

  const ChoreInfoPage({super.key, required this.chore});

  @override
  State<ChoreInfoPage> createState() => _ChoreInfoPageState();
}

class _ChoreInfoPageState extends State<ChoreInfoPage> {
  late bool isEditing;
  late TextEditingController titleController;
  late TextEditingController rewardController;
  late DateTime deadline;
  late List<String> assignedTo;

  /// IMPORTANT: values can be either legacy String or {status,time} map
  late Map<String, dynamic> progressMap;

  // NEW: show description for both roles (read-only)
  late final String description;

  Map<String, String> _childNamesById = {};
  // Selections
  Set<String> _selectedToVerify = {};
  Set<String> _selectedToPay = {};

  // ----- currency from FamilyService -----
  final _familyService = FamilyService();
  String _currencySymbol = r'$'; // UI display
  String _currencyCode = 'USD';  // used for payment records
  StreamSubscription<String?>? _curSymSub;
  StreamSubscription<String?>? _curCodeSub;

  bool get _isChild => (UserService.currentUser?.role == 'child');

  @override
  void initState() {
    super.initState();
    isEditing = false;
    titleController = TextEditingController(text: widget.chore.title);
    rewardController = TextEditingController(text: widget.chore.reward);
    deadline = widget.chore.deadline;
    assignedTo = List<String>.from(widget.chore.assignedTo);
    progressMap = Map<String, dynamic>.from(widget.chore.progress ?? {});
    description = widget.chore.description; // keep as-is (read-only)

    _initCurrency();
    _loadChildNames();
  }

  Future<void> _initCurrency() async {
    final familyId = UserService.currentUser?.familyId;
    if (familyId == null || familyId.isEmpty) return;

    // Start listening to family doc (if not already)
    _familyService.listenToFamily(familyId);

    // seed immediate values if already cached
    _currencySymbol = _familyService.currentCurrency;
    _currencyCode = _familyService.currentCurrency;

    _curSymSub = _familyService.currencyStream.listen((sym) {
      if (!mounted) return;
      if (sym != null && sym.isNotEmpty && sym != _currencySymbol) {
        setState(() => _currencySymbol = sym);
      }
    });

    _curCodeSub = _familyService.currencyStream.listen((code) {
      if (!mounted) return;
      if (code != null && code.isNotEmpty && code != _currencyCode) {
        setState(() => _currencyCode = code);
      }
    });
  }

  Future<void> _loadChildNames() async {
    final familyId = UserService.currentUser?.familyId;
    if (familyId != null) {
      final map = await FamilyService().getChildrenNamesMap(familyId);
      if (mounted) {
        setState(() {
          _childNamesById = map;
        });
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    rewardController.dispose();
    _curSymSub?.cancel();
    _curCodeSub?.cancel();
    _familyService.dispose();
    super.dispose();
  }

  // ---- helpers for new/old progress shapes ----
  String? _statusFrom(dynamic v) {
    if (v is String) return v; // legacy
    if (v is Map<String, dynamic>) return v['status'] as String?;
    if (v is Map) return v['status'] as String?;
    return null;
  }

  bool _isStatus(dynamic v, String s) => _statusFrom(v) == s;

  // --------------------------------------------

  Future<void> _saveChanges() async {
    // NOTE: description is view-only here (ChoreService.updateChore signature
    // provided does not include description), so we don't attempt to save it.
    await ChoreService().updateChore(
      familyId: UserService.currentUser!.familyId!,
      choreId: widget.chore.id,
      title: titleController.text,
      reward: rewardController.text,
      deadline: deadline,
      assignedTo: assignedTo,
    );

    setState(() => isEditing = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Chore updated')));
  }

  Future<void> _deleteChore() async {
    await ChoreService().deleteChore(
      familyId: UserService.currentUser!.familyId!,
      choreId: widget.chore.id,
    );

    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _verifySelectedChildren() async {
    final familyId = UserService.currentUser!.familyId!;
    final choreId = widget.chore.id;

    for (final childId in _selectedToVerify) {
      await ChoreService().markChoreAsVerified(
        familyId: familyId,
        choreId: choreId,
        childId: childId,
        time: DateTime.now(),
      );
      // Local UI update in new shape
      progressMap[childId] = {
        'status': 'verified',
        'time': DateTime.now().toUtc(),
      };
    }

    setState(() {
      _selectedToVerify.clear();
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected children marked as verified')),
      );
    }
  }

  // --- Payment helpers ------------------------------------------------------

  int _parseAmountCents(String raw) {
    // Accept things like "30", "30.50", "30,50", "₪30.50", "$30"
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[^0-9\.,]'), '');
    if (s.contains(',') && !s.contains('.')) {
      s = s.replaceAll(',', '.'); // "30,5" -> "30.5"
    } else if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll(',', ''); // "1,234.50" -> "1234.50"
    }
    final value = double.tryParse(s) ?? 0.0;
    return (value * 100).round();
  }

  Future<void> _paySelectedChildren() async {
    final familyId = UserService.currentUser!.familyId!;
    final choreId = widget.chore.id;
    final payer = UserService.currentUser!.uid;
    final amountCents = _parseAmountCents(rewardController.text);

    for (final childId in _selectedToPay) {
      await ChoreService().markChoreAsPaid(
        familyId: familyId,
        choreId: choreId,
        childId: childId,
        amountCents: amountCents,
        currency: _currencyCode.isNotEmpty ? _currencyCode : 'USD', // <- from family
        method: 'cash',
        paidByUid: payer,
        paidAt: DateTime.now(),
      );
      // Local UI update in new shape
      progressMap[childId] = {
        'status': 'paid',
        'time': DateTime.now().toUtc(),
      };
    }

    setState(() {
      _selectedToPay.clear();
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected children marked as paid')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 190, 71),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'Chorebid',
          style: GoogleFonts.pacifico(
            fontSize: 30,
            color: const Color.fromARGB(255, 11, 16, 47),
          ),
        ),
        centerTitle: true,
        actions: [
          // Child is view-only: no edit/delete
          if (!_isChild &&
              progressMap.values.every(
                (v) => _statusFrom(v) == null || _statusFrom(v) == 'unclaimed',
              ))
            IconButton(
              icon: Icon(isEditing ? Icons.cancel : Icons.edit),
              onPressed: () => setState(() => isEditing = !isEditing),
            ),
          if (!_isChild && !isEditing)
            IconButton(icon: const Icon(Icons.delete), onPressed: _deleteChore),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 253, 247, 193),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(
                icon: Icons.title,
                label: 'Title',
                contentWidget: isEditing
                    ? TextField(controller: titleController)
                    : Text(
                        titleController.text,
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
              const SizedBox(height: 20),
              // NEW: Description (read-only for all roles to match existing update API)
              _section(
                icon: Icons.description,
                label: 'Description',
                contentWidget: Text(
                  (description.isNotEmpty ? description : 'No description provided'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 20),
              _section(
                icon: Icons.monetization_on,
                label: 'Reward',
                contentWidget: isEditing
                    ? TextField(controller: rewardController)
                    : Text(
                        '$_currencySymbol${rewardController.text}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              _section(
                icon: Icons.calendar_today,
                label: 'Deadline',
                contentWidget: isEditing
                    ? TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: deadline,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null) {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(deadline),
                            );
                            if (time != null) {
                              setState(() {
                                deadline = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                  time.hour,
                                  time.minute,
                                );
                              });
                            }
                          }
                        },
                        child: Text(
                          dateFormat.format(deadline),
                          style: const TextStyle(fontSize: 16),
                        ),
                      )
                    : Text(
                        dateFormat.format(deadline),
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
              const SizedBox(height: 20),
              _section(
                icon: Icons.group,
                label: 'Assigned to',
                contentWidget: Text(
                  assignedTo
                      .map((id) => _childNamesById[id] ?? 'Unknown')
                      .join(', '),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 20),

              // Parent-only management sections
              if (!_isChild)
                _section(
                  icon: Icons.check,
                  label: 'Verify Completed Chores',
                  contentWidget: _buildVerificationChecklist(),
                ),
              if (!_isChild) const SizedBox(height: 20),
              if (!_isChild)
                _section(
                  icon: Icons.payments,
                  label: 'Pay Verified Children',
                  contentWidget: _buildPaymentChecklist(),
                ),

              const Spacer(),

              // Parent-only action buttons
              if (!_isChild && _selectedToVerify.isNotEmpty)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _verifySelectedChildren,
                    icon: const Icon(Icons.verified),
                    label: const Text("Verify Selected"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              if (!_isChild && _selectedToVerify.isNotEmpty && _selectedToPay.isNotEmpty)
                const SizedBox(height: 8),
              if (!_isChild && _selectedToPay.isNotEmpty)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _paySelectedChildren,
                    icon: const Icon(Icons.attach_money),
                    label: const Text("Pay Selected"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              if (!_isChild && isEditing) const SizedBox(height: 8),
              if (!_isChild && isEditing)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _saveChanges,
                    icon: const Icon(Icons.save),
                    label: const Text("Save"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String label,
    required Widget contentWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: Colors.indigo),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              contentWidget,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationChecklist() {
    final completedChildren =
        progressMap.entries.where((e) => _isStatus(e.value, 'complete'));

    if (completedChildren.isEmpty) {
      return const Text(
        'No completed chores to verify',
        style: TextStyle(fontSize: 16),
      );
    }

    return Column(
      children: completedChildren.map((entry) {
        final childId = entry.key;
        final name = _childNamesById[childId] ?? 'Unknown';

        return CheckboxListTile(
          title: Text(name),
          value: _selectedToVerify.contains(childId),
          onChanged: (checked) {
            setState(() {
              if (checked == true) {
                _selectedToVerify.add(childId);
              } else {
                _selectedToVerify.remove(childId);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildPaymentChecklist() {
    // Only show children who are verified and not yet paid
    final verifiedNotPaid =
        progressMap.entries.where((e) => _isStatus(e.value, 'verified'));

    if (verifiedNotPaid.isEmpty) {
      return const Text(
        'No verified chores to pay',
        style: TextStyle(fontSize: 16),
      );
    }

    return Column(
      children: verifiedNotPaid.map((entry) {
        final childId = entry.key;
        final name = _childNamesById[childId] ?? 'Unknown';

        return CheckboxListTile(
          title: Text(name),
          value: _selectedToPay.contains(childId),
          onChanged: (checked) {
            setState(() {
              if (checked == true) {
                _selectedToPay.add(childId);
              } else {
                _selectedToPay.remove(childId);
              }
            });
          },
        );
      }).toList(),
    );
  }
}
