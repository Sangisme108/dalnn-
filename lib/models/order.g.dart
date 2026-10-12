// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OrderAdapter extends TypeAdapter<Order> {
  @override
  final int typeId = 2;

  @override
  Order read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Order(
      id: fields[0] as String,
      orderDate: fields[1] as DateTime,
      totalAmount: fields[2] as double,
      customerName: fields[3] as String,
      status: fields[4] as String,
      items: (fields[5] as List).cast<OrderLine>(),
      customerId: fields[6] as int?,
      shippingAddress: fields[7] as String?,
      paymentMethod: fields[8] as String?,
      paymentStatus: fields[9] as String?,
      note: fields[10] as String?,
      voucherId: fields[11] as int?,
      discountAmount: fields[12] as double,
      orderType: fields[13] as String? ?? 'offline',
      deliveryMethod: fields[14] as String?,
      transactionId: fields[15] as String?,
      paidAt: fields[16] as DateTime?,
      qrContent: fields[17] as String?,
      transferContent: fields[18] as String?,
      pointsUsed: fields[19] as int? ?? 0,
      pointsEarned: fields[20] as int? ?? 0,
      pointsDiscount: fields[21] as double? ?? 0,
      customerPhone: fields[22] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Order obj) {
    writer
      ..writeByte(23)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.orderDate)
      ..writeByte(2)
      ..write(obj.totalAmount)
      ..writeByte(3)
      ..write(obj.customerName)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.items)
      ..writeByte(6)
      ..write(obj.customerId)
      ..writeByte(7)
      ..write(obj.shippingAddress)
      ..writeByte(8)
      ..write(obj.paymentMethod)
      ..writeByte(9)
      ..write(obj.paymentStatus)
      ..writeByte(10)
      ..write(obj.note)
      ..writeByte(11)
      ..write(obj.voucherId)
      ..writeByte(12)
      ..write(obj.discountAmount)
      ..writeByte(13)
      ..write(obj.orderType)
      ..writeByte(14)
      ..write(obj.deliveryMethod)
      ..writeByte(15)
      ..write(obj.transactionId)
      ..writeByte(16)
      ..write(obj.paidAt)
      ..writeByte(17)
      ..write(obj.qrContent)
      ..writeByte(18)
      ..write(obj.transferContent)
      ..writeByte(19)
      ..write(obj.pointsUsed)
      ..writeByte(20)
      ..write(obj.pointsEarned)
      ..writeByte(21)
      ..write(obj.pointsDiscount)
      ..writeByte(22)
      ..write(obj.customerPhone);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
