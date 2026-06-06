import 'package:equatable/equatable.dart';

enum TransactionType { buy, sell }

class TransactionEntity extends Equatable {
  final String id;
  final String cryptoId;
  final TransactionType type;
  final double quantity;
  final double pricePerCoin;
  final DateTime date;
  final String? note;

  const TransactionEntity({
    required this.id,
    required this.cryptoId,
    required this.type,
    required this.quantity,
    required this.pricePerCoin,
    required this.date,
    this.note,
  });

  double get totalValue => quantity * pricePerCoin;

  @override
  List<Object?> get props => [id, cryptoId, type, quantity, pricePerCoin, date, note];
}
