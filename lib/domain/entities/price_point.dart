/// A single (time, price) sample from CoinGecko's market_chart endpoint.
class PricePoint {
  final DateTime time;
  final double price;

  const PricePoint(this.time, this.price);
}
