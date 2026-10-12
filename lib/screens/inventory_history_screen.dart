// lib/screens/inventory_history_screen.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/inventory_history_entry.dart';
import '../services/db_service.dart';

class InventoryHistoryScreen extends StatelessWidget {
  const InventoryHistoryScreen({super.key});

  String _formatDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  ({IconData icon, Color color, String label}) _typeUi(String type) {
    switch (type) {
      case 'in':
        return (
          icon: Icons.call_received,
          color: Colors.green,
          label: 'Nhập kho',
        );
      case 'out':
        return (icon: Icons.call_made, color: Colors.red, label: 'Xuất kho');
      case 'adjust':
        return (icon: Icons.tune, color: Colors.orange, label: 'Điều chỉnh');
      default:
        return (icon: Icons.history, color: Colors.blueGrey, label: 'Lịch sử');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Lịch sử xuất nhập kho',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: ValueListenableBuilder<Box<InventoryHistoryEntry>>(
        valueListenable: DBService.inventoryHistory().listenable(),
        builder: (context, box, _) {
          final entries = box.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (entries.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Chưa có lịch sử nào',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 16),
            itemBuilder: (context, index) {
              final e = entries[index];
              final ui = _typeUi(e.type);

              final signedQty = e.quantityChange;
              final qtyText = signedQty > 0 ? '+$signedQty' : '$signedQty';

              final subtitleLines = <String>[
                'Mã vạch / Mã nội bộ: ${e.itemId}',
                'Tồn: ${e.beforeQuantity} → ${e.afterQuantity} ($qtyText ${e.unit})',
                _formatDateTime(e.createdAt),
              ];
              if (e.note.trim().isNotEmpty) {
                subtitleLines.add('Ghi chú: ${e.note.trim()}');
              }

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ui.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(ui.icon, color: ui.color),
                ),
                title: Text(
                  '${ui.label}: ${e.itemName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(subtitleLines.join('\n')),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
