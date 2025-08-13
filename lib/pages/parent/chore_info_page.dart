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
  late Map<String, String> progressMap;

  Map<String, String> _childNamesById = {};
  // Selections
  Set<String> _selectedToVerify = {};
  Set<String> _selectedToPay = {};

  @override
  void initState() {
    super.initState();
    isEditing = false;
    titleController = TextEditingController(text: widget.chore.title);
    rewardController = TextEditingController(text: widget.chore.reward);
    deadline = widget.chore.deadline;
    assignedTo = List<String>.from(widget.chore.assignedTo);
    progressMap = Map<String, String>.from(widget.chore.progress ?? {});
    _loadChildNames();
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
    super.dispose();
  }

  Future<void> _saveChanges() async {
    await ChoreService().updateChore(
      familyId: UserService.currentUser!.familyId!,
      choreId: widget.chore.id,
      title: titleController.text,
      reward: rewardController.text,
      deadline: deadline,
      assignedTo: assignedTo,
    );

    setState(() => isEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chore updated')),
    );
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
      );
      // Local UI update
      progressMap[childId] = 'verified';
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
    // Accept things like "30", "30.50", "30,50", "₪30.50"
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
        currency: 'ILS',
        method: 'cash',
        paidByUid: payer,
      );
      // Local UI update
      progressMap[childId] = 'paid';
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
          if (progressMap.values.every((s) => s == 'unclaimed'))
            IconButton(
              icon: Icon(isEditing ? Icons.cancel : Icons.edit),
              onPressed: () => setState(() => isEditing = !isEditing),
            ),
          if (!isEditing)
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
                    : Text(titleController.text, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 20),
              _section(
                icon: Icons.monetization_on,
                label: 'Reward',
                contentWidget: isEditing
                    ? TextField(controller: rewardController)
                    : Text(
                        '${rewardController.text}₪',
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
                            lastDate: DateTime.now().add(const Duration(days: 365)),
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
                        child: Text(dateFormat.format(deadline), style: const TextStyle(fontSize: 16)),
                      )
                    : Text(dateFormat.format(deadline), style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 20),
              _section(
                icon: Icons.group,
                label: 'Assigned to',
                contentWidget: isEditing
                    ? Wrap(
                        spacing: 8,
                        children: _childNamesById.entries.map((entry) {
                          final childId = entry.key;
                          final isSelected = assignedTo.contains(childId);
                          return FilterChip(
                            label: Text(entry.value),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  assignedTo.add(childId);
                                } else {
                                  assignedTo.remove(childId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      )
                    : Text(
                        assignedTo.map((id) => _childNamesById[id] ?? 'Unknown').join(', '),
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
              const SizedBox(height: 20),

              // Verify completed
              _section(
                icon: Icons.check,
                label: 'Verify Completed Chores',
                contentWidget: _buildVerificationChecklist(),
              ),
              const SizedBox(height: 20),

              // Pay verified
              _section(
                icon: Icons.payments,
                label: 'Pay Verified Children',
                contentWidget: _buildPaymentChecklist(),
              ),

              const Spacer(),

              // Action buttons
              if (_selectedToVerify.isNotEmpty)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _verifySelectedChildren,
                    icon: const Icon(Icons.verified),
                    label: const Text("Verify Selected"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ),
              if (_selectedToVerify.isNotEmpty && _selectedToPay.isNotEmpty)
                const SizedBox(height: 8),
              if (_selectedToPay.isNotEmpty)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _paySelectedChildren,
                    icon: const Icon(Icons.attach_money),
                    label: const Text("Pay Selected"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ),
              if (isEditing) const SizedBox(height: 8),
              if (isEditing)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _saveChanges,
                    icon: const Icon(Icons.save),
                    label: const Text("Save"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
    final completedChildren = progressMap.entries.where((e) => e.value == 'complete');

    if (completedChildren.isEmpty) {
      return const Text('No completed chores to verify', style: TextStyle(fontSize: 16));
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
    final verifiedNotPaid = progressMap.entries.where((e) => e.value == 'verified');

    if (verifiedNotPaid.isEmpty) {
      return const Text('No verified chores to pay', style: TextStyle(fontSize: 16));
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
