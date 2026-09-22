import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/badges.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../wallet/data/wallet_repository.dart';

const kGameIds = ['dice', 'wheel', 'rps', 'guess'];
const kWheelSegments = ['0x', '0.5x', '1x', '1.5x', '2x', '5x'];

final gameConfigProvider = StreamProvider.family<GameConfig, String>((ref, id) => ref.watch(firestoreProvider).doc('${Col.games}/$id').snapshots().map((s) {
      final m = s.data() ?? {};
      return GameConfig(
        id: id,
        nameRaw: m['name'],
        enabled: m['enabled'] != false,
        minBet: asInt(m['minBet']) == 0 ? 10 : asInt(m['minBet']),
        maxBet: asInt(m['maxBet']) == 0 ? 10000 : asInt(m['maxBet']),
      );
    }));

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  static const _icons = {'dice': Icons.casino_rounded, 'wheel': Icons.donut_large_rounded, 'rps': Icons.back_hand_rounded, 'guess': Icons.pin_rounded};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider).valueOrNull ?? const WalletData();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('games.title')), actions: [Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: CoinChip(amount: Fmt.compact(wallet.coins), onTap: () => context.push('/wallet')))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: [
            for (final id in kGameIds)
              GlassCard(
                onTap: () => context.push('/games/$id'),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_icons[id], size: 44, color: AppColors.primary),
                  const SizedBox(height: 10),
                  Text(context.tr('game.$id'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(context.tr('games.notice'), style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
      ]),
    );
  }
}

class GameRoomScreen extends ConsumerStatefulWidget {
  const GameRoomScreen({super.key, required this.gameId});
  final String gameId;
  @override
  ConsumerState<GameRoomScreen> createState() => _GameRoomScreenState();
}

class _GameRoomScreenState extends ConsumerState<GameRoomScreen> {
  int _bet = 10;
  String _choice = '';
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _key;
  static const _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    _choice = _defaultChoice();
  }

  String _defaultChoice() {
    switch (widget.gameId) {
      case 'dice':
        return 'high';
      case 'rps':
        return 'rock';
      case 'guess':
        return '5';
      default:
        return 'spin';
    }
  }

  Future<void> _play(GameConfig cfg) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    _key ??= _uuid.v4();
    try {
      final res = await ref.read(functionsClientProvider).call(Fn.playGame, {'gameId': widget.gameId, 'choice': _choice, 'bet': _bet, 'idempotencyKey': _key});
      _key = null; // next round gets a fresh key
      if (mounted) setState(() => _result = res);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _choices() {
    switch (widget.gameId) {
      case 'dice':
        return SegmentedButton<String>(
          segments: [ButtonSegment(value: 'low', label: Text(context.tr('game.low'))), ButtonSegment(value: 'high', label: Text(context.tr('game.high')))],
          selected: {_choice},
          onSelectionChanged: (s) => setState(() => _choice = s.first),
        );
      case 'rps':
        return SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'rock', label: Text(context.tr('game.rock')), icon: const Icon(Icons.circle_rounded)),
            ButtonSegment(value: 'paper', label: Text(context.tr('game.paper')), icon: const Icon(Icons.description_rounded)),
            ButtonSegment(value: 'scissors', label: Text(context.tr('game.scissors')), icon: const Icon(Icons.content_cut_rounded)),
          ],
          selected: {_choice},
          onSelectionChanged: (s) => setState(() => _choice = s.first),
        );
      case 'guess':
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (var n = 1; n <= 10; n++) ChoiceChip(label: Text('$n'), selected: _choice == '$n', onSelected: (_) => setState(() => _choice = '$n')),
        ]);
      default:
        return Text(context.tr('game.wheel_hint'), style: TextStyle(color: context.palette.textMuted));
    }
  }

  String _detailText(Map<String, dynamic> r) {
    final d = asMap(r['detail']);
    switch (widget.gameId) {
      case 'dice':
        return '🎲 ${d['roll']}';
      case 'wheel':
        final i = asInt(d['segment']);
        return '🎡 ${kWheelSegments[i.clamp(0, kWheelSegments.length - 1)]}';
      case 'rps':
        return '${context.tr('game.house')}: ${context.tr('game.${d['house']}')}';
      case 'guess':
        return '${context.tr('game.secret')}: ${d['secret']}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(gameConfigProvider(widget.gameId)).valueOrNull ?? GameConfig(id: widget.gameId);
    final wallet = ref.watch(walletProvider).valueOrNull ?? const WalletData();
    final bets = <int>{for (final b in [10, 50, 100, 500, 1000, 5000]) if (b >= cfg.minBet && b <= cfg.maxBet) b}.toList();
    if (bets.isNotEmpty && !bets.contains(_bet)) _bet = bets.first;
    final r = _result;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('game.${widget.gameId}')), actions: [Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: CoinChip(amount: Fmt.compact(wallet.coins)))]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: GlassCard(
            key: ValueKey(r?.hashCode ?? 0),
            child: SizedBox(
              height: 150,
              child: Center(
                child: _busy
                    ? const CircularProgressIndicator()
                    : r == null
                        ? Text(context.tr('game.ready'), style: TextStyle(color: context.palette.textMuted))
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(_detailText(r), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            Text(
                              r['won'] == true ? context.tr('game.won', {'n': Fmt.number(asInt(r['payout']))}) : r['draw'] == true ? context.tr('game.draw') : context.tr('game.lost'),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: r['won'] == true ? AppColors.success : r['draw'] == true ? AppColors.gold : AppColors.danger),
                            ),
                          ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Align(alignment: AlignmentDirectional.centerStart, child: Text(context.tr('game.your_choice'), style: const TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(height: 8),
        _choices(),
        const SizedBox(height: 20),
        Align(alignment: AlignmentDirectional.centerStart, child: Text(context.tr('game.bet'), style: const TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [for (final b in bets) ChoiceChip(label: Text(Fmt.number(b)), selected: _bet == b, onSelected: (_) => setState(() => _bet = b))]),
        const SizedBox(height: 24),
        GradientButton(
          label: cfg.enabled ? context.tr('game.play') : context.tr('game.disabled'),
          icon: Icons.play_arrow_rounded,
          loading: _busy,
          onPressed: cfg.enabled && wallet.coins >= _bet ? () => _play(cfg) : null,
        ),
        if (wallet.coins < _bet) TextButton(onPressed: () => context.push('/wallet'), child: Text(context.tr('gift.recharge'))),
        const SizedBox(height: 12),
        Text(context.tr('games.notice'), style: TextStyle(color: context.palette.textMuted, fontSize: 12), textAlign: TextAlign.center),
      ]),
    );
  }
}
