import 'package:flutter/material.dart';
import 'screens/home.dart';
import 'screens/job_management.dart';
import 'screens/work_input.dart';
import 'screens/history.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '給料管理アプリ',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const WageAppMain(),
    );
  }
}

class WageAppMain extends StatefulWidget {
  const WageAppMain({super.key});

  @override
  State<WageAppMain> createState() => _WageAppMainState();
}

class _WageAppMainState extends State<WageAppMain> {
  int _selectedIndex = 0;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final List<Map<String, dynamic>> _workplaces = [
    {'id': 1, 'name': '本社', 'hourlyWage': 1200},
    {'id': 2, 'name': '支店', 'hourlyWage': 1100},
  ];
  final List<Map<String, dynamic>> _shifts = [];
  int _nextWorkplaceId = 3;
  int _nextShiftId = 1;

  List<DateTime> get _availableMonths {
    final Set<DateTime> months = {
      DateTime(DateTime.now().year, DateTime.now().month),
    };
    for (final shift in _shifts) {
      final date = shift['date'] as DateTime;
      months.add(DateTime(date.year, date.month));
    }
    final monthsList = months.toList()
      ..sort((a, b) => b.compareTo(a));
    return monthsList;
  }

  List<Map<String, dynamic>> get _selectedMonthShifts {
    return _shifts
        .where((shift) {
          final date = shift['date'] as DateTime;
          return date.year == _selectedMonth.year &&
              date.month == _selectedMonth.month;
        })
        .toList()
      ..sort((a, b) {
        final aDate = a['date'] as DateTime;
        final bDate = b['date'] as DateTime;
        return aDate.compareTo(bDate);
      });
  }

  double _shiftHours(Map<String, dynamic> shift) {
    final date = shift['date'] as DateTime;
    final start = shift['start'] as TimeOfDay;
    final end = shift['end'] as TimeOfDay;
    final startDateTime = DateTime(date.year, date.month, date.day, start.hour, start.minute);
    final endDateTime = DateTime(date.year, date.month, date.day, end.hour, end.minute);
    var duration = endDateTime.difference(startDateTime);
    if (duration.isNegative) {
      duration += const Duration(days: 1);
    }
    return duration.inMinutes / 60.0;
  }

  int _shiftPay(Map<String, dynamic> shift) {
    final workplaceId = shift['workplaceId'] as int;
    final place = _workplaces.firstWhere(
      (item) => item['id'] == workplaceId,
      orElse: () => {'id': 0, 'name': '未登録', 'hourlyWage': 0},
    );
    final wage = place['hourlyWage'] as int;
    return (_shiftHours(shift) * wage).round();
  }

  double get _selectedMonthHours {
    return _selectedMonthShifts.fold(0.0, (sum, shift) => sum + _shiftHours(shift));
  }

  int get _selectedMonthPay {
    return _selectedMonthShifts.fold(0, (sum, shift) => sum + _shiftPay(shift));
  }

  void _addOrEditWorkplace({Map<String, dynamic>? workplace}) {
    final nameController =
        TextEditingController(text: workplace != null ? workplace['name'] as String : '');
    final wageController = TextEditingController(
      text: workplace != null ? (workplace['hourlyWage'] as int).toString() : '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(workplace == null ? '勤務先を追加' : '勤務先を編集'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '店名'),
              ),
              TextField(
                controller: wageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '時給'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                final wage = int.tryParse(wageController.text.trim());
                if (name.isEmpty || wage == null || wage <= 0) {
                  return;
                }
                setState(() {
                  if (workplace != null) {
                    final index =
                        _workplaces.indexWhere((item) => item['id'] == workplace['id']);
                    if (index != -1) {
                      _workplaces[index] = {'id': workplace['id'], 'name': name, 'hourlyWage': wage};
                    }
                  } else {
                    _workplaces.add({'id': _nextWorkplaceId++, 'name': name, 'hourlyWage': wage});
                  }
                });
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  void _deleteWorkplace(int id) {
    final used = _shifts.any((shift) => shift['workplaceId'] == id);
    if (used) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('削除できません'),
            content: const Text('この勤務先はシフトで使用されています。先に該当シフトを削除してください。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          );
        },
      );
      return;
    }
    setState(() {
      _workplaces.removeWhere((item) => item['id'] == id);
    });
  }

  void _saveShift(Map<String, dynamic> shift) {
    final index = _shifts.indexWhere((item) => item['id'] == shift['id']);
    setState(() {
      if (index != -1) {
        _shifts[index] = shift;
      } else {
        _shifts.add(shift);
      }
      final date = shift['date'] as DateTime;
      _selectedMonth = DateTime(date.year, date.month);
    });
  }

  void _deleteShift(int id) {
    setState(() {
      _shifts.removeWhere((shift) => shift['id'] == id);
    });
  }

  void _showShiftForm({Map<String, dynamic>? existing}) {
    showDialog(
      context: context,
      builder: (context) {
        return ShiftFormDialog(
          workplaces: _workplaces,
          existing: existing,
          nextShiftId: _nextShiftId,
          onSave: (shift) {
            setState(() {
              if (existing == null) {
                _nextShiftId += 1;
              }
              _saveShift(shift);
            });
            Navigator.pop(context);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      Home(
        selectedMonth: _selectedMonth,
        availableMonths: _availableMonths,
        onMonthChanged: (month) {
          setState(() {
            _selectedMonth = month;
          });
        },
        totalHours: _selectedMonthHours,
        totalPay: _selectedMonthPay,
        shiftCount: _selectedMonthShifts.length,
      ),
      JobManagement(
        workplaces: _workplaces,
        onAdd: () => _addOrEditWorkplace(),
        onEdit: (workplace) => _addOrEditWorkplace(workplace: workplace),
        onDelete: _deleteWorkplace,
      ),
      WorkInput(
        workplaces: _workplaces,
        onSaveShift: (date, workplaceId, startTime, endTime) {
          _saveShift({
            'id': _nextShiftId,
            'date': date,
            'workplaceId': workplaceId,
            'start': startTime,
            'end': endTime,
          });
          _nextShiftId += 1;
        },
      ),
      History(
        shifts: _shifts,
        workplaces: _workplaces,
        onEditShift: (shift) => _showShiftForm(existing: shift),
        onDeleteShift: _deleteShift,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(['ホーム', '勤務先管理', '勤務入力', '履歴一覧'][_selectedIndex]),
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.business), label: '勤務先'),
          BottomNavigationBarItem(icon: Icon(Icons.access_time), label: '勤務入力'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '履歴'),
        ],
      ),
    );
  }
}

class ShiftFormDialog extends StatefulWidget {
  final List<Map<String, dynamic>> workplaces;
  final Map<String, dynamic>? existing;
  final int nextShiftId;
  final ValueChanged<Map<String, dynamic>> onSave;

  const ShiftFormDialog({
    super.key,
    required this.workplaces,
    this.existing,
    required this.nextShiftId,
    required this.onSave,
  });

  @override
  State<ShiftFormDialog> createState() => _ShiftFormDialogState();
}

class _ShiftFormDialogState extends State<ShiftFormDialog> {
  late DateTime _selectedDate;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  int? _selectedWorkplaceId;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.existing != null ? widget.existing!['date'] as DateTime : DateTime.now();
    _selectedWorkplaceId = widget.existing != null ? widget.existing!['workplaceId'] as int : null;
    _startController = TextEditingController(
      text: widget.existing != null ? _formatTime(widget.existing!['start'] as TimeOfDay) : '',
    );
    _endController = TextEditingController(
      text: widget.existing != null ? _formatTime(widget.existing!['end'] as TimeOfDay) : '',
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(_selectedDate.year - 1, 1, 1),
      lastDate: DateTime(_selectedDate.year + 1, 12, 31),
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

  void _save() {
    final startTime = _parseTime(_startController.text);
    final endTime = _parseTime(_endController.text);
    if (_selectedWorkplaceId == null || startTime == null || endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('すべての項目を正しく入力してください。')),
      );
      return;
    }
    widget.onSave({
      'id': widget.existing != null ? widget.existing!['id'] as int : widget.nextShiftId,
      'date': _selectedDate,
      'workplaceId': _selectedWorkplaceId!,
      'start': startTime,
      'end': endTime,
    });
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'シフトを追加' : 'シフトを編集'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: _pickDate,
              child: Text('勤務日: ${_formatDate(_selectedDate)}'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _selectedWorkplaceId,
              decoration: const InputDecoration(labelText: '勤務先'),
              items: widget.workplaces.map((workplace) {
                return DropdownMenuItem<int>(
                  value: workplace['id'] as int,
                  child: Text('${workplace['name']} (¥${workplace['hourlyWage']})'),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
