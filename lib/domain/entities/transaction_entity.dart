import 'package:equatable/equatable.dart';

enum TransactionType { buy, sell, transferIn, transferOut }

extension TransactionTypeX on TransactionType {
  bool get addsHoldings => this == TransactionType.buy || this == TransactionType.transferIn;
  bool get removesHoldings => this == TransactionType.sell || this == TransactionType.transferOut;
  bool get isTransfer => this == TransactionType.transferIn || this == TransactionType.transferOut;
}

class TransactionEntity extends Equatable {
  final String id;
  final String cryptoId;
  final TransactionType type;
  final double quantity;
  final double pricePerCoin;
  final DateTime date;
  final String? note;

  /// Trading fee paid on this transaction, in the same currency as
  /// [pricePerCoin]. Defaults to zero so existing records — which predate the
  /// field — behave exactly as before.
  final double fee;

  const TransactionEntity({
    required this.id,
    required this.cryptoId,
    required this.type,
    required this.quantity,
    required this.pricePerCoin,
    required this.date,
    this.note,
    this.fee = 0,
  });

  double get totalValue => quantity * pricePerCoin;

  /// What acquiring these units actually cost, fee included.
  double get grossCost => quantity * pricePerCoin + fee;

  /// What disposing of them actually returned, fee deducted.
  double get netProceeds => quantity * pricePerCoin - fee;

  @override
  List<Object?> get props =>
      [id, cryptoId, type, quantity, pricePerCoin, date, note, fee];
}
