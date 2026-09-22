import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lightweight localization backed by assets/l10n/{ar,en}.json.
/// Missing keys fall back to English, then to the key itself (visible in dev).
class AppStrings {
  AppStrings(this.locale, this._map, this._fallback);
  final Locale locale;
  final Map<String, String> _map;
  final Map<String, String> _fallback;

  static const supported = [Locale('ar'), Locale('en')];
  static const delegate = _AppStringsDelegate();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings)!;

  bool get isArabic => locale.languageCode == 'ar';

  String tr(String key, [Map<String, Object?> params = const {}]) {
    var s = _map[key] ?? _fallback[key] ?? key;
    params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  /// For tests: build without the asset bundle.
  factory AppStrings.fromMaps(Locale l, Map<String, String> m, [Map<String, String> fb = const {}]) =>
      AppStrings(l, m, fb);
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => ['ar', 'en'].contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async {
    final lang = isSupported(locale) ? locale.languageCode : 'ar';
    final main = await _read(lang);
    final fallback = lang == 'en' ? main : await _read('en');
    return AppStrings(Locale(lang), main, fallback);
  }

  Future<Map<String, String>> _read(String lang) async {
    final raw = await rootBundle.loadString('assets/l10n/$lang.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}

extension TrX on BuildContext {
  String tr(String key, [Map<String, Object?> params = const {}]) => AppStrings.of(this).tr(key, params);
  bool get isArabic => AppStrings.of(this).isArabic;
}
