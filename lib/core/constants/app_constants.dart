class AppConstants {
  /// Shown next to the title so the running build is identifiable at a
  /// glance — telling whether a PWA has actually picked up a deployment was
  /// guesswork until now.
  ///
  /// Kept in step with `pubspec.yaml` by a test rather than by discipline: a
  /// version label that can drift will eventually lie.
  static const String appVersion = '1.4.1';

  // ── CoinGecko ─────────────────────────────────────────────────────────────
  static const String coingeckoBaseUrl = 'https://api.coingecko.com/api/v3';
  static const String coingeckoApiKey = 'CG-PbBxVvGjPJKaYE7L3GhrqM5L';

  // ── CoinMarketCap ─────────────────────────────────────────────────────────
  static const String coinmarketcapBaseUrl = 'https://pro-api.coinmarketcap.com/v1';
  static const String coinmarketcapApiKey = 'c046c5c4-2519-4937-874b-a20d22b8c368';

  // ── Supabase ──────────────────────────────────────────────────────────────
  static const String supabaseUrl = 'https://ksjglaxzpzsrufbsshwl.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_0xUACLer18cqVThPRT4lkg_Ki2xPLg1';

  // ── Hive boxes ────────────────────────────────────────────────────────────
  static const String cryptoBoxName = 'cryptos';
  static const String transactionBoxName = 'transactions';
  static const String pendingDeleteBoxName = 'pending_deletes';
  static const String valueHistoryBoxName = 'value_history';

  static const Duration priceCacheDuration = Duration(minutes: 5);
}
