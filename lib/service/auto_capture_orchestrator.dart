import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kiosque_samsung_ultra/service/bluetooth_fridge_service.dart';
import 'package:kiosque_samsung_ultra/service/auto_capture_service.dart';
import 'package:kiosque_samsung_ultra/service/api.dart';
import 'package:kiosque_samsung_ultra/screen/consumption_review.dart';

/// ═══════════════════════════════════════════════════════════
/// ORCHESTRATEUR AUTO-CAPTURE avec choix Entrée/Sortie
/// ═══════════════════════════════════════════════════════════

enum SessionType { entry, exit }

class AutoCaptureOrchestrator extends ChangeNotifier {
  final BluetoothFridgeService bluetoothService;
  final AutoCaptureService captureService;
  final KioskApiService api;
  final BuildContext context; // Pour afficher le dialogue

  AutoCaptureOrchestrator({
    required this.bluetoothService,
    required this.captureService,
    required this.api,
    required this.context,
  });

  StreamSubscription? _eventSubscription;

  // État global
  bool _isActive = false;
  bool _isUploading = false;
  bool _isWaitingUserChoice = false; // NOUVEAU
  int? _fridgeId;

  // Session courante
  String? _currentSessionId;
  List<File> _pendingPhotos = [];
  DateTime? _sessionStartTime;

  // Statistiques
  int _totalSessionsProcessed = 0;
  int _totalPhotosUploaded = 0;
  int _failedUploads = 0;

  // ═══════════ GETTERS ═══════════
  bool get isActive => _isActive;
  bool get isUploading => _isUploading;
  bool get isWaitingUserChoice => _isWaitingUserChoice;
  bool get hasSession => _currentSessionId != null;
  int get pendingPhotoCount => _pendingPhotos.length;

  // ═══════════════════════════════════════════════════════
  // INITIALISATION
  // ═══════════════════════════════════════════════════════

  Future<void> init(int fridgeId) async {
    _fridgeId = fridgeId;

    debugPrint(
      '🎯 AutoCaptureOrchestrator: Initialisation pour frigo #$fridgeId',
    );

    _subscribeToBluetoothEvents();
    debugPrint('✅ Orchestrateur prêt');
  }

  void _subscribeToBluetoothEvents() {
    _eventSubscription = bluetoothService.eventStream.listen(
      _handleFridgeEvent,
      onError: (error) {
        debugPrint('❌ Erreur stream Bluetooth: $error');
      },
    );

    debugPrint('👂 Écoute des événements Bluetooth activée');
  }

  // ═══════════════════════════════════════════════════════
  // GESTION DES ÉVÉNEMENTS FRIGO
  // ═══════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════
  // OUVERTURE DU FRIGO
  // ═══════════════════════════════════════════════════════

  Future<void> _onFridgeOpened() async {
    if (_isActive) {
      debugPrint('⚠️ Session déjà active, ignoré');
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
      debugPrint('✅ Capture démarrée avec succès');
    } else {
      debugPrint('❌ Échec démarrage capture');
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

  // ═══════════════════════════════════════════════════════
  // FERMETURE DU FRIGO
  // ═══════════════════════════════════════════════════════

  Future<void> _onFridgeClosed(Map<String, dynamic>? data) async {
    if (!_isActive) {
      debugPrint('⚠️ Pas de session active, ignoré');
      return;
    }

    debugPrint('🚪 ═══════════════════════════════════');
    debugPrint('🚪 FRIGO FERMÉ - ARRÊT CAPTURE');
    debugPrint('🚪 ═══════════════════════════════════');

    // Arrêter la capture
    _pendingPhotos = await captureService.stopCaptureSession();

    final photoCount = _pendingPhotos.length;
    final duration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds
        : 0;

    debugPrint('📊 Session terminée:');
    debugPrint('   - Photos: $photoCount');
    debugPrint('   - Durée: ${duration}s');

    _isActive = false;
    notifyListeners();

    // ═══════════════════════════════════════════════════════
    // 🎯 NOUVEAU : Demander le type de session à l'utilisateur
    // ═══════════════════════════════════════════════════════

    if (_pendingPhotos.isEmpty) {
      debugPrint('ℹ️ Aucune photo à traiter');
      _cleanupSession();
      return;
    }

    // Afficher le dialogue modal
    final sessionType = await _showSessionTypeDialog();

    if (sessionType == null) {
      // Ne devrait jamais arriver (dialogue unskippable)
      debugPrint('⚠️ Aucun choix fait, annulation');
      _cleanupSession();
      return;
    }

    // Uploader selon le type choisi
    await _uploadPhotos(sessionType);
  }

  // ═══════════════════════════════════════════════════════
  // 🆕 DIALOGUE MODAL POUR CHOISIR LE TYPE
  // ═══════════════════════════════════════════════════════

  Future<SessionType?> _showSessionTypeDialog() async {
    _isWaitingUserChoice = true;
    notifyListeners();

    debugPrint('❓ Affichage du dialogue de choix...');

    final result = await showDialog<SessionType>(
      context: context,
      barrierDismissible: false, // UNSKIPPABLE
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => false, // Empêche le back button
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
                  // Icône
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

                  // Titre
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

                  // Description
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

                  // Bouton ENTRÉE
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

                  // Bouton SORTIE
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

                  // Bouton annuler (optionnel)
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

    debugPrint('✅ Choix fait: ${result?.toString() ?? "Annulé"}');

    return result;
  }

  // ═══════════════════════════════════════════════════════
  // UPLOAD DES PHOTOS (modifié)
  // ═══════════════════════════════════════════════════════

  Future<void> _uploadPhotos(SessionType type) async {
    if (_fridgeId == null) {
      debugPrint('❌ Pas de fridgeId configuré');
      _cleanupSession();
      return;
    }

    if (_pendingPhotos.isEmpty) {
      debugPrint('ℹ️ Aucune photo à uploader');
      _cleanupSession();
      return;
    }

    _isUploading = true;
    notifyListeners();

    debugPrint('📤 ═══════════════════════════════════');
    debugPrint(
      '📤 UPLOAD ${_pendingPhotos.length} PHOTOS (${type == SessionType.entry ? "ENTRÉE" : "SORTIE"})',
    );
    debugPrint('📤 ═══════════════════════════════════');

    if (type == SessionType.entry) {
      // ═══════════════════════════════════════════════════
      // MODE ENTRÉE : Ajout automatique
      // ═══════════════════════════════════════════════════
      await _uploadForEntry();
    } else {
      // ═══════════════════════════════════════════════════
      // MODE SORTIE : Analyse + Revue manuelle
      // ═══════════════════════════════════════════════════
      await _uploadForExit();
    }

    _isUploading = false;
    notifyListeners();
  }

  /// Upload pour ENTRÉE : analyse et ajout automatique
  Future<void> _uploadForEntry() async {
    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < _pendingPhotos.length; i++) {
      final photo = _pendingPhotos[i];

      debugPrint('📤 Upload photo ${i + 1}/${_pendingPhotos.length}...');

      try {
        await api.analyzeImage(_fridgeId!, photo);

        successCount++;
        _totalPhotosUploaded++;

        debugPrint('   ✅ Réussi');

        await bluetoothService.notifyPhotoTaken();
      } catch (e) {
        debugPrint('   ❌ Échec: $e');
        failCount++;
        _failedUploads++;
      }

      if (i < _pendingPhotos.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    debugPrint('📊 Résultat upload ENTRÉE:');
    debugPrint('   ✅ Réussis: $successCount');
    debugPrint('   ❌ Échecs: $failCount');

    _totalSessionsProcessed++;

    // Afficher notification de succès
    if (successCount > 0) {
      _showSnackBar(
        '✅ $successCount photo${successCount > 1 ? 's' : ''} traitée${successCount > 1 ? 's' : ''} - Produits ajoutés',
        Colors.green,
      );
    }

    await _cleanupSession();
  }

  /// Upload pour SORTIE : analyse puis navigation vers revue
  Future<void> _uploadForExit() async {
    debugPrint('🔄 Mode SORTIE : analyse pour consommation...');

    // Prendre la première photo la plus claire (ou fusionner)
    final bestPhoto = _pendingPhotos.first;

    try {
      // Analyser pour la consommation
      final analysisResult = await api.analyzeImageForConsumption(
        _fridgeId!,
        bestPhoto,
      );

      debugPrint('✅ Analyse consommation réussie');

      // Notifier Arduino
      await bluetoothService.notifyPhotoTaken();

      _totalSessionsProcessed++;
      _totalPhotosUploaded++;

      // Navigation vers la page de revue
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
          _showSnackBar('✅ Produits retirés avec succès', Colors.green);
        }
      }
    } catch (e) {
      debugPrint('❌ Erreur analyse consommation: $e');
      _failedUploads++;

      _showSnackBar('❌ Erreur lors de l\'analyse: $e', Colors.red);

      await _cleanupSession();
    }
  }

  // ═══════════════════════════════════════════════════════
  // UTILITAIRES UI
  // ═══════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════
  // NETTOYAGE
  // ═══════════════════════════════════════════════════════

  Future<void> _cleanupSession() async {
    if (_currentSessionId == null) return;

    debugPrint('🗑️ Nettoyage session: $_currentSessionId');

    await captureService.cleanupSessionFiles(_currentSessionId!);

    _currentSessionId = null;
    _pendingPhotos.clear();
    _sessionStartTime = null;

    notifyListeners();

    debugPrint('✅ Session nettoyée');
  }

  // ═══════════════════════════════════════════════════════
  // CONTRÔLES MANUELS
  // ═══════════════════════════════════════════════════════

  Future<void> cancelCurrentSession() async {
    if (!_isActive) return;

    debugPrint('❌ Annulation session en cours');

    await captureService.stopCaptureSession();

    _isActive = false;
    await _cleanupSession();

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  // STATISTIQUES
  // ═══════════════════════════════════════════════════════

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
