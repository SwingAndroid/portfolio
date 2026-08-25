import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/services/diversification_service.dart';
import '../../../domain/entities/crypto_entity.dart';

/// Loads the diversification picture once per session.
///
/// Correlation needs a year of prices per coin and sectors need one lookup
/// each, so this is deliberately cached rather than recomputed on every visit:
/// the device shares 30 requests a minute across the whole app.
class DiversificationCubit extends Cubit<DiversificationState> {
  final DiversificationService service;

  DiversificationCubit({required this.service})
      : super(const DiversificationState.initial());

  bool _loaded = false;

  Future<void> load(List<CryptoEntity> cryptos, {bool force = false}) async {
    if (_loaded && !force) return;
    emit(const DiversificationState.loading());
    try {
      final result = await service.load(cryptos);
      _loaded = result.error == null;
      emit(DiversificationState.ready(result));
    } catch (e) {
      emit(DiversificationState.ready(
        DiversificationResult(
          report: DiversificationResult.empty.report,
          sectors: const [],
          error: e,
        ),
      ));
    }
  }
}

class DiversificationState {
  final bool isLoading;
  final DiversificationResult? result;

  const DiversificationState._(this.isLoading, this.result);

  const DiversificationState.initial() : this._(true, null);
  const DiversificationState.loading() : this._(true, null);
  const DiversificationState.ready(DiversificationResult r) : this._(false, r);
}
