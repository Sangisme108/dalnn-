// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserAdapter extends TypeAdapter<User> {
  @override
  final int typeId = 1;

  @override
  User read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return User(
      userId: fields[13] as int?,
      email: fields[0] as String,
      password: fields[1] as String,
      role: fields[2] as String,
      fullName: fields[3] as String,
      birthYear: fields[4] as int,
      phone: fields[5] as String,
      address: fields[6] as String,
      gender: fields[7] as String,
      startDate: fields[8] as DateTime?,
      avatarPath: fields[9] as String?,
      status: fields[10] as String,
      points: fields[11] as int,
      createdAt: fields[12] as DateTime?,
      membershipCode: fields[14] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, User obj) {
    writer
      ..writeByte(15)
      ..writeByte(13)
      ..write(obj.userId)
      ..writeByte(0)
      ..write(obj.email)
      ..writeByte(1)
      ..write(obj.password)
      ..writeByte(2)
      ..write(obj.role)
      ..writeByte(3)
      ..write(obj.fullName)
      ..writeByte(4)
      ..write(obj.birthYear)
      ..writeByte(5)
      ..write(obj.phone)
      ..writeByte(6)
      ..write(obj.address)
      ..writeByte(7)
      ..write(obj.gender)
      ..writeByte(8)
      ..write(obj.startDate)
      ..writeByte(9)
      ..write(obj.avatarPath)
      ..writeByte(10)
      ..write(obj.status)
      ..writeByte(11)
      ..write(obj.points)
      ..writeByte(12)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.membershipCode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
