import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/failures.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_strings.dart';
import 'skeleton.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined, this.actionLabel, this.onAction});
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: context.palette.textMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted, fontSize: 15)),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 52, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(friendlyError(error), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(context.tr('common.retry'))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard loading / error / empty / data handling for any AsyncValue.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.isEmpty,
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final bool Function(T data)? isEmpty;
  final String? emptyMessage;
  final IconData emptyIcon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading ?? const SkeletonList(),
      error: (e, _) => ErrorState(error: e, onRetry: onRetry),
      data: (d) {
        if (isEmpty != null && isEmpty!(d)) {
          return EmptyState(message: emptyMessage ?? context.tr('common.empty'), icon: emptyIcon);
        }
        return data(d);
      },
    );
  }
}

/// Thin banner shown when the device is offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.danger.withOpacity(0.9),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Text(context.tr('common.offline'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 13)),
    );
  }
}
