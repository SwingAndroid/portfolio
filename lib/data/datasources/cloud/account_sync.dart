import '../local/crypto_local_datasource.dart';
import 'sync_service.dart';

/// Decides what syncing is safe for a given signed-in account.
///
/// Kept out of AuthCubit so it can be tested without a live SupabaseClient —
/// this is the code path that runs on every app start, including the first
/// start after a deployment, so it has to be provable.
class AccountSync {
  final CryptoLocalDatasource local;
  final SyncService sync;

  AccountSync({required this.local, required this.sync});

  /// Reconciles this device with [userId]'s cloud account.
  ///
  /// On the very first run after this version is installed, a device that still
  /// holds unsynced records does **not** upload them automatically. It reports
  /// back so the user can take a local backup first and then approve the upload
  /// with [confirmed]. Uploading is additive and safe either way, but the first
  /// run is the one moment where having a backup in hand matters most.
  Future<SyncReport> syncForUser(String userId, {bool confirmed = false}) async {
    final owner = await local.getOwnerUserId();

    if (owner == null) {
      // Nobody has claimed this device yet. Anything already stored predates
      // owner tracking and belongs to whoever is signing in now — this is the
      // path that recovers a pre-existing backlog.
      await local.setOwnerUserId(userId);
    } else if (owner != userId) {
      // Another account's data is on this device. Pull only: never upload it.
      await sync.pullFromCloud();
      return const SyncReport();
    }

    if (!confirmed && !await local.isFirstSyncDone()) {
      final backlog = await sync.findUnsynced();
      if (backlog != null) {
        // Hold. Nothing is written in either direction until approved.
        return SyncReport(awaiting: backlog);
      }
      // Nothing at stake — proceed and stop gating future runs.
      await local.markFirstSyncDone();
      return sync.syncAll();
    }

    final report = await sync.syncAll();
    if (report.ok) await local.markFirstSyncDone();
    return report;
  }
}
