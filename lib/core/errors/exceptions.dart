/// Exceptions thrown by the remote datasource.
///
/// These exist so failures stop being silently swallowed: the UI needs to be
/// able to tell "this coin has no data" apart from "the request failed".
library;

/// CoinGecko returned 404 for this coin id.
///
/// Usually means the coin's id was renamed upstream (e.g. `mantra-dao` →
/// `mantra`). The legacy id often still resolves on `/simple/price`, so the
/// coin keeps showing a price while every `/coins/{id}` call fails.
class CoinNotFoundException implements Exception {
  final String coinId;
  const CoinNotFoundException(this.coinId);

  @override
  String toString() => 'CoinNotFoundException($coinId)';
}

/// Any other remote failure — network down, timeout, rate limit, 5xx.
class RemoteException implements Exception {
  final String message;
  const RemoteException(this.message);

  @override
  String toString() => 'RemoteException($message)';
}
