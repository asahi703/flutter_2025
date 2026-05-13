import 'package:flutter/material.dart';

class JobManagement extends StatelessWidget {
  final List<Map<String, dynamic>> workplaces;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<int> onDelete;

  const JobManagement({
    super.key,
    required this.workplaces,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: workplaces.isEmpty
              ? const Center(child: Text('勤務先を追加してください。'))
              : ListView.builder(
                  itemCount: workplaces.length,
                  itemBuilder: (context, index) {
                    final workplace = workplaces[index];
                    return ListTile(
                      title: Text(workplace['name'] as String),
                      subtitle: Text('時給: ¥${workplace['hourlyWage']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => onEdit(workplace),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => onDelete(workplace['id'] as int),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_business),
            label: const Text('勤務先を追加'),
          ),
        ),
      ],
    );
  }
}
