import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/services/benchmark_service.dart';
import '../../../domain/entities/crypto_entity.dart';

/// Loads the benchmark comparison once per session.
///
/// It costs one chart per yardstick on top of the value curve, against a
/// budget the whole app shares, so a failure earns a rest rather than a retry
/// on every visit.
class BenchmarkCubit extends Cubit<BenchmarkState> {
  final BenchmarkService service;

  BenchmarkCubit({required this.service}) : super(const BenchmarkState.initial());

  bool _loaded = false;

  Future<void> load(List<CryptoEntity> cryptos, {bool force = false}) async {
    if (_loaded && !force) return;
    emit(const BenchmarkState.loading());
    try {
      final result = await service.compare(cryptos: cryptos);
      _loaded = result.error == null && result.hasData;
      emit(BenchmarkState.ready(result));
    } catch (e) {
      emit(BenchmarkState.ready(
        BenchmarkComparison(outcomes: const [], error: e),
      ));
    }
  }
}

class BenchmarkState {
  final bool isLoading;
  final BenchmarkComparison? result;

  const BenchmarkState._(this.isLoading, this.result);

  const BenchmarkState.initial() : this._(true, null);
  const BenchmarkState.loading() : this._(true, null);
  const BenchmarkState.ready(BenchmarkComparison r) : this._(false, r);
}
