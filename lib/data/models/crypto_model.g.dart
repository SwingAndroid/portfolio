// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crypto_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CryptoModelAdapter extends TypeAdapter<CryptoModel> {
  @override
  final int typeId = 0;

  @override
  CryptoModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CryptoModel(
      id: fields[0] as String,
      coinId: fields[1] as String,
      name: fields[2] as String,
      symbol: fields[3] as String,
      imageUrl: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, CryptoModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.coinId)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.symbol)
      ..writeByte(4)
      ..write(obj.imageUrl);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptoModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
