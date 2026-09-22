import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failures.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/user_repository.dart';

/// [type] is user | room | message. For messages, [targetId] is "roomId~messageId".
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.type, required this.targetId});
  final String type;
  final String targetId;
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  static const reasons = ['spam', 'harassment', 'hate', 'sexual', 'violence', 'scam', 'underage', 'other'];
  String _reason = 'spam';
  final _details = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final text = _details.text.trim();
      await ref.read(userRepositoryProvider).report(
            reporterId: ref.read(myUidProvider),
            targetType: widget.type,
            targetId: widget.targetId,
            reason: text.isEmpty ? _reason : '$_reason: $text',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('report.sent'))));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('report.${widget.type}'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(context.tr('report.why'), style: const TextStyle(fontWeight: FontWeight.w800)),
        RadioGroupCompat(
          value: _reason,
          onChanged: (v) => setState(() => _reason = v),
          items: [for (final r in reasons) (r, context.tr('report.reason_$r'))],
        ),
        TextField(controller: _details, maxLength: 400, maxLines: 4, decoration: InputDecoration(hintText: context.tr('report.details'))),
        const SizedBox(height: 12),
        GradientButton(label: context.tr('report.submit'), onPressed: _submit, loading: _busy),
      ]),
    );
  }
}

/// Radio list that works on every Flutter 3.x version (RadioListTile's group API changed in 3.32).
class RadioGroupCompat extends StatelessWidget {
  const RadioGroupCompat({super.key, required this.value, required this.onChanged, required this.items});
  final String value;
  final ValueChanged<String> onChanged;
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final it in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(it.$2),
          leading: Icon(value == it.$1 ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: value == it.$1 ? Theme.of(context).colorScheme.primary : null),
          onTap: () => onChanged(it.$1),
        ),
    ]);
  }
}
