import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/states.dart';
import '../data/wallet_repository.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});
  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  Map<String, ProductDetails> _products = {};
  bool _storeAvailable = true;
  bool _loadingProducts = true;

  Future<void> _loadProducts(List<CoinPackage> packages) async {
    final ctrl = ref.read(purchaseControllerProvider.notifier);
    try {
      _storeAvailable = await ctrl.available();
      if (_storeAvailable && packages.isNotEmpty) {
        _products = await ctrl.products(packages.map((p) => p.productId).toSet());
      }
    } catch (_) {
      _storeAvailable = false;
    }
    if (mounted) setState(() => _loadingProducts = false);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider).valueOrNull ?? const WalletData();
    final packages = ref.watch(coinPackagesProvider);
    final purchase = ref.watch(purchaseControllerProvider);

    ref.listen(coinPackagesProvider, (_, next) => next.whenData(_loadProducts));
    ref.listen(purchaseControllerProvider, (_, next) {
      if (next.state == PurchaseUiState.success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('wallet.purchase_success'))));
      } else if (next.state == PurchaseUiState.error && next.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('wallet.title')),
        actions: [IconButton(icon: const Icon(Icons.receipt_long_rounded), tooltip: context.tr('wallet.transactions'), onPressed: () => context.push('/wallet/transactions'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            gradient: const LinearGradient(colors: [Color(0xFF3A2A8F), Color(0xFF1F4FA8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            child: Row(children: [
              Expanded(child: _balance(Icons.monetization_on_rounded, AppColors.gold, context.tr('wallet.coins'), wallet.coins)),
              Container(width: 1, height: 48, color: Colors.white24),
              Expanded(child: _balance(Icons.diamond_rounded, AppColors.secondary, context.tr('wallet.diamonds'), wallet.diamonds)),
            ]),
          ),
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.tr('wallet.diamonds_note'), style: TextStyle(color: context.palette.textMuted, fontSize: 12))),
          const SizedBox(height: 16),
          Text(context.tr('wallet.buy_coins'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          packages.when(
            loading: () => const SkeletonCards(height: 120),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(coinPackagesProvider)),
            data: (list) {
              if (list.isEmpty) return SizedBox(height: 160, child: EmptyState(message: context.tr('wallet.no_packages'), icon: Icons.storefront_rounded));
              if (!_loadingProducts && !_storeAvailable) return SizedBox(height: 160, child: EmptyState(message: context.tr('wallet.store_unavailable'), icon: Icons.storefront_rounded));
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.35),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final pkg = list[i];
                  final product = _products[pkg.productId];
                  final busy = purchase.state == PurchaseUiState.pending || purchase.state == PurchaseUiState.verifying;
                  return GlassCard(
                    onTap: product == null || busy ? null : () => ref.read(purchaseControllerProvider.notifier).buy(product),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.monetization_on_rounded, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text(Fmt.number(pkg.coins), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      ]),
                      if (pkg.bonus > 0) Text('+${Fmt.number(pkg.bonus)} ${context.tr('wallet.bonus')}', style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(product?.price ?? '\$${pkg.priceUsd.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                    ]),
                  );
                },
              );
            },
          ),
          if (purchase.state == PurchaseUiState.verifying || purchase.state == PurchaseUiState.pending)
            Padding(padding: const EdgeInsets.only(top: 16), child: Center(child: Text(context.tr('wallet.processing')))),
        ],
      ),
    );
  }

  Widget _balance(IconData icon, Color color, String label, int value) => Column(children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 6),
        Text(Fmt.number(value), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);
}

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _items = <WalletTx>[];
  QDoc? _cursor;
  bool _loading = true;
  bool _done = false;
  Object? _error;
  String? _type;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _items.clear();
      _cursor = null;
      _done = false;
    }
    if (_done || (!reset && _loading && _items.isNotEmpty)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = ref.read(uidProvider).valueOrNull ?? '';
      final page = await ref.read(walletRepositoryProvider).fetchTransactions(uid, after: _cursor, type: _type);
      _items.addAll(page.items);
      _cursor = page.cursor;
      if (page.items.length < 20) _done = true;
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  IconData _icon(String t) {
    switch (t) {
      case 'purchase':
        return Icons.shopping_bag_rounded;
      case 'gift':
        return Icons.card_giftcard_rounded;
      case 'reward':
        return Icons.emoji_events_rounded;
      case 'refund':
        return Icons.undo_rounded;
      case 'vip':
        return Icons.workspace_premium_rounded;
      case 'game':
        return Icons.casino_rounded;
      default:
        return Icons.tune_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    const types = ['purchase', 'gift', 'reward', 'refund', 'vip', 'game', 'admin_adjustment'];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('wallet.transactions'))),
      body: Column(children: [
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text(context.tr('common.all')), selected: _type == null, onSelected: (_) {
              _type = null;
              _load(reset: true);
            })),
            for (final t in types)
              Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text(context.tr('tx.$t')), selected: _type == t, onSelected: (_) {
                _type = t;
                _load(reset: true);
              })),
          ]),
        ),
        Expanded(
          child: _error != null && _items.isEmpty
              ? ErrorState(error: _error!, onRetry: () => _load(reset: true))
              : _loading && _items.isEmpty
                  ? const SkeletonList()
                  : _items.isEmpty
                      ? EmptyState(message: context.tr('wallet.no_transactions'), icon: Icons.receipt_long_rounded)
                      : ListView.separated(
                          controller: _scroll,
                          itemCount: _items.length + (_loading ? 1 : 0),
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (_, i) {
                            if (i >= _items.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                            final t = _items[i];
                            final positive = t.amount >= 0;
                            return ListTile(
                              leading: CircleAvatar(backgroundColor: context.palette.surfaceHigh, child: Icon(_icon(t.type), size: 20)),
                              title: Text(context.tr('tx.${t.type}')),
                              subtitle: Text(t.createdAt == null ? '' : Fmt.dateTime(t.createdAt!, context.isArabic ? 'ar' : 'en'), style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('${positive ? '+' : ''}${Fmt.number(t.amount)} ${t.currency == 'diamonds' ? '💎' : '🪙'}', style: TextStyle(fontWeight: FontWeight.w800, color: positive ? AppColors.success : AppColors.danger)),
                                Text(Fmt.number(t.balanceAfter), style: TextStyle(fontSize: 11, color: context.palette.textMuted)),
                              ]),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
