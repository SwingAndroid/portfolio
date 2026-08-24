/// A live price together with its 24-hour move.
///
/// The 24h figure was already being requested from CoinGecko
/// (`include_24hr_change=true`) and then discarded, so the detail page showed
/// a permanent "0.00%". Carrying it in the same object makes dropping it
/// again much harder.
class PriceQuote {
  final double price;
  final double change24h;

  const PriceQuote({required this.price, this.change24h = 0});

  static const zero = PriceQuote(price: 0);
}
