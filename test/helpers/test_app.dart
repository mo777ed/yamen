import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yemen_chat/l10n/app_strings.dart';

class _TestDelegate extends LocalizationsDelegate<AppStrings> {
  const _TestDelegate(this.strings);
  final Map<String, String> strings;
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppStrings> load(Locale locale) async => AppStrings.fromMaps(locale, strings);
  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}

/// Wraps [child] in a MaterialApp with in-memory strings (no asset bundle needed).
Widget testApp(Widget child, {Map<String, String> strings = const {}, Locale locale = const Locale('ar')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.supported,
    localizationsDelegates: [
      _TestDelegate(strings),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}
