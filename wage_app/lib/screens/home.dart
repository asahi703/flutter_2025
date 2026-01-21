import 'package:flutter/material.dart';
import 'job_management.dart';
import 'work_input.dart';
import 'history.dart';

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.calendar_today, size: 64, color: Colors.blueAccent),
          SizedBox(height: 16),
          Text('ホーム', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('今月の給料合計: ¥0', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
