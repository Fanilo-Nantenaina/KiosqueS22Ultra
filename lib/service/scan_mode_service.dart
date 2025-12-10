import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

enum ScanMode {
  entry, // Ajout de produits
  exit, // Sortie de produits
}

class ScanModeService extends ChangeNotifier {
  static final ScanModeService _instance = ScanModeService._internal();
  factory ScanModeService() => _instance;
  ScanModeService._internal();

  ScanMode _currentMode = ScanMode.entry;
  ScanMode get currentMode => _currentMode;

  bool get isEntryMode => _currentMode == ScanMode.entry;
  bool get isExitMode => _currentMode == ScanMode.exit;

  String get modeLabel => _currentMode == ScanMode.entry ? 'Entrée' : 'Sortie';
  String get modeDescription => _currentMode == ScanMode.entry
      ? 'Ajouter des produits au frigo'
      : 'Retirer des produits consommés';

  /// Initialise depuis SharedPreferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('scan_mode') ?? 'entry';

    _currentMode = savedMode == 'exit' ? ScanMode.exit : ScanMode.entry;
    notifyListeners();
  }

  /// Change le mode et persiste
  Future<void> setMode(ScanMode mode) async {
    if (_currentMode == mode) return;

    _currentMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'scan_mode',
      mode == ScanMode.entry ? 'entry' : 'exit',
    );
  }

  /// Toggle entre Entrée et Sortie
  Future<void> toggleMode() async {
    await setMode(
      _currentMode == ScanMode.entry ? ScanMode.exit : ScanMode.entry,
    );
  }
}
