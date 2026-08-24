import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/transaction_entity.dart';

part 'transaction_model.g.dart';

@HiveType(typeId: 1)
class TransactionModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String cryptoId;

  @HiveField(2)
  final int typeIndex;

  @HiveField(3)
  final double quantity;

  @HiveField(4)
  final double pricePerCoin;

  @HiveField(5)
  final DateTime date;

  @HiveField(6)
  final String? note;

  /// Added after the first release. Nullable on purpose: Hive returns null for
  /// this field on every record written before it existed, so no migration and
  /// no rewrite of the existing boxes is needed.
  @HiveField(7)
  final double? fee;

  TransactionModel({
    required this.id,
    required this.cryptoId,
    required this.typeIndex,
    required this.quantity,
    required this.pricePerCoin,
    required this.date,
    this.note,
    this.fee,
  });

  TransactionEntity toEntity() => TransactionEntity(
    id: id,
    cryptoId: cryptoId,
    type: TransactionType.values[typeIndex],
    quantity: quantity,
    pricePerCoin: pricePerCoin,
    date: date,
    note: note,
    fee: fee ?? 0,
  );

  factory TransactionModel.fromEntity(TransactionEntity entity) => TransactionModel(
    id: entity.id,
    cryptoId: entity.cryptoId,
    typeIndex: entity.type.index,
    quantity: entity.quantity,
    pricePerCoin: entity.pricePerCoin,
    date: entity.date,
    note: entity.note,
    fee: entity.fee == 0 ? null : entity.fee,
  );
}
