import 'package:flutter/material.dart';

class JobManagement extends StatelessWidget {
  const JobManagement({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.business, size: 64, color: Colors.green),
          SizedBox(height: 16),
          Text('バイト先管理', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('バイト先の追加・編集・削除を行います', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
