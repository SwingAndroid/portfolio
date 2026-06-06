import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AppAuthState extends Equatable {
  const AppAuthState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AppAuthState {
  const AuthInitial();
}

class AuthLoading extends AppAuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AppAuthState {
  final User user;
  const AuthAuthenticated(this.user);
  @override
  List<Object?> get props => [user];
}

class AuthUnauthenticated extends AppAuthState {
  const AuthUnauthenticated();
}

class AuthError extends AppAuthState {
  final String message;
  const AuthError(this.message);
  @override
  List<Object?> get props => [message];
}
