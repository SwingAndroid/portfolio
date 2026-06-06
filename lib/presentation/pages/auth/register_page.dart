import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../bloc/auth/auth_state.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: BlocConsumer<AuthCubit, AppAuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            context.go('/');
          }
          if (state is AuthError &&
              state.message.contains('confirm')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.surface,
                content: Text(state.message,
                    style: const TextStyle(color: AppTheme.textPrimary)),
              ),
            );
            context.go('/login');
          }
        },
        builder: (context, state) {
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back button
                      GestureDetector(
                        onTap: () => context.go('/login'),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.cardBorder),
                          ),
                          child: const Icon(Icons.arrow_back_ios,
                              color: AppTheme.textPrimary, size: 16),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Create account',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Start tracking your crypto portfolio',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 15),
                      ),
                      const SizedBox(height: 40),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined,
                                    color: AppTheme.textSecondary, size: 20),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Enter your email';
                                if (!v.contains('@')) return 'Enter a valid email';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline,
                                    color: AppTheme.textSecondary, size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: AppTheme.textSecondary,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Enter a password';
                                if (v.length < 6) return 'Minimum 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmCtrl,
                              obscureText: _obscure,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Confirm Password',
                                prefixIcon: Icon(Icons.lock_outline,
                                    color: AppTheme.textSecondary, size: 20),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Confirm your password';
                                if (v != _passCtrl.text) return 'Passwords do not match';
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),

                            if (state is AuthError && !state.message.contains('confirm'))
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.loss.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AppTheme.loss.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: AppTheme.loss, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(state.message,
                                          style: const TextStyle(
                                              color: AppTheme.loss, fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 24),

                            ElevatedButton(
                              onPressed: state is AuthLoading ? null : _submit,
                              child: state is AuthLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Text('Create Account'),
                            ),

                            const SizedBox(height: 16),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Already have an account?',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 14)),
                                TextButton(
                                  onPressed: () => context.go('/login'),
                                  child: const Text('Sign In',
                                      style: TextStyle(
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthCubit>().signUp(
            _emailCtrl.text.trim(),
            _passCtrl.text,
          );
    }
  }
}
