// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_line.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OrderLineAdapter extends TypeAdapter<OrderLine> {
  @override
  final int typeId = 3;

  @override
  OrderLine read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OrderLine(
      productId: fields[0] as String,
      productName: fields[1] as String,
      quantity: fields[2] as int,
      pricePerUnit: fields[3] as double,
    );
  }

  @override
  void write(BinaryWriter writer, OrderLine obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.productId)
      ..writeByte(1)
      ..write(obj.productName)
      ..writeByte(2)
      ..write(obj.quantity)
      ..writeByte(3)
      ..write(obj.pricePerUnit);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderLineAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
