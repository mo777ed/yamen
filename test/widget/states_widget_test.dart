import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yemen_chat/core/errors/failures.dart';
import 'package:yemen_chat/shared/components/speaking_ring.dart';
import 'package:yemen_chat/shared/widgets/gradient_button.dart';
import 'package:yemen_chat/shared/widgets/states.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('EmptyState shows message and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(testApp(EmptyState(message: 'لا يوجد شيء', actionLabel: 'إعادة', onAction: () => tapped = true)));
    expect(find.text('لا يوجد شيء'), findsOneWidget);
    await tester.tap(find.text('إعادة'));
    expect(tapped, isTrue);
  });

  testWidgets('ErrorState shows a friendly message and retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(testApp(ErrorState(error: const Failure('x', 'حدث خطأ ما'), onRetry: () => retried = true), strings: {'common.retry': 'Retry'}));
    expect(find.text('حدث خطأ ما'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('GradientButton is inert while loading', (tester) async {
    var taps = 0;
    await tester.pumpWidget(testApp(GradientButton(label: 'Go', onPressed: () => taps++, loading: true)));
    await tester.tap(find.byType(GradientButton));
    expect(taps, 0);
    await tester.pumpWidget(testApp(GradientButton(label: 'Go', onPressed: () => taps++)));
    await tester.tap(find.text('Go'));
    expect(taps, 1);
  });

  testWidgets('AsyncBody covers loading, error, empty and data', (tester) async {
    Widget body(AsyncValue<List<int>> v) => testApp(
          AsyncBody<List<int>>(value: v, loading: const Text('loading'), isEmpty: (l) => l.isEmpty, emptyMessage: 'empty!', data: (l) => Text('n=${l.length}')),
          strings: {'common.retry': 'Retry'},
        );
    await tester.pumpWidget(body(const AsyncValue.loading()));
    expect(find.text('loading'), findsOneWidget);
    await tester.pumpWidget(body(const AsyncValue.data([])));
    expect(find.text('empty!'), findsOneWidget);
    await tester.pumpWidget(body(const AsyncValue.data([1, 2])));
    expect(find.text('n=2'), findsOneWidget);
    await tester.pumpWidget(body(AsyncValue.error(const Failure('e', 'boom'), StackTrace.empty)));
    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('SpeakingRing toggles without throwing', (tester) async {
    Widget ring(bool speaking) => testApp(Center(child: SpeakingRing(speaking: speaking, child: const SizedBox(width: 40, height: 40))));
    await tester.pumpWidget(ring(false));
    await tester.pumpWidget(ring(true));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(ring(false));
    expect(tester.takeException(), isNull);
  });
}
