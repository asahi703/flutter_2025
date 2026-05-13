import 'package:flutter/material.dart';

class WorkInput extends StatefulWidget {
  final List<Map<String, dynamic>> workplaces;
  final void Function(DateTime date, int workplaceId, TimeOfDay startTime, TimeOfDay endTime)
      onSaveShift;

  const WorkInput({
    super.key,
    required this.workplaces,
    required this.onSaveShift,
  });

  @override
  State<WorkInput> createState() => _WorkInputState();
}

class _WorkInputState extends State<WorkInput> {
  DateTime? _selectedDate;
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  int? _selectedWorkplaceId;

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  TimeOfDay? _parseTime(String text) {
    final parts = text.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  void _saveShift() {
    final startTime = _parseTime(_startController.text);
    final endTime = _parseTime(_endController.text);
    if (_selectedDate == null ||
        _selectedWorkplaceId == null ||
        startTime == null ||
        endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('すべての項目を正しく入力してください。')),
      );
      return;
    }
    widget.onSaveShift(
      _selectedDate!,
      _selectedWorkplaceId!,
      startTime,
      endTime,
    );
    setState(() {
      _selectedDate = null;
      _startController.clear();
      _endController.clear();
      _selectedWorkplaceId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('シフトを保存しました。')),
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'シフト入力',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _pickDate,
            child: Text(
              _selectedDate == null
                  ? '勤務日を選択'
                  : '勤務日: ${_formatDate(_selectedDate!)}',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedWorkplaceId,
            decoration: const InputDecoration(labelText: '勤務先を選択'),
            items: widget.workplaces.map((place) {
              return DropdownMenuItem<int>(
                value: place['id'] as int,
                child: Text('${place['name']} (¥${place['hourlyWage']})'),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedWorkplaceId = value;
              });
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _startController,
                  decoration: const InputDecoration(
                    labelText: '開始時刻 (HH:mm)',
                  ),
                  keyboardType: TextInputType.datetime,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _endController,
                  decoration: const InputDecoration(
                    labelText: '終了時刻 (HH:mm)',
                  ),
                  keyboardType: TextInputType.datetime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveShift,
            child: const Text('シフトを保存'),
          ),
          const SizedBox(height: 12),
          const Text('勤務先は事前に「勤務先管理」で登録してください。'),
        ],
      ),
    );
  }
}
