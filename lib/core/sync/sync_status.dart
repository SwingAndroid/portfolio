import 'package:flutter/foundation.dart';

/// Where the last cloud write stood.
enum SyncHealth {
  /// No write attempted yet this session.
  unknown,

  /// The most recent write reached the cloud.
  synced,

  /// The most recent write failed. Data is safe locally and will be retried,
  /// but it is not in the cloud yet.
  failing,

  /// A backlog exists and the first upload is waiting for the user to approve
  /// it, so they can take a backup first.
  held,
}

@immutable
class SyncSnapshot {
  final SyncHealth health;

  /// Message from the last failed write, for display and diagnosis.
  final String? lastError;

  /// Local records the cloud does not have, as of the last check.
  final int pendingCount;

  final DateTime? lastSuccess;

  const SyncSnapshot({
    this.health = SyncHealth.unknown,
    this.lastError,
    this.pendingCount = 0,
    this.lastSuccess,
  });

  SyncSnapshot copyWith({
    SyncHealth? health,
    String? lastError,
    int? pendingCount,
    DateTime? lastSuccess,
    bool clearError = false,
  }) {
    return SyncSnapshot(
      health: health ?? this.health,
      lastError: clearError ? null : (lastError ?? this.lastError),
      pendingCount: pendingCount ?? this.pendingCount,
      lastSuccess: lastSuccess ?? this.lastSuccess,
    );
  }
}

/// Single place the app reports cloud-write health to.
///
/// Writes used to fail inside an empty `catch (_) {}`, which is how 77 days of
/// data went missing without a single visible symptom. Every write path now
/// reports here instead.
class SyncStatus extends ValueNotifier<SyncSnapshot> {
  SyncStatus() : super(const SyncSnapshot());

  void reportSuccess() {
    value = value.copyWith(
      health: SyncHealth.synced,
      clearError: true,
      lastSuccess: DateTime.now(),
    );
  }

  void reportFailure(Object error) {
    value = value.copyWith(
      health: SyncHealth.failing,
      lastError: error.toString(),
    );
  }

  void reportPending(int count) {
    value = value.copyWith(pendingCount: count);
  }

  void reportHeld(int count) {
    value = value.copyWith(
      health: SyncHealth.held,
      pendingCount: count,
      clearError: true,
    );
  }
}
