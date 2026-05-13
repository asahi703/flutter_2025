import 'package:flutter/material.dart';

class History extends StatelessWidget {
  final List<Map<String, dynamic>> shifts;
  final List<Map<String, dynamic>> workplaces;
  final ValueChanged<Map<String, dynamic>> onEditShift;
  final ValueChanged<int> onDeleteShift;

  const History({
    super.key,
    required this.shifts,
    required this.workplaces,
    required this.onEditShift,
    required this.onDeleteShift,
  });

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (shifts.isEmpty) {
      return const Center(child: Text('履歴がありません。'));
    }
    final sortedShifts = shifts.toList()
      ..sort((a, b) {
        final aDate = a['date'] as DateTime;
        final bDate = b['date'] as DateTime;
        return bDate.compareTo(aDate);
      });
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedShifts.length,
      itemBuilder: (context, index) {
        final shift = sortedShifts[index];
        final workplaceId = shift['workplaceId'] as int;
        final workplace = workplaces.firstWhere(
          (item) => item['id'] == workplaceId,
          orElse: () => {'id': 0, 'name': '未登録', 'hourlyWage': 0},
        );
        final start = shift['start'] as TimeOfDay;
        final end = shift['end'] as TimeOfDay;
        final date = shift['date'] as DateTime;
        final hours = () {
          final startDateTime = DateTime(date.year, date.month, date.day, start.hour, start.minute);
          final endDateTime = DateTime(date.year, date.month, date.day, end.hour, end.minute);
          var duration = endDateTime.difference(startDateTime);
          if (duration.isNegative) {
            duration += const Duration(days: 1);
          }
          return duration.inMinutes / 60.0;
        }();
        final pay = (hours * (workplace['hourlyWage'] as int)).round();
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text('${_formatDate(date)} - ${workplace['name']}'),
            subtitle: Text(
              '勤務: ${start.format(context)}〜${end.format(context)}\n'
              '時間: ${hours.toStringAsFixed(2)}h  推定給与: ¥$pay',
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => onEditShift(shift),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => onDeleteShift(shift['id'] as int),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
