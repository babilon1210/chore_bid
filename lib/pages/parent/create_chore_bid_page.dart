import 'package:flutter/material.dart';
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

  void _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );

    if (date != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          _selectedDeadline = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate() && _selectedDeadline != null) {
      try {
        await _choreService.addChore(
          familyId: widget.user.familyId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          reward: _rewardController.text.trim(),
          assignedTo: _selectedChildren.toList(),
          deadline: _selectedDeadline!,
          isExclusive: _isExclusive,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chore created successfully!')),
        );

        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating chore: $e')));
      }
    } else if (_selectedDeadline == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please pick a deadline')));
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
                decoration: const InputDecoration(
                  labelText: 'Chore Description',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Please enter a description'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _rewardController,
                decoration: const InputDecoration(
                  labelText: 'Reward (e.g. \$5 or Ice Cream)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Please enter a reward' : null,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Exclusive Chore'),
                subtitle: const Text('Only one child can claim this chore'),
                value: _isExclusive,
                onChanged: (val) {
                  setState(() {
                    _isExclusive = val;
                  });
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text(deadlineLabel),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDeadline,
              ),
              const SizedBox(height: 16),
              if (_childNamesById.isNotEmpty) ...[
                Row(
                  children: [
                    Checkbox(
                      value:
                          _selectedChildren.length == _childNamesById.length,
                      onChanged: (val) => _toggleSelectAll(val ?? false),
                    ),
                    const Text("Assign to All Children"),
                  ],
                ),
                ..._childNamesById.entries.map((entry) {
                  return CheckboxListTile(
                    title: Text(entry.value),
                    value: _selectedChildren.contains(entry.key),
                    onChanged: (val) {
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
              ElevatedButton(
                onPressed: _submitForm,
                child: const Text('Create Chore Bid'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
