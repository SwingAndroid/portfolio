import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/datasources/cloud/sync_service.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AppAuthState> {
  final SupabaseClient _client;
  final SyncService _syncService;

  AuthCubit({required SupabaseClient client, required SyncService syncService})
      : _client = client,
        _syncService = syncService,
        super(const AuthInitial()) {
    _init();
  }

  void _init() {
    final user = _client.auth.currentUser;
    if (user != null) {
      emit(AuthAuthenticated(user));
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

  Future<void> signIn(String email, String password) async {
    emit(const AuthLoading());
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) {
        await _syncService.pullFromCloud();
        emit(AuthAuthenticated(response.user!));
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

  Future<void> signOut() async {
    try {
      await _syncService.clearLocal();
      await _client.auth.signOut();
      emit(const AuthUnauthenticated());
    } catch (e) {
      emit(const AuthUnauthenticated());
    }
  }
}
