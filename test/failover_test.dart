import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/core/errors/exceptions.dart';
import 'package:crypto_portfolio/data/datasources/remote/coinmarketcap_datasource.dart';
import 'package:crypto_portfolio/data/datasources/remote/crypto_remote_datasource.dart';
import 'package:crypto_portfolio/data/datasources/remote/failover_datasource.dart';
import 'package:crypto_portfolio/data/datasources/remote/symbol_registry.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/price_quote.dart';

/// Records what it was asked for and answers however the test dictates.
class ScriptedSource implements CryptoRemoteDatasource {
  ScriptedSource(this.name, {this.failWith});

  final String name;
  final Object? failWith;
  final List<String> calls = [];

  T _answer<T>(String call, T value) {
    calls.add(call);
    if (failWith != null) throw failWith!;
    return value;
  }

  @override
  Future<Map<String, PriceQuote>> getMultiplePrices(List<String> ids) async =>
      _answer('prices', {
        for (final id in ids)
          id: PriceQuote(price: name == 'primary' ? 100 : 101, change24h: 1)
      });

  @override
  Future<double> getCryptoPrice(String coinId) async =>
      _answer('price', name == 'primary' ? 100.0 : 101.0);

  @override
  Future<List<PricePoint>> getMarketChart(String id, {int days = 90}) async =>
      _answer('chart', [PricePoint(DateTime(2026, 1, 1), 100)]);

  @override
  Future<Map<String, dynamic>?> getCoinDetails(String id) async =>
      _answer('details', {'source': name});

  @override
  Future<List<String>> getCoinCategories(String id) async =>
      _answer('categories', [name]);

  @override
  Future<List<Map<String, dynamic>>> searchCoins(String q) async =>
      _answer('search', [
        {'id': name}
      ]);

  @override
  Future<String?> resolveCoinId(
          {required String symbol, required String name}) async =>
      _answer('resolve', 'resolved');
}

class CountingAdapter implements HttpClientAdapter {
  final List<String> requests = [];
  Object Function(RequestOptions options)? responder;
  int status = 200;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _,
      Future<void>? __) async {
    requests.add('${options.path}?${options.queryParameters}');
    final body = responder?.call(options) ?? {};
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('failover', () {
    test('a healthy primary is used alone', () async {
      final primary = ScriptedSource('primary');
      final backup = ScriptedSource('backup');
      final source =
          FailoverRemoteDatasource(primary: primary, backup: backup);

      final prices = await source.getMultiplePrices(['bitcoin']);

      expect(prices['bitcoin']!.price, 100);
      expect(backup.calls, isEmpty, reason: 'no reason to spend a credit');
    });

    test('a network failure falls through to the backup', () async {
      final primary =
          ScriptedSource('primary', failWith: const RemoteException('429'));
      final backup = ScriptedSource('backup');
      final source =
          FailoverRemoteDatasource(primary: primary, backup: backup);

      final prices = await source.getMultiplePrices(['bitcoin']);

      expect(prices['bitcoin']!.price, 101, reason: 'served by the backup');
      expect(backup.calls, ['prices']);
    });

    test('an unknown coin is not asked of the backup', () async {
      // CoinGecko saying a coin does not exist is an answer, not an outage.
      // The backup would only cost a request to repeat it.
      final primary = ScriptedSource('primary',
          failWith: const CoinNotFoundException('mantra-dao'));
      final backup = ScriptedSource('backup');
      final source =
          FailoverRemoteDatasource(primary: primary, backup: backup);

      await expectLater(
        source.getMarketChart('mantra-dao'),
        throwsA(isA<CoinNotFoundException>()),
      );
      expect(backup.calls, isEmpty);
    });

    test('when both refuse, the primary reason is reported', () async {
      final primary = ScriptedSource('primary',
          failWith: const RemoteException('primary down'));
      final backup = ScriptedSource('backup',
          failWith: const RemoteException('not mirrored'));
      final source =
          FailoverRemoteDatasource(primary: primary, backup: backup);

      await expectLater(
        source.getCoinDetails('bitcoin'),
        throwsA(predicate(
            (e) => e is RemoteException && e.message == 'primary down')),
        reason: 'the backup may simply not mirror this call',
      );
    });

    test('with no backup configured the failure passes straight through',
        () async {
      final primary =
          ScriptedSource('primary', failWith: const RemoteException('down'));
      final source = FailoverRemoteDatasource(primary: primary);

      await expectLater(
        source.getMultiplePrices(['bitcoin']),
        throwsA(isA<RemoteException>()),
      );
    });

    test('search and id repair never fail over', () async {
      // Both only make sense against CoinGecko's own catalogue.
      final primary = ScriptedSource('primary');
      final backup = ScriptedSource('backup');
      final source =
          FailoverRemoteDatasource(primary: primary, backup: backup);

      await source.searchCoins('bitcoin');
      await source.resolveCoinId(symbol: 'OM', name: 'MANTRA');

      expect(backup.calls, isEmpty);
    });

    test('reports which source answered', () async {
      final served = <bool>[];
      final source = FailoverRemoteDatasource(
        primary:
            ScriptedSource('primary', failWith: const RemoteException('429')),
        backup: ScriptedSource('backup'),
        onServed: served.add,
      );

      await source.getCryptoPrice('bitcoin');
      expect(served, [true], reason: 'the banner needs to know');
    });
  });

  group('symbol registry', () {
    test('translates the ids it knows and names those it does not', () {
      final registry = SymbolRegistry()
        ..register('bitcoin', 'btc')
        ..register('ethereum', 'ETH');

      final resolved = registry.resolve(['bitcoin', 'ethereum', 'mystery']);

      expect(resolved.known, {'bitcoin': 'BTC', 'ethereum': 'ETH'},
          reason: 'symbols are normalised to upper case');
      expect(resolved.unknown, ['mystery']);
    });

    test('ignores empty entries', () {
      final registry = SymbolRegistry()
        ..register('', 'BTC')
        ..register('bitcoin', '');
      expect(registry.isEmpty, isTrue);
    });
  });

  group('CoinMarketCap datasource', () {
    late CountingAdapter adapter;
    late SymbolRegistry registry;
    late CoinMarketCapDatasource source;

    setUp(() {
      adapter = CountingAdapter();
      registry = SymbolRegistry()
        ..register('bitcoin', 'BTC')
        ..register('aave', 'AAVE');
      final dio = Dio(BaseOptions(baseUrl: 'https://cmc.test'))
        ..httpClientAdapter = adapter;
      source = CoinMarketCapDatasource(dio: dio, registry: registry);
    });

    test('asks by ticker and maps the answer back to CoinGecko ids', () async {
      adapter.responder = (_) => {
            'data': {
              'BTC': {
                'quote': {
                  'USD': {'price': 80000.0, 'percent_change_24h': -1.5}
                }
              },
              'AAVE': {
                'quote': {
                  'USD': {'price': 131.19, 'percent_change_24h': 0.4}
                }
              },
            }
          };

      final prices = await source.getMultiplePrices(['bitcoin', 'aave']);

      expect(adapter.requests.single, contains('BTC'));
      expect(prices['bitcoin']!.price, 80000.0);
      expect(prices['bitcoin']!.change24h, -1.5);
      expect(prices['aave']!.price, 131.19);
    });

    test('accepts the list shape some endpoints return', () async {
      adapter.responder = (_) => {
            'data': {
              'BTC': [
                {
                  'quote': {
                    'USD': {'price': 80000.0, 'percent_change_24h': 2.0}
                  }
                }
              ]
            }
          };

      final prices = await source.getMultiplePrices(['bitcoin']);
      expect(prices['bitcoin']!.price, 80000.0);
    });

    test('a coin with no known ticker cannot be asked for', () async {
      await expectLater(
        source.getMultiplePrices(['unknown-coin']),
        throwsA(isA<RemoteException>()),
      );
      expect(adapter.requests, isEmpty, reason: 'no request worth making');
    });

    test('history is returned oldest first', () async {
      adapter.responder = (_) => {
            'data': {
              'quotes': [
                {
                  'timestamp': '2026-08-22T00:00:00.000Z',
                  'quote': {
                    'USD': {'price': 110.0}
                  }
                },
                {
                  'timestamp': '2026-08-20T00:00:00.000Z',
                  'quote': {
                    'USD': {'price': 100.0}
                  }
                },
              ]
            }
          };

      final chart = await source.getMarketChart('bitcoin', days: 30);

      expect(chart.map((p) => p.price), [100.0, 110.0]);
    });

    test('a request beyond twelve months is capped, not refused', () async {
      // The free plan stops at a year, exactly like CoinGecko, so asking for
      // more would only earn an error.
      adapter.responder = (_) => {
            'data': {'quotes': []}
          };

      await source.getMarketChart('bitcoin', days: 2000);

      final sent = adapter.requests.single;
      expect(sent, contains('time_start'));
      expect(sent, isNot(contains('2020')));
    });

    test('refuses the calls it cannot mirror faithfully', () async {
      // Serving these from a different taxonomy would change what the numbers
      // mean without saying so.
      await expectLater(
          source.getCoinDetails('bitcoin'), throwsA(isA<RemoteException>()));
      await expectLater(
          source.getCoinCategories('bitcoin'), throwsA(isA<RemoteException>()));
      expect(await source.searchCoins('btc'), isEmpty);
      expect(await source.resolveCoinId(symbol: 'B', name: 'B'), isNull);
    });
  });
}
