import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() with the real instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'));

class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._prefs) : super(Locale(_prefs.getString(_key) ?? 'ar'));
  final SharedPreferences _prefs;
  static const _key = 'locale';

  Future<void> set(String code) async {
    state = Locale(code);
    await _prefs.setString(_key, code);
  }
}

final localeProvider = StateNotifierProvider<LocaleController, Locale>((ref) => LocaleController(ref.watch(sharedPrefsProvider)));

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_read(_prefs));
  final SharedPreferences _prefs;
  static const _key = 'theme_mode';

  static ThemeMode _read(SharedPreferences p) {
    switch (p.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark; // dark is the default
    }
  }

  Future<void> set(ThemeMode m) async {
    state = m;
    await _prefs.setString(_key, m.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>((ref) => ThemeModeController(ref.watch(sharedPrefsProvider)));
