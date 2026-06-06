import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import 'desktop_sidebar.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Sidebar only on true desktop — tablet gets the full-width mobile layout
    if (!Responsive.isDesktop(context)) {
      return child;
    }
    final uri = GoRouterState.of(context).uri.toString();
    final selectedId = _extractCryptoId(uri);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          DesktopSidebar(selectedCryptoId: selectedId),
          const VerticalDivider(width: 1, color: AppTheme.divider),
          Expanded(child: child),
        ],
      ),
    );
  }

  String? _extractCryptoId(String path) {
    final match = RegExp(r'^/crypto/(.+)$').firstMatch(path);
    return match?.group(1);
  }
}
