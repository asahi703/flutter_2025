import 'package:flutter/material.dart';

class WorkInputScreen extends StatelessWidget {
  const WorkInputScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.access_time, size: 64, color: Colors.orange),
          SizedBox(height: 16),
          Text('勤務入力', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('日付・出勤・退勤・休憩を入力します', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
