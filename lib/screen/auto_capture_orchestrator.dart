import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kiosque_samsung_ultra/service/bluetooth_fridge_service.dart';
import 'package:kiosque_samsung_ultra/service/auto_capture_service.dart';
import 'package:kiosque_samsung_ultra/service/api.dart';
import 'package:kiosque_samsung_ultra/screen/consumption_review.dart';
import 'package:kiosque_samsung_ultra/screen/vision_scan.dart';

enum SessionType { entry, exit }

class AutoCaptureOrchestrator extends ChangeNotifier {
  final BluetoothFridgeService bluetoothService;
  final AutoCaptureService captureService;
  final KioskApiService api;
  final BuildContext context;

  AutoCaptureOrchestrator({
    required this.bluetoothService,
    required this.captureService,
    required this.api,
    required this.context,
  });

  StreamSubscription? _eventSubscription;

  bool _isActive = false;
  bool _isUploading = false;
  bool _isWaitingUserChoice = false;
  int? _fridgeId;

  String? _currentSessionId;
  List<File> _pendingPhotos = [];
  DateTime? _sessionStartTime;

  int _totalSessionsProcessed = 0;
  int _totalPhotosUploaded = 0;
  int _failedUploads = 0;

  bool get isActive => _isActive;
  bool get isUploading => _isUploading;
  bool get isWaitingUserChoice => _isWaitingUserChoice;
  bool get hasSession => _currentSessionId != null;
  int get pendingPhotoCount => _pendingPhotos.length;

  Future<void> init(int fridgeId) async {
    _fridgeId = fridgeId;

    debugPrint('AutoCaptureOrchestrator: Initialisation pour frigo #$fridgeId');

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
    debugPrint('📨 Événement reçu: ${event.event}');

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

    debugPrint('🚪 ═══════════════════════════════════');
    debugPrint('🚪 FRIGO OUVERT - DÉMARRAGE CAPTURE');
    debugPrint('🚪 ═══════════════════════════════════');

    _isActive = true;
    _sessionStartTime = DateTime.now();
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _pendingPhotos.clear();

    notifyListeners();

    final success = await captureService.startCaptureSession();

    if (success) {
      debugPrint('Capture démarrée avec succès');

      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VisionScanPage(
              fridgeId: _fridgeId!,
              mode: ScanPageMode.autoCapture,
              autoCaptureService: captureService,
            ),
          ),
        );
      }
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
      debugPrint('💓 Frigo toujours ouvert - $photoCount photos');
    }
  }

  Future<void> _onFridgeClosed(Map<String, dynamic>? data) async {
    if (!_isActive) {
      debugPrint('Pas de session active, ignoré');
      return;
    }

    debugPrint('🚪 ═══════════════════════════════════');
    debugPrint('🚪 FRIGO FERMÉ - ARRÊT CAPTURE');
    debugPrint('🚪 ═══════════════════════════════════');

    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    _pendingPhotos = await captureService.stopCaptureSession();

    final photoCount = _pendingPhotos.length;
    final duration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds
        : 0;

    debugPrint('Session terminée:');
    debugPrint('   - Photos: $photoCount');
    debugPrint('   - Durée: ${duration}s');

    _isActive = false;
    notifyListeners();

    if (_pendingPhotos.isEmpty) {
      debugPrint('Aucune photo à traiter');
      _cleanupSession();
      return;
    }

    final sessionType = await _showSessionTypeDialog();

    if (sessionType == null) {
      debugPrint('Aucun choix fait, annulation');
      _cleanupSession();
      return;
    }

    await _uploadPhotos(sessionType);
  }

  Future<SessionType?> _showSessionTypeDialog() async {
    if (!context.mounted) return null;

    _isWaitingUserChoice = true;
    notifyListeners();

    debugPrint('❓ Affichage du dialogue de choix...');

    final result = await showDialog<SessionType>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E293B)
                    : Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.help_outline,
                      size: 48,
                      color: Color(0xFF3B82F6),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'Type d\'opération',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    '${_pendingPhotos.length} photo${_pendingPhotos.length > 1 ? 's' : ''} capturée${_pendingPhotos.length > 1 ? 's' : ''}.\nAvez-vous ajouté ou retiré des produits ?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black54,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(SessionType.entry);
                      },
                      icon: const Icon(Icons.add_circle_outline, size: 24),
                      label: const Text('Ajout de produits'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(SessionType.exit);
                      },
                      icon: const Icon(Icons.remove_circle_outline, size: 24),
                      label: const Text('Retrait de produits'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(null);
                    },
                    child: Text(
                      'Annuler (pas de changement)',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white54
                            : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    _isWaitingUserChoice = false;
    notifyListeners();

    debugPrint('Choix fait: ${result?.toString() ?? "Annulé"}');

    return result;
  }

  Future<void> _uploadPhotos(SessionType type) async {
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
    debugPrint(
      'UPLOAD ${_pendingPhotos.length} PHOTOS (${type == SessionType.entry ? "ENTRÉE" : "SORTIE"})',
    );
    debugPrint('═══════════════════════════════════');

    if (type == SessionType.entry) {
      await _uploadForEntry();
    } else {
      await _uploadForExit();
    }

    _isUploading = false;
    notifyListeners();
  }

  Future<void> _uploadForEntry() async {
    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < _pendingPhotos.length; i++) {
      final photo = _pendingPhotos[i];

      debugPrint('Upload photo ${i + 1}/${_pendingPhotos.length}...');

      try {
        await api.analyzeImage(_fridgeId!, photo);

        successCount++;
        _totalPhotosUploaded++;

        debugPrint('   Réussi');

        await bluetoothService.notifyPhotoTaken();
      } catch (e) {
        debugPrint('   Échec: $e');
        failCount++;
        _failedUploads++;
      }

      if (i < _pendingPhotos.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    debugPrint('Résultat upload ENTRÉE:');
    debugPrint('   Réussis: $successCount');
    debugPrint('   Échecs: $failCount');

    _totalSessionsProcessed++;

    if (successCount > 0) {
      _showSnackBar(
        '$successCount photo${successCount > 1 ? 's' : ''} traitée${successCount > 1 ? 's' : ''} - Produits ajoutés',
        Colors.green,
      );
    }

    await _cleanupSession();
  }

  Future<void> _uploadForExit() async {
    debugPrint('Mode SORTIE : analyse pour consommation...');

    final bestPhoto = _pendingPhotos.first;

    try {
      final analysisResult = await api.analyzeImageForConsumption(
        _fridgeId!,
        bestPhoto,
      );

      debugPrint('Analyse consommation réussie');

      await bluetoothService.notifyPhotoTaken();

      _totalSessionsProcessed++;
      _totalPhotosUploaded++;

      await _cleanupSession();

      if (context.mounted) {
        final confirmed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => ConsumptionReviewPage(
              fridgeId: _fridgeId!,
              analysisResult: analysisResult,
            ),
          ),
        );

        if (confirmed == true) {
          _showSnackBar('Produits retirés avec succès', Colors.green);
        }
      }
    } catch (e) {
      debugPrint('Erreur analyse consommation: $e');
      _failedUploads++;

      _showSnackBar('Erreur lors de l\'analyse: $e', Colors.red);

      await _cleanupSession();
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _cleanupSession() async {
    if (_currentSessionId == null) return;

    debugPrint(' Nettoyage session: $_currentSessionId');

    await captureService.cleanupSessionFiles(_currentSessionId!);

    _currentSessionId = null;
    _pendingPhotos.clear();
    _sessionStartTime = null;

    notifyListeners();

    debugPrint('Session nettoyée');
  }

  Future<void> cancelCurrentSession() async {
    if (!_isActive) return;

    debugPrint('Annulation session en cours');

    // Fermer la page de capture
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    await captureService.stopCaptureSession();

    _isActive = false;
    await _cleanupSession();

    notifyListeners();
  }

  Map<String, dynamic> getStats() {
    return {
      'is_active': _isActive,
      'is_uploading': _isUploading,
      'is_waiting_user_choice': _isWaitingUserChoice,
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

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}
