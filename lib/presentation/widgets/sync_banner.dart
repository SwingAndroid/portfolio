import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/sync/sync_status.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/cloud/sync_service.dart';
import '../../injection_container.dart';
import '../bloc/auth/auth_cubit.dart';
import '../bloc/portfolio/portfolio_bloc.dart';
import '../bloc/portfolio/portfolio_event.dart';

/// Compact strip showing cloud-sync health, with a manual retry and a local
/// backup escape hatch.
///
/// Cloud writes used to fail inside an empty catch block, so a broken sync was
/// invisible. Nothing here is decorative: it exists so a failure can never go
/// unnoticed again.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final status = sl<SyncStatus>();

    return ValueListenableBuilder<SyncSnapshot>(
      valueListenable: status,
      builder: (context, snap, _) {
        final held = snap.health == SyncHealth.held;
        final failing = snap.health == SyncHealth.failing;
        final accent = held
            ? AppTheme.primary
            : (failing ? AppTheme.loss : AppTheme.profit);

        final message = held
            ? '${snap.pendingCount} records exist only on this device. '
                'Back them up, then send them to the cloud.'
            : failing
                ? 'Cloud sync failing — your data is safe on this device but '
                    'is not backed up.'
                : 'Synced with cloud';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: held || failing
                  ? accent.withOpacity(0.08)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: held || failing
                    ? accent.withOpacity(0.35)
                    : AppTheme.cardBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      held
                          ? Icons.cloud_upload_outlined
                          : (failing
                              ? Icons.cloud_off_rounded
                              : Icons.cloud_done_rounded),
                      size: 16,
                      color: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                            color: held || failing
                                ? AppTheme.textSecondary
                                : AppTheme.textTertiary,
                            fontSize: 11,
                            height: 1.35),
                      ),
                    ),
                    if (!held && !failing)
                      IconButton(
                        tooltip: 'Back up locally',
                        onPressed: () => showBackupSheet(context),
                        icon: const Icon(Icons.save_alt_rounded, size: 18),
                        color: AppTheme.textSecondary,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.only(left: 6),
                      ),
                  ],
                ),
                // The held state is the one moment a backup really matters, so
                // both actions get a full-size target rather than an icon.
                if (held || failing) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => showBackupSheet(context),
                          icon: const Icon(Icons.save_alt_rounded, size: 16),
                          label: const Text('Back up',
                              style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            side: const BorderSide(color: AppTheme.cardBorder),
                            minimumSize: const Size(0, 38),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _retry(context),
                          icon: const Icon(Icons.cloud_upload_outlined,
                              size: 16),
                          label: Text(held ? 'Send to cloud' : 'Retry',
                              style: const TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(0, 38),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _retry(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final portfolio = context.read<PortfolioBloc>();
    final report = await context.read<AuthCubit>().retrySync();
    if (!context.mounted) return;

    messenger.showSnackBar(SnackBar(
      backgroundColor: report.ok ? AppTheme.surface : AppTheme.loss,
      content: Text(
        report.ok
            ? 'Synced: ${report.pushedTransactions} transactions, '
                '${report.pushedCryptos} coins uploaded.'
            : 'Sync failed: ${report.error}',
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      ),
    ));
    if (report.ok && report.pushed > 0) {
      portfolio.add(const RefreshPortfolioEvent());
    }
  }
}

/// Shows the full local dataset as JSON so it can be copied out of the app.
///
/// Deliberately dependency-free and offline-only: it reads Hive and nothing
/// else, so it works when every network path is broken.
Future<void> showBackupSheet(BuildContext context) async {
  final json = await sl<SyncService>().exportJson();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.save_alt_rounded,
                    color: AppTheme.primary, size: 18),
                SizedBox(width: 8),
                Text('Local backup',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Everything stored on this device, including anything the cloud '
              'has never received. Copy this somewhere safe.',
              style: const TextStyle(
                  color: AppTheme.textTertiary, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  backgroundColor: AppTheme.surface,
                  content: Text('Backup copied to clipboard',
                      style: TextStyle(color: AppTheme.textPrimary)),
                ));
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text('Copy all (${json.length ~/ 1024} KB)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SelectableText(
                    json,
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        height: 1.35),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Signs out, but never silently. If local data has not reached the cloud the
/// user is told exactly how much is at stake and offered a backup first —
/// logging out wipes the local store, which is the only copy.
Future<void> confirmAndSignOut(BuildContext context) async {
  final auth = context.read<AuthCubit>();
  final blocked = await auth.signOut();
  if (blocked == null || !context.mounted) return;

  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Unsynced data',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
      content: Text(
        '${blocked.transactions} transactions and ${blocked.cryptos} coins '
        'exist only on this device. Signing out erases local data, so they '
        'would be lost permanently.',
        style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'backup'),
          child: const Text('Back up first',
              style: TextStyle(color: AppTheme.primary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'cancel'),
          child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'force'),
          child: const Text('Sign out anyway',
              style: TextStyle(color: AppTheme.loss)),
        ),
      ],
    ),
  );

  if (!context.mounted) return;
  if (choice == 'backup') {
    await showBackupSheet(context);
  } else if (choice == 'force') {
    await auth.signOut(force: true);
  }
}
