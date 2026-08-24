import 'package:equatable/equatable.dart';

/// Kinds of movement.
///
/// `reward` is appended last on purpose: Hive stores the enum's *index*, so
/// inserting anywhere else would silently reinterpret every existing record.
enum TransactionType { buy, sell, transferIn, transferOut, reward }

extension TransactionTypeX on TransactionType {
  bool get addsHoldings =>
      this == TransactionType.buy ||
      this == TransactionType.transferIn ||
      this == TransactionType.reward;

  bool get removesHoldings =>
      this == TransactionType.sell || this == TransactionType.transferOut;

  bool get isTransfer =>
      this == TransactionType.transferIn || this == TransactionType.transferOut;

  /// Coins that arrived as income — staking, airdrops — rather than being
  /// bought or moved.
  bool get isIncome => this == TransactionType.reward;
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
  ///
  /// For a reward this is its value at receipt: you did not pay for it, but
  /// that value is what a later sale is measured against.
  double get grossCost => quantity * pricePerCoin + fee;

  /// Capital you actually put in.
  ///
  /// Deliberately distinct from [grossCost]. A staking reward carries a cost
  /// basis but costs no money, so counting it as capital would make the
  /// portfolio look like it had swallowed funds that were never deployed —
  /// deflating every return that divides by capital engaged.
  double get capitalIn => isIncomeMovement ? 0 : grossCost;

  /// Value received as income at the moment it landed.
  double get incomeValue => isIncomeMovement ? quantity * pricePerCoin : 0;

  bool get isIncomeMovement => type == TransactionType.reward;

  /// What disposing of them actually returned, fee deducted.
  double get netProceeds => quantity * pricePerCoin - fee;

  @override
  List<Object?> get props =>
      [id, cryptoId, type, quantity, pricePerCoin, date, note, fee];
}
