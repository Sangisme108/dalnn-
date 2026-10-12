import 'package:hive/hive.dart';

/// InventoryHistoryEntry represents a single warehouse event.
///
/// type:
/// - 'in'      : nhập kho (tăng tồn)
/// - 'out'     : xuất kho (giảm tồn)
/// - 'adjust'  : kiểm kê/điều chỉnh (có thể +/-)
class InventoryHistoryEntry {
  final String id;
  final String type;
  final String itemId;
  final String itemName;
  final String unit;

  /// quantityChange is the signed quantity change (e.g. +10, -5).
  final int quantityChange;

  final int beforeQuantity;
  final int afterQuantity;

  final String note;
  final DateTime createdAt;

  InventoryHistoryEntry({
    required this.id,
    required this.type,
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.quantityChange,
    required this.beforeQuantity,
    required this.afterQuantity,
    required this.note,
    required this.createdAt,
  });
}

class InventoryHistoryEntryAdapter extends TypeAdapter<InventoryHistoryEntry> {
  @override
  final int typeId = 11;

  @override
  InventoryHistoryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      final key = reader.readByte();
      final value = reader.read();
      fields[key] = value;
    }

    return InventoryHistoryEntry(
      id: fields[0].toString(),
      type: fields[1].toString(),
      itemId: fields[2].toString(),
      itemName: fields[3].toString(),
      unit: fields[4].toString(),
      quantityChange: (fields[5] as num).toInt(),
      beforeQuantity: (fields[6] as num).toInt(),
      afterQuantity: (fields[7] as num).toInt(),
      note: (fields[8] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (fields[9] as num).toInt(),
      ),
    );
  }

  @override
  void write(BinaryWriter writer, InventoryHistoryEntry obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.itemId)
      ..writeByte(3)
      ..write(obj.itemName)
      ..writeByte(4)
      ..write(obj.unit)
      ..writeByte(5)
      ..write(obj.quantityChange)
      ..writeByte(6)
      ..write(obj.beforeQuantity)
      ..writeByte(7)
      ..write(obj.afterQuantity)
      ..writeByte(8)
      ..write(obj.note)
      ..writeByte(9)
      ..write(obj.createdAt.millisecondsSinceEpoch);
  }
}
