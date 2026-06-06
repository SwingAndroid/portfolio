import 'package:dio/dio.dart';

abstract class CryptoRemoteDatasource {
  Future<double> getCryptoPrice(String coinId);
  Future<List<Map<String, dynamic>>> searchCoins(String query);
  Future<Map<String, dynamic>?> getCoinDetails(String coinId);
  Future<Map<String, double>> getMultiplePrices(List<String> coinIds);
}

class CryptoRemoteDatasourceImpl implements CryptoRemoteDatasource {
  final Dio dio;

  CryptoRemoteDatasourceImpl({required this.dio});

  @override
  Future<double> getCryptoPrice(String coinId) async {
    try {
      final response = await dio.get('/simple/price', queryParameters: {
        'ids': coinId,
        'vs_currencies': 'usd',
      });
      final data = response.data as Map<String, dynamic>;
      return (data[coinId]?['usd'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchCoins(String query) async {
    try {
      final response = await dio.get('/search', queryParameters: {'query': query});
      final coins = (response.data['coins'] as List?) ?? [];
      return coins.take(20).map((c) => Map<String, dynamic>.from(c)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>?> getCoinDetails(String coinId) async {
    try {
      final response = await dio.get('/coins/$coinId', queryParameters: {
        'localization': false,
        'tickers': false,
        'market_data': true,
        'community_data': false,
        'developer_data': false,
      });
      return Map<String, dynamic>.from(response.data);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, double>> getMultiplePrices(List<String> coinIds) async {
    if (coinIds.isEmpty) return {};
    try {
      final response = await dio.get('/simple/price', queryParameters: {
        'ids': coinIds.join(','),
        'vs_currencies': 'usd',
        'include_24hr_change': true,
      });
      final data = response.data as Map<String, dynamic>;
      final result = <String, double>{};
      for (final id in coinIds) {
        result[id] = (data[id]?['usd'] as num?)?.toDouble() ?? 0.0;
      }
      return result;
    } catch (_) {
      return {};
    }
  }
}
