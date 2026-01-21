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

  static const List<Widget> _pages = [
    Home(),
    JobManagement(),
    WorkInput(),
    History(),
  ];

  static const List<String> _titles = [
    'ホーム',
    'バイト先管理',
    '勤務入力',
    '履歴一覧',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
      ),
      body: _pages[_selectedIndex],
      floatingActionButton: _selectedIndex == 2
          ? FloatingActionButton(
              onPressed: () {
                // TODO: Implement add work entry
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.business), label: 'バイト先'),
          BottomNavigationBarItem(icon: Icon(Icons.access_time), label: '勤務入力'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '履歴'),
        ],
      ),
    );
  }
}
