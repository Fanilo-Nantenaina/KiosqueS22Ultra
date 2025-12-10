import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:kiosque_samsung_ultra/service/bluetooth_fridge_service.dart';
import 'package:kiosque_samsung_ultra/service/auto_capture_service.dart';
import 'package:kiosque_samsung_ultra/service/api.dart';

/// ═══════════════════════════════════════════════════════════
/// ORCHESTRATEUR AUTO-CAPTURE
/// Lie le Bluetooth et la capture automatique
/// Gère le flow complet: ouverture → capture → fermeture → upload
/// ═══════════════════════════════════════════════════════════

class AutoCaptureOrchestrator extends ChangeNotifier {
  final BluetoothFridgeService bluetoothService;
  final AutoCaptureService captureService;
  final KioskApiService api;

  AutoCaptureOrchestrator({
    required this.bluetoothService,
    required this.captureService,
    required this.api,
  });

  StreamSubscription? _eventSubscription;

  bool _isActive = false;
  bool _isUploading = false;
  int? _fridgeId;

  String? _currentSessionId;
  List<File> _pendingPhotos = [];
  DateTime? _sessionStartTime;

  int _totalSessionsProcessed = 0;
  int _totalPhotosUploaded = 0;
  int _failedUploads = 0;

  bool get isActive => _isActive;
  bool get isUploading => _isUploading;
  bool get hasSession => _currentSessionId != null;
  int get pendingPhotoCount => _pendingPhotos.length;

  Future<void> init(int fridgeId) async {
    _fridgeId = fridgeId;

    debugPrint(
      '🎯 AutoCaptureOrchestrator: Initialisation pour frigo #$fridgeId',
    );

    _subscribeToBluetoothEvents();

    debugPrint('Orchestrateur prêt');
  }

  void _subscribeToBluetoothEvents() {
    _eventSubscription = bluetoothService.eventStream.listen(
      _handleFridgeEvent,
      onError: (error) {
        debugPrint('Erreur stream Bluetooth: $error');
      },
    );

    debugPrint('Écoute des événements Bluetooth activée');
  }

  Future<void> _handleFridgeEvent(FridgeEventData event) async {
    debugPrint('Événement reçu: ${event.event}');

    switch (event.event) {
      case FridgeEvent.open:
        await _onFridgeOpened();
        break;

      case FridgeEvent.closed:
        await _onFridgeClosed(event.data);
        break;

      case FridgeEvent.stillOpen:
        _onStillOpen();
        break;

      default:
        break;
    }
  }

  Future<void> _onFridgeOpened() async {
    if (_isActive) {
      debugPrint('Session déjà active, ignoré');
      return;
    }

    debugPrint('═══════════════════════════════════');
    debugPrint('FRIGO OUVERT - DÉMARRAGE CAPTURE');
    debugPrint('═══════════════════════════════════');

    _isActive = true;
    _sessionStartTime = DateTime.now();
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _pendingPhotos.clear();

    notifyListeners();

    final success = await captureService.startCaptureSession();

    if (success) {
      debugPrint('Capture démarrée avec succès');
    } else {
      debugPrint('Échec démarrage capture');
      _isActive = false;
      _currentSessionId = null;
      notifyListeners();
    }
  }

  void _onStillOpen() {
    if (_isActive) {
      final stats = captureService.getStats();
      final currentSession = stats['current_session'] as Map<String, dynamic>?;
      final photoCount = currentSession?['photo_count'] ?? 0;
      debugPrint('Frigo toujours ouvert - $photoCount photos');
    }
  }

  Future<void> _onFridgeClosed(Map<String, dynamic>? data) async {
    if (!_isActive) {
      debugPrint('Pas de session active, ignoré');
      return;
    }

    debugPrint('═══════════════════════════════════');
    debugPrint('FRIGO FERMÉ - ARRÊT CAPTURE');
    debugPrint('═══════════════════════════════════');

    _pendingPhotos = await captureService.stopCaptureSession();

    final photoCount = _pendingPhotos.length;
    final duration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds
        : 0;

    debugPrint('Session terminée:');
    debugPrint('Photos: $photoCount');
    debugPrint('Durée: ${duration}s');

    _isActive = false;
    notifyListeners();

    if (_pendingPhotos.isNotEmpty) {
      await _uploadPhotos();
    } else {
      debugPrint('Aucune photo à uploader');
      _cleanupSession();
    }
  }

  Future<void> _uploadPhotos() async {
    if (_fridgeId == null) {
      debugPrint('Pas de fridgeId configuré');
      _cleanupSession();
      return;
    }

    if (_pendingPhotos.isEmpty) {
      debugPrint('Aucune photo à uploader');
      _cleanupSession();
      return;
    }

    _isUploading = true;
    notifyListeners();

    debugPrint('═══════════════════════════════════');
    debugPrint('UPLOAD DE ${_pendingPhotos.length} PHOTOS');
    debugPrint('═══════════════════════════════════');

    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < _pendingPhotos.length; i++) {
      final photo = _pendingPhotos[i];

      debugPrint('Upload photo ${i + 1}/${_pendingPhotos.length}...');

      try {
        await api.analyzeImage(_fridgeId!, photo);

        successCount++;
        _totalPhotosUploaded++;

        debugPrint('Réussi');

        await bluetoothService.notifyPhotoTaken();
      } catch (e) {
        debugPrint('Échec: $e');
        failCount++;
        _failedUploads++;
      }

      if (i < _pendingPhotos.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    debugPrint('Résultat upload:');
    debugPrint('Réussis: $successCount');
    debugPrint('Échecs: $failCount');

    _totalSessionsProcessed++;

    _isUploading = false;
    notifyListeners();

    // Nettoyer
    await _cleanupSession();
  }

  Future<void> _cleanupSession() async {
    if (_currentSessionId == null) return;

    debugPrint('Nettoyage session: $_currentSessionId');

    await captureService.cleanupSessionFiles(_currentSessionId!);

    _currentSessionId = null;
    _pendingPhotos.clear();
    _sessionStartTime = null;

    notifyListeners();

    debugPrint('Session nettoyée');
  }

  Future<void> startManualCapture() async {
    debugPrint('Capture manuelle démarrée');
    await _onFridgeOpened();
  }

  Future<void> stopManualCapture() async {
    debugPrint('Capture manuelle arrêtée');
    await _onFridgeClosed(null);
  }

  Future<void> cancelCurrentSession() async {
    if (!_isActive) return;

    debugPrint('Annulation session en cours');

    // Arrêter capture sans upload
    await captureService.stopCaptureSession();

    _isActive = false;
    await _cleanupSession();

    notifyListeners();
  }

  Future<void> enable() async {
    await captureService.setEnabled(true);
    debugPrint('Auto-capture activée');
  }

  Future<void> disable() async {
    // Si session active, l'annuler
    if (_isActive) {
      await cancelCurrentSession();
    }

    await captureService.setEnabled(false);
    debugPrint('Auto-capture désactivée');
  }

  Map<String, dynamic> getStats() {
    return {
      'is_active': _isActive,
      'is_uploading': _isUploading,
      'has_session': hasSession,
      'pending_photos': pendingPhotoCount,
      'session_duration_seconds': _sessionStartTime != null
          ? DateTime.now().difference(_sessionStartTime!).inSeconds
          : 0,
      'total_sessions_processed': _totalSessionsProcessed,
      'total_photos_uploaded': _totalPhotosUploaded,
      'failed_uploads': _failedUploads,
      'success_rate': _totalSessionsProcessed > 0
          ? ((_totalSessionsProcessed - _failedUploads) /
                    _totalSessionsProcessed *
                    100)
                .toStringAsFixed(1)
          : '0.0',
    };
  }

  void printStats() {
    final stats = getStats();
    debugPrint('═══════════════════════════════════');
    debugPrint('STATISTIQUES AUTO-CAPTURE');
    debugPrint('═══════════════════════════════════');
    debugPrint('traitées: ${stats['total_sessions_processed']}');
    debugPrint('uploadées: ${stats['total_photos_uploaded']}');
    debugPrint('upload: ${stats['failed_uploads']}');
    debugPrint('de succès: ${stats['success_rate']}%');
    debugPrint('═══════════════════════════════════');
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}
