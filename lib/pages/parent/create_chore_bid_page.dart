import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // digits-only for reward
import '../../services/chore_service.dart';
import '../../services/family_service.dart';
import '../../models/user_model.dart';

class CreateChoreBidPage extends StatefulWidget {
  final UserModel user;

  const CreateChoreBidPage({super.key, required this.user});

  @override
  State<CreateChoreBidPage> createState() => _CreateChoreBidPageState();
}

class _CreateChoreBidPageState extends State<CreateChoreBidPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rewardController = TextEditingController();
  DateTime? _selectedDeadline;

  final _choreService = ChoreService();
  final _familyService = FamilyService();
  Map<String, String> _childNamesById = {};
  Set<String> _selectedChildren = {};

  bool _isExclusive = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final namesMap =
        await _familyService.getChildrenNamesMap(widget.user.familyId!);

    if (mounted) {
      setState(() {
        _childNamesById = namesMap;
      });
    }
  }

  void _toggleSelectAll(bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedChildren = _childNamesById.keys.toSet();
      } else {
        _selectedChildren.clear();
      }
    });
  }

  bool _isDeadlineValid(DateTime d) {
    final min = DateTime.now().add(const Duration(minutes: 30));
    // Valid if deadline is >= now + 30 minutes
    return !d.isBefore(min);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now, // no past dates
      lastDate: now.add(const Duration(days: 30)),
    );

    if (date == null) return;

    // If picking "today", make suggested time at least 30 mins ahead for convenience.
    final suggested = now.add(const Duration(minutes: 31));
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

    final initialTime = isToday
        ? TimeOfDay(hour: suggested.hour, minute: suggested.minute)
        : TimeOfDay.now();

    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (time == null) return;

    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    if (!_isDeadlineValid(picked)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a deadline at least 30 minutes from now.')),
      );
      return; // do not set invalid deadline
    }

    setState(() {
      _selectedDeadline = picked;
    });
  }

  Future<void> _submitForm() async {
    if (_isSubmitting) return;

    // Validate form fields first
    final formOk = _formKey.currentState!.validate();

    // Validate deadline presence + rules
    if (_selectedDeadline == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please pick a deadline')));
      return;
    }
    if (!_isDeadlineValid(_selectedDeadline!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deadline must be at least 30 minutes from now.')),
      );
      return;
    }

    if (formOk) {
      setState(() => _isSubmitting = true);
      FocusScope.of(context).unfocus();

      try {
        await _choreService.addChore(
          familyId: widget.user.familyId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          reward: _rewardController.text.trim(), // digits only
          assignedTo: _selectedChildren.toList(),
          deadline: _selectedDeadline!,
          isExclusive: _isExclusive,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chore created successfully!')),
        );
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating chore: $e')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _rewardController.dispose();
    _familyService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadlineLabel = _selectedDeadline == null
        ? 'Pick a deadline'
        : 'Deadline: ${_selectedDeadline!.toLocal().toString().substring(0, 16)}';

    return Scaffold(
      appBar: AppBar(title: const Text('New Chore Bid')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Chore Title',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Chore Description',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Please enter a description'
                    : null,
              ),
              const SizedBox(height: 16),

              // --------- NUMBERS ONLY ---------
              TextFormField(
                controller: _rewardController,
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: false,
                  decimal: false,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Reward',
                  hintText: 'Numbers only',
                  border: OutlineInputBorder(),
                  prefixText: '₪',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a reward';
                  }
                  if (!RegExp(r'^\d+$').hasMatch(value)) {
                    return 'Use digits only';
                  }
                  if (int.tryParse(value) == 0) {
                    return 'Amount must be greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // --------------------------------

              SwitchListTile(
                title: const Text('Exclusive Chore'),
                subtitle: const Text('Only one child can claim this chore'),
                value: _isExclusive,
                onChanged: _isSubmitting
                    ? null
                    : (val) {
                        setState(() {
                          _isExclusive = val;
                        });
                      },
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text(deadlineLabel),
                subtitle: const Text('Must be at least 30 minutes from now'),
                trailing: const Icon(Icons.calendar_today),
                onTap: _isSubmitting ? null : _pickDeadline,
              ),
              const SizedBox(height: 16),

              if (_childNamesById.isNotEmpty) ...[
                Row(
                  children: [
                    Checkbox(
                      value: _selectedChildren.length == _childNamesById.length &&
                          _childNamesById.isNotEmpty,
                      onChanged: _isSubmitting
                          ? null
                          : (val) => _toggleSelectAll(val ?? false),
                    ),
                    const Text("Assign to All Children"),
                  ],
                ),
                ..._childNamesById.entries.map((entry) {
                  return CheckboxListTile(
                    title: Text(entry.value),
                    value: _selectedChildren.contains(entry.key),
                    onChanged: _isSubmitting
                        ? null
                        : (val) {
                            setState(() {
                              if (val == true) {
                                _selectedChildren.add(entry.key);
                              } else {
                                _selectedChildren.remove(entry.key);
                              }
                            });
                          },
                  );
                }).toList(),
              ],

              const SizedBox(height: 32),

              // ----- Submit button with loading state -----
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitForm,
                  child: _isSubmitting
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Creating…'),
                          ],
                        )
                      : const Text('Create Chore Bid'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
