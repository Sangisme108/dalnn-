import 'package:hive/hive.dart';
import '../utils/type_converters.dart';

/// InventoryItem is a separate model used only for warehouse/inventory records.
/// We provide a manual TypeAdapter so it works without code generation.
class InventoryItem {
  String id;
  String name;
  double price;
  double? importPrice;
  String unit;
  int stockQuantity;
  int? categoryId;
  String? imageUrl;

  InventoryItem({
    required this.id,
    required this.name,
    required this.price,
    this.importPrice,
    required this.unit,
    this.stockQuantity = 0,
    this.categoryId,
    this.imageUrl,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: (json['barcode'] ?? json['id'] ?? json['inventory_item_id'])
          .toString(),
      name: (json['item_name'] ?? json['name'] ?? '').toString(),
      price: TypeConverters.toDouble(json['price']),
      importPrice: json['import_price'] == null && json['importPrice'] == null
          ? null
          : TypeConverters.toDouble(
              json['import_price'] ?? json['importPrice'],
            ),
      unit: (json['unit'] ?? 'sp').toString(),
      stockQuantity: TypeConverters.toInt(
        json['stock'] ?? json['stockQuantity'],
      ),
      categoryId: TypeConverters.toNullableInt(
        json['category_id'] ?? json['categoryId'],
      ),
      imageUrl: (json['image_url'] ?? json['imageUrl'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inventory_item_id': int.tryParse(id),
      'barcode': id,
      'item_name': name,
      'price': price,
      'import_price': importPrice,
      'unit': unit,
      'stock': stockQuantity,
      // IMPORTANT: backend expects category_id (or categoryId)
      'category_id': categoryId,
      'image_url': imageUrl,
    };
  }
}

class InventoryItemAdapter extends TypeAdapter<InventoryItem> {
  @override
  final int typeId = 10; // pick an id unlikely to collide

  @override
  InventoryItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      final key = reader.readByte();
      final value = reader.read();
      fields[key] = value;
    }

    return InventoryItem(
      id: fields[0].toString(),
      name: fields[1].toString(),
      price: (fields[2] as num).toDouble(),
      unit: fields[3].toString(),
      stockQuantity: (fields[4] as num).toInt(),
      importPrice: fields[5] == null ? null : (fields[5] as num).toDouble(),
      categoryId: fields[6] == null ? null : (fields[6] as num).toInt(),
      imageUrl: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, InventoryItem obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.price)
      ..writeByte(3)
      ..write(obj.unit)
      ..writeByte(4)
      ..write(obj.stockQuantity)
      ..writeByte(5)
      ..write(obj.importPrice)
      ..writeByte(6)
      ..write(obj.categoryId)
      ..writeByte(7)
      ..write(obj.imageUrl);
  }
}
