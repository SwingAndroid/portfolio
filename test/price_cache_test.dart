import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/data/datasources/remote/crypto_remote_datasource.dart';

/// Counts outgoing requests and serves canned JSON, so the cache can be
/// observed by what it does *not* send.
class CountingAdapter implements HttpClientAdapter {
  final List<String> requests = [];
  bool failing = false;

  int get calls => requests.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.path}?${options.queryParameters}');
    if (failing) throw DioException(requestOptions: options, error: 'boom');

    final Object body;
    if (options.path.contains('market_chart')) {
      body = {
        'prices': [
          [1756080000000, 100.0],
          [1756166400000, 110.0],
        ]
      };
    } else {
      final ids = (options.queryParameters['ids'] as String).split(',');
      body = {
        for (final id in ids)
          id: {'usd': 42.0, 'usd_24h_change': -1.5}
      };
    }

    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late CountingAdapter adapter;
  late CryptoRemoteDatasourceImpl source;

  setUp(() {
    adapter = CountingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    source = CryptoRemoteDatasourceImpl(dio: dio);
  });

  group('quote cache', () {
    test('a second lookup inside the window sends nothing', () async {
      await source.getMultiplePrices(['bitcoin', 'ethereum']);
      await source.getMultiplePrices(['bitcoin', 'ethereum']);

      expect(adapter.calls, 1,
          reason: '30 calls a minute is the whole budget for the device');
    });

    test('a coin page reuses the price the portfolio just fetched', () async {
      await source.getMultiplePrices(['bitcoin', 'ethereum']);
      final price = await source.getCryptoPrice('bitcoin');

      expect(price, 42.0);
      expect(adapter.calls, 1, reason: 'this per-coin call was pure waste');
    });

    test('only the coins missing from the cache are requested', () async {
      await source.getMultiplePrices(['bitcoin']);
      await source.getMultiplePrices(['bitcoin', 'ethereum']);

      expect(adapter.calls, 2);
      expect(adapter.requests.last, contains('ethereum'));
      expect(adapter.requests.last, isNot(contains('bitcoin')),
          reason: 'the cached one is not re-requested');
    });

    test('all requested coins come back, cached or freshly fetched', () async {
      await source.getMultiplePrices(['bitcoin']);
      final result = await source.getMultiplePrices(['bitcoin', 'ethereum']);

      expect(result.keys.toSet(), {'bitcoin', 'ethereum'});
      expect(result['bitcoin']!.price, 42.0);
    });

    test('the 24h change survives the cache', () async {
      final result = await source.getMultiplePrices(['bitcoin']);
      expect(result['bitcoin']!.change24h, -1.5);

      final again = await source.getMultiplePrices(['bitcoin']);
      expect(again['bitcoin']!.change24h, -1.5);
    });

    test('a stale price is served when the network fails', () async {
      await source.getMultiplePrices(['bitcoin']);
      adapter.failing = true;

      final result = await source.getMultiplePrices(['bitcoin']);

      expect(result['bitcoin']?.price, 42.0,
          reason: 'a stale price beats collapsing the portfolio to zero');
    });

    test('a single-coin lookup also falls back to its cached value', () async {
      await source.getMultiplePrices(['bitcoin']);
      adapter.failing = true;

      expect(await source.getCryptoPrice('bitcoin'), 42.0);
    });

    test('with nothing cached a failure still yields zero, not a crash',
        () async {
      adapter.failing = true;
      expect(await source.getCryptoPrice('bitcoin'), 0.0);
      expect(await source.getMultiplePrices(['bitcoin']), isEmpty);
    });
  });

  group('chart cache', () {
    test('returning to a coin does not spend another chart call', () async {
      await source.getMarketChart('bitcoin', days: 90);
      await source.getMarketChart('bitcoin', days: 90);

      expect(adapter.calls, 1, reason: 'charts are the heaviest requests');
    });

    test('each range is cached separately', () async {
      await source.getMarketChart('bitcoin', days: 90);
      await source.getMarketChart('bitcoin', days: 30);
      await source.getMarketChart('bitcoin', days: 90);

      expect(adapter.calls, 2);
    });

    test('each coin is cached separately', () async {
      await source.getMarketChart('bitcoin', days: 90);
      await source.getMarketChart('ethereum', days: 90);

      expect(adapter.calls, 2);
    });

    test('the cached chart carries the real points', () async {
      final first = await source.getMarketChart('bitcoin', days: 90);
      final second = await source.getMarketChart('bitcoin', days: 90);

      expect(second.length, first.length);
      expect(second.last.price, 110.0);
    });

    test('a chart failure still reports rather than caching an empty list',
        () async {
      adapter.failing = true;
      await expectLater(
        source.getMarketChart('bitcoin', days: 90),
        throwsA(anything),
        reason: 'silently caching a failure would hide it for five minutes',
      );
    });
  });
}
