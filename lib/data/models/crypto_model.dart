import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/crypto_entity.dart';
import '../../domain/entities/transaction_entity.dart';

part 'crypto_model.g.dart';

@HiveType(typeId: 0)
class CryptoModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String coinId;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final String symbol;

  @HiveField(4)
  final String? imageUrl;

  CryptoModel({
    required this.id,
    required this.coinId,
    required this.name,
    required this.symbol,
    this.imageUrl,
  });

  CryptoEntity toEntity({
    List<TransactionEntity> transactions = const [],
    double currentPrice = 0,
    double priceChangePercent24h = 0,
  }) =>
      CryptoEntity(
        id: id,
        coinId: coinId,
        name: name,
        symbol: symbol,
        imageUrl: imageUrl,
        transactions: transactions,
        currentPrice: currentPrice,
        priceChangePercent24h: priceChangePercent24h,
      );

  factory CryptoModel.fromEntity(CryptoEntity entity) => CryptoModel(
        id: entity.id,
        coinId: entity.coinId,
        name: entity.name,
        symbol: entity.symbol,
        imageUrl: entity.imageUrl,
      );
}
