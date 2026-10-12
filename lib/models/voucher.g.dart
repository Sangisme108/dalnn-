// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voucher.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VoucherAdapter extends TypeAdapter<Voucher> {
  @override
  final int typeId = 5;

  @override
  Voucher read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Voucher(
      id: fields[0] as int,
      code: fields[1] as String,
      description: fields[2] as String?,
      discountType: fields[3] as String,
      discountValue: fields[4] as double,
      minOrderAmount: fields[5] as double,
      maxDiscount: fields[6] as double?,
      usageLimit: fields[7] as int?,
      usedCount: fields[8] as int,
      expiryDate: fields[9] as DateTime?,
      status: fields[10] as String,
      createdAt: fields[11] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Voucher obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.code)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.discountType)
      ..writeByte(4)
      ..write(obj.discountValue)
      ..writeByte(5)
      ..write(obj.minOrderAmount)
      ..writeByte(6)
      ..write(obj.maxDiscount)
      ..writeByte(7)
      ..write(obj.usageLimit)
      ..writeByte(8)
      ..write(obj.usedCount)
      ..writeByte(9)
      ..write(obj.expiryDate)
      ..writeByte(10)
      ..write(obj.status)
      ..writeByte(11)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoucherAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
