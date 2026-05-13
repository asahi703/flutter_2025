import 'package:flutter/material.dart';

class Home extends StatelessWidget {
  final DateTime selectedMonth;
  final List<DateTime> availableMonths;
  final ValueChanged<DateTime> onMonthChanged;
  final double totalHours;
  final int totalPay;
  final int shiftCount;

  const Home({
    super.key,
    required this.selectedMonth,
    required this.availableMonths,
    required this.onMonthChanged,
    required this.totalHours,
    required this.totalPay,
    required this.shiftCount,
  });

  String _formatMonth(DateTime month) {
    return '${month.year}年${month.month.toString().padLeft(2, '0')}月';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '今月の給与',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('表示月:'),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<DateTime>(
                  value: selectedMonth,
                  isExpanded: true,
                  items: availableMonths.map((month) {
                    return DropdownMenuItem<DateTime>(
                      value: month,
                      child: Text(_formatMonth(month)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      onMonthChanged(value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('合計勤務日数: $shiftCount 日'),
                  const SizedBox(height: 8),
                  Text('合計勤務時間: ${totalHours.toStringAsFixed(2)} 時間'),
                  const SizedBox(height: 8),
                  Text(
                    '推定給与: ¥$totalPay',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('今月の勤務時間と給与をここから確認します。'),
        ],
      ),
    );
  }
}
