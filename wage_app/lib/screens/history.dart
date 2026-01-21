import 'package:flutter/material.dart';

class History extends StatelessWidget {
  const History({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.history, size: 64, color: Colors.purple),
          SizedBox(height: 16),
          Text('履歴一覧', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('月別給料合計を確認できます', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
