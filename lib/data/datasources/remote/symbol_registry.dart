/// Maps CoinGecko ids to ticker symbols.
///
/// The datasource interface speaks CoinGecko ids (`quant-network`) while
/// CoinMarketCap speaks symbols (`QNT`). Rather than spend a request bridging
/// them, this is filled from the portfolio itself: every stored coin already
/// carries both, so the mapping is free and cannot drift from what the user
/// actually holds.
class SymbolRegistry {
  final Map<String, String> _symbols = {};

  void register(String coinId, String symbol) {
    if (coinId.isEmpty || symbol.isEmpty) return;
    _symbols[coinId] = symbol.toUpperCase();
  }

  void registerAll(Map<String, String> pairs) {
    pairs.forEach(register);
  }

  String? symbolFor(String coinId) => _symbols[coinId];

  /// Symbols for the ids we know, and the ids we could not translate.
  ({Map<String, String> known, List<String> unknown}) resolve(
    List<String> coinIds,
  ) {
    final known = <String, String>{};
    final unknown = <String>[];
    for (final id in coinIds) {
      final symbol = _symbols[id];
      if (symbol == null) {
        unknown.add(id);
      } else {
        known[id] = symbol;
      }
    }
    return (known: known, unknown: unknown);
  }

  bool get isEmpty => _symbols.isEmpty;
}
