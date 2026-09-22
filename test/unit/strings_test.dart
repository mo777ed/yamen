import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_chat/l10n/app_strings.dart';

Map<String, String> load(String lang) => (jsonDecode(File('assets/l10n/$lang.json').readAsStringSync()) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));

void main() {
  final ar = load('ar');
  final en = load('en');

  test('Arabic and English define exactly the same keys', () {
    expect(ar.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'keys missing in en.json');
    expect(en.keys.toSet().difference(ar.keys.toSet()), isEmpty, reason: 'keys missing in ar.json');
  });

  test('placeholders match between languages', () {
    final re = RegExp(r'\{(\w+)\}');
    for (final k in ar.keys) {
      final a = re.allMatches(ar[k]!).map((m) => m.group(1)).toSet();
      final e = re.allMatches(en[k]!).map((m) => m.group(1)).toSet();
      expect(a, e, reason: 'placeholder mismatch in "$k"');
    }
  });

  test('every tr() key used in the source exists', () {
    final used = <String>{};
    final re = RegExp(r"""tr\(\s*(['"])([^'"$]+)\1""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      used.addAll(re.allMatches(f.readAsStringSync()).map((m) => m.group(2)!));
    }
    expect(used.difference(ar.keys.toSet()), isEmpty);
  });

  test('tr() substitutes params and falls back to the key', () {
    final s = AppStrings.fromMaps(const Locale('en'), {'hi': 'Hello {name}'});
    expect(s.tr('hi', {'name': 'Ali'}), 'Hello Ali');
    expect(s.tr('missing'), 'missing');
  });
}
