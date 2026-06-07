/// Lightweight slice of CoinGecko `/coins/{id}` market_data used by the
/// Entry Signal feature. All fields are nullable because the API response
/// can omit any of them.
class MarketData {
  final double currentPrice;
  final double? ath;
  final double? athChangePercent; // negative number, e.g. -65 = 65% below ATH
  final double? change7d;
  final double? change30d;
  final double? change1y;
  final int? marketCapRank;

  const MarketData({
    required this.currentPrice,
    this.ath,
    this.athChangePercent,
    this.change7d,
    this.change30d,
    this.change1y,
    this.marketCapRank,
  });

  /// Parses the raw `/coins/{id}` response. Returns null when there is no
  /// usable market_data block.
  static MarketData? fromCoinDetails(Map<String, dynamic> json) {
    final m = json['market_data'];
    if (m is! Map) return null;

    double? usd(dynamic node) =>
        (node is Map ? node['usd'] : null) is num ? (node['usd'] as num).toDouble() : null;
    double? num0(dynamic v) => v is num ? v.toDouble() : null;

    final price = usd(m['current_price']);
    if (price == null) return null;

    return MarketData(
      currentPrice: price,
      ath: usd(m['ath']),
      athChangePercent: usd(m['ath_change_percentage']),
      change7d: num0(m['price_change_percentage_7d']),
      change30d: num0(m['price_change_percentage_30d']),
      change1y: num0(m['price_change_percentage_1y']),
      marketCapRank: (m['market_cap_rank'] as num?)?.toInt(),
    );
  }
}
