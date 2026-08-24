import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/sync/sync_status.dart';
import '../../../data/datasources/cloud/account_sync.dart';
import '../../../data/datasources/cloud/sync_service.dart';
import '../../../data/datasources/local/crypto_local_datasource.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AppAuthState> {
  final SupabaseClient _client;
  final SyncService _syncService;
  final AccountSync _accountSync;
  final SyncStatus? _syncStatus;

  AuthCubit({
    required SupabaseClient client,
    required SyncService syncService,
    required CryptoLocalDatasource local,
    SyncStatus? syncStatus,
  })  : _client = client,
        _syncService = syncService,
        _accountSync = AccountSync(local: local, sync: syncService),
        _syncStatus = syncStatus,
        super(const AuthInitial()) {
    _init();
  }

  void _init() {
    final user = _client.auth.currentUser;
    if (user != null) {
      // Emit first, sync after. The router treats anything other than
      // AuthAuthenticated as logged out, so waiting on the network here used to
      // bounce an authenticated user to /login until the request came back.
      emit(AuthAuthenticated(user));
      unawaited(_syncFor(user.id));
    } else {
      emit(const AuthUnauthenticated());
    }

    _client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        emit(AuthAuthenticated(user));
      } else {
        emit(const AuthUnauthenticated());
      }
    });
  }

  /// Reconciles local and cloud for [userId] via [AccountSync].
  Future<void> _syncFor(String userId) async {
    try {
      final report = await _accountSync.syncForUser(userId);
      if (report.isHeld) {
        _syncStatus?.reportHeld(report.awaiting!.total);
      } else if (report.ok) {
        if (report.pushed > 0) _syncStatus?.reportSuccess();
        _syncStatus?.reportPending(0);
      } else {
        _syncStatus?.reportFailure(report.error!);
      }
    } catch (e) {
      _syncStatus?.reportFailure(e);
    }
  }

  /// Retries the backlog on demand. Returns the report so the UI can show what
  /// happened.
  Future<SyncReport> retrySync() async {
    final user = _client.auth.currentUser;
    if (user == null) return const SyncReport(error: 'Not signed in');
    // A manual tap is the user's approval to upload the backlog.
    final report = await _accountSync.syncForUser(user.id, confirmed: true);
    if (report.ok) {
      _syncStatus?.reportSuccess();
      _syncStatus?.reportPending(0);
    } else {
      _syncStatus?.reportFailure(report.error!);
    }
    return report;
  }

  Future<void> signIn(String email, String password) async {
    emit(const AuthLoading());
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user != null) {
        await _syncFor(user.id);
        emit(AuthAuthenticated(user));
      } else {
        emit(const AuthError('Sign in failed. Please try again.'));
      }
    } on AuthException catch (e) {
      emit(AuthError(e.message));
    } catch (_) {
      emit(const AuthError('An unexpected error occurred.'));
    }
  }

  Future<void> signUp(String email, String password) async {
    emit(const AuthLoading());
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );
      if (response.user != null) {
        emit(AuthAuthenticated(response.user!));
      } else {
        emit(const AuthError('Check your email to confirm your account.'));
      }
    } on AuthException catch (e) {
      emit(AuthError(e.message));
    } catch (_) {
      emit(const AuthError('An unexpected error occurred.'));
    }
  }

  /// Signs out, refusing to wipe local data that the cloud has never seen.
  ///
  /// Returns null when sign-out completed. Returns the pending-data details
  /// when it was refused, so the caller can warn before offering [force].
  Future<UnsyncedDataException?> signOut({bool force = false}) async {
    if (!force) {
      // Last chance to save the backlog before it would be destroyed.
      await _syncService.pushLocalChanges();
      final unsynced = await _syncService.findUnsynced();
      if (unsynced != null) return unsynced;
    }

    try {
      await _syncService.clearLocal(force: true);
      await _client.auth.signOut();
    } catch (_) {
      // Fall through: the session is gone locally either way.
    }
    emit(const AuthUnauthenticated());
    return null;
  }
}
