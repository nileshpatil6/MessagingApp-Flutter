import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/local_storage.dart';

class LocaleNotifier extends StateNotifier<bool> {
  LocaleNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    state = await LocalStorage.getIsJapanese();
  }

  Future<void> toggle() async {
    state = !state;
    await LocalStorage.setIsJapanese(state);
  }

  Future<void> setJapanese(bool value) async {
    state = value;
    await LocalStorage.setIsJapanese(value);
  }
}

/// true = Japanese (primary), false = English
final localeProvider = StateNotifierProvider<LocaleNotifier, bool>(
  (ref) => LocaleNotifier(),
);
