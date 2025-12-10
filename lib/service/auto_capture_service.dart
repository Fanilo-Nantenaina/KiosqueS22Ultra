import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════════
/// Service de capture automatique de photos
/// S'active automatiquement à l'ouverture du frigo
/// ═══════════════════════════════════════════════════════════

enum CaptureState {
  idle,           // Pas de capture en cours
  initializing,   // Initialisation caméra
  ready,          // Caméra prête
  capturing,      // Capture en cours
  processing,     // Traitement/upload photos
}

class CaptureSession {
  final String sessionId;
  final DateTime startTime;
  final List<File> photos;
  DateTime? endTime;
  
  CaptureSession({
    required this.sessionId,
    required this.startTime,
    this.photos = const [],
  });
  
  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);
  int get photoCount => photos.length;
  bool get isActive => endTime == null;
}

class AutoCaptureService extends ChangeNotifier {
  static final AutoCaptureService _instance = AutoCaptureService._internal();
  factory AutoCaptureService() => _instance;
  AutoCaptureService._internal();

  // ═══════════ Configuration ═══════════
  bool _isEnabled = true;
  int _captureIntervalSeconds = 3;        // Photo toutes les 3s
  int _maxPhotosPerSession = 30;          // Max 30 photos par session
  double _imageQuality = 85;              // Qualité JPEG (0-100)
  
  // ═══════════ État ═══════════
  CaptureState _state = CaptureState.idle;
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  CaptureSession? _currentSession;
  
  Timer? _captureTimer;
  bool _isTakingPhoto = false;
  
  // ═══════════ Statistiques ═══════════
  int _totalSessions = 0;
  int _totalPhotos = 0;
  int _failedCaptures = 0;

  // ═══════════ GETTERS ═══════════
  bool get isEnabled => _isEnabled;
  CaptureState get state => _state;
  bool get isCapturing => _state == CaptureState.capturing;
  bool get isCameraReady => _cameraController?.value.isInitialized ?? false;
  CaptureSession? get currentSession => _currentSession;
  int get captureInterval => _captureIntervalSeconds;
  int get maxPhotos => _maxPhotosPerSession;

  // ═══════════════════════════════════════════════════════
  // INITIALISATION
  // ═══════════════════════════════════════════════════════

  Future<void> init() async {
    debugPrint('📸 AutoCaptureService: Initialisation');
    
    // Charger les préférences
    await _loadPreferences();
    
    // Initialiser les caméras
    try {
      _cameras = await availableCameras();
      debugPrint('📷 ${_cameras!.length} caméra(s) disponible(s)');
      
      if (_cameras!.isEmpty) {
        debugPrint('❌ Aucune caméra disponible');
        return;
      }
      
      // Privilégier caméra arrière
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      
      debugPrint('📷 Caméra sélectionnée: ${backCamera.name}');
      
    } catch (e) {
      debugPrint('❌ Erreur initialisation caméras: $e');
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    _isEnabled = prefs.getBool('auto_capture_enabled') ?? true;
    _captureIntervalSeconds = prefs.getInt('capture_interval') ?? 3;
    _maxPhotosPerSession = prefs.getInt('max_photos_per_session') ?? 30;
    _imageQuality = prefs.getDouble('image_quality') ?? 85;
    
    debugPrint('⚙️  Configuration chargée:');
    debugPrint('   - Activé: $_isEnabled');
    debugPrint('   - Intervalle: ${_captureIntervalSeconds}s');
    debugPrint('   - Max photos: $_maxPhotosPerSession');
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_capture_enabled', _isEnabled);
    await prefs.setInt('capture_interval', _captureIntervalSeconds);
    await prefs.setInt('max_photos_per_session', _maxPhotosPerSession);
    await prefs.setDouble('image_quality', _imageQuality);
  }

  // ═══════════════════════════════════════════════════════
  // GESTION CAMÉRA
  // ═══════════════════════════════════════════════════════

  Future<bool> initializeCamera() async {
    if (_cameras == null || _cameras!.isEmpty) {
      debugPrint('❌ Pas de caméra disponible');
      return false;
    }
    
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }
    
    _setState(CaptureState.initializing);
    
    try {
      // Sélectionner caméra arrière
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      
      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      await _cameraController!.initialize();
      
      // Configurer flash auto
      await _cameraController!.setFlashMode(FlashMode.auto);
      
      _setState(CaptureState.ready);
      debugPrint('✅ Caméra initialisée');
      
      return true;
    } catch (e) {
      debugPrint('❌ Erreur initialisation caméra: $e');
      _setState(CaptureState.idle);
      return false;
    }
  }

  Future<void> disposeCamera() async {
    await _cameraController?.dispose();
    _cameraController = null;
    _setState(CaptureState.idle);
    debugPrint('📷 Caméra libérée');
  }

  // ═══════════════════════════════════════════════════════
  // SESSION DE CAPTURE
  // ═══════════════════════════════════════════════════════

  Future<bool> startCaptureSession() async {
    if (!_isEnabled) {
      debugPrint('⚠️  Capture automatique désactivée');
      return false;
    }
    
    if (_currentSession != null && _currentSession!.isActive) {
      debugPrint('⚠️  Session déjà active');
      return false;
    }
    
    debugPrint('📸 ═══════════════════════════════════');
    debugPrint('📸 DÉMARRAGE SESSION DE CAPTURE');
    debugPrint('📸 ═══════════════════════════════════');
    
    // Initialiser la caméra si nécessaire
    if (!isCameraReady) {
      final success = await initializeCamera();
      if (!success) {
        debugPrint('❌ Impossible d\'initialiser la caméra');
        return false;
      }
    }
    
    // Créer nouvelle session
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentSession = CaptureSession(
      sessionId: sessionId,
      startTime: DateTime.now(),
      photos: [],
    );
    
    _setState(CaptureState.capturing);
    _totalSessions++;
    
    // Démarrer timer de capture périodique
    _startCaptureTimer();
    
    // Prendre première photo immédiatement
    await _takePhoto();
    
    debugPrint('✅ Session démarrée: $sessionId');
    return true;
  }

  void _startCaptureTimer() {
    _captureTimer?.cancel();
    
    _captureTimer = Timer.periodic(
      Duration(seconds: _captureIntervalSeconds),
      (timer) async {
        if (_currentSession == null || !_currentSession!.isActive) {
          timer.cancel();
          return;
        }
        
        if (_currentSession!.photoCount >= _maxPhotosPerSession) {
          debugPrint('⚠️  Limite de photos atteinte ($_maxPhotosPerSession)');
          await stopCaptureSession();
          return;
        }
        
        await _takePhoto();
      },
    );
  }

  Future<void> _takePhoto() async {
    if (_isTakingPhoto || _cameraController == null) return;
    
    if (!_cameraController!.value.isInitialized) {
      debugPrint('⚠️  Caméra non initialisée');
      return;
    }
    
    _isTakingPhoto = true;
    
    try {
      // Prendre la photo
      final XFile photo = await _cameraController!.takePicture();
      
      // Sauvegarder dans répertoire temporaire
      final directory = await getTemporaryDirectory();
      final sessionDir = Directory('${directory.path}/capture_${_currentSession!.sessionId}');
      
      if (!await sessionDir.exists()) {
        await sessionDir.create(recursive: true);
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '${sessionDir.path}/photo_$timestamp.jpg';
      
      final File savedPhoto = await File(photo.path).copy(newPath);
      
      // Ajouter à la session
      _currentSession!.photos.add(savedPhoto);
      _totalPhotos++;
      
      final photoNum = _currentSession!.photoCount;
      debugPrint('📸 Photo $photoNum/$_maxPhotosPerSession capturée: ${savedPhoto.path}');
      
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ Erreur capture photo: $e');
      _failedCaptures++;
    } finally {
      _isTakingPhoto = false;
    }
  }

  Future<List<File>> stopCaptureSession() async {
    if (_currentSession == null) {
      debugPrint('⚠️  Aucune session active');
      return [];
    }
    
    debugPrint('📸 ═══════════════════════════════════');
    debugPrint('📸 ARRÊT SESSION DE CAPTURE');
    debugPrint('📸 ═══════════════════════════════════');
    
    _captureTimer?.cancel();
    _captureTimer = null;
    
    _currentSession!.endTime = DateTime.now();
    
    final photos = List<File>.from(_currentSession!.photos);
    final duration = _currentSession!.duration;
    final photoCount = photos.length;
    
    debugPrint('📊 Session terminée:');
    debugPrint('   - Photos: $photoCount');
    debugPrint('   - Durée: ${duration.inSeconds}s');
    debugPrint('   - Intervalle: ${_captureIntervalSeconds}s');
    
    _setState(CaptureState.ready);
    
    // Garder référence session pour stats
    final completedSession = _currentSession;
    _currentSession = null;
    
    notifyListeners();
    
    return photos;
  }

  // ═══════════════════════════════════════════════════════
  // NETTOYAGE
  // ═══════════════════════════════════════════════════════

  Future<void> cleanupSessionFiles(String sessionId) async {
    try {
      final directory = await getTemporaryDirectory();
      final sessionDir = Directory('${directory.path}/capture_$sessionId');
      
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
        debugPrint('🗑️  Fichiers session supprimés: $sessionId');
      }
    } catch (e) {
      debugPrint('❌ Erreur nettoyage: $e');
    }
  }

  Future<void> cleanupAllSessions() async {
    try {
      final directory = await getTemporaryDirectory();
      final contents = directory.listSync();
      
      int cleaned = 0;
      for (var entity in contents) {
        if (entity is Directory && entity.path.contains('capture_')) {
          await entity.delete(recursive: true);
          cleaned++;
        }
      }
      
      debugPrint('🗑️  $cleaned session(s) nettoyée(s)');
    } catch (e) {
      debugPrint('❌ Erreur nettoyage: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    await _savePreferences();
    debugPrint('⚙️  Auto-capture: ${enabled ? "activé" : "désactivé"}');
    notifyListeners();
  }

  Future<void> setCaptureInterval(int seconds) async {
    if (seconds < 1 || seconds > 10) {
      debugPrint('⚠️  Intervalle invalide: $seconds (1-10s autorisé)');
      return;
    }
    
    _captureIntervalSeconds = seconds;
    await _savePreferences();
    debugPrint('⚙️  Intervalle: ${seconds}s');
    notifyListeners();
  }

  Future<void> setMaxPhotos(int max) async {
    if (max < 5 || max > 50) {
      debugPrint('⚠️  Max photos invalide: $max (5-50 autorisé)');
      return;
    }
    
    _maxPhotosPerSession = max;
    await _savePreferences();
    debugPrint('⚙️  Max photos: $max');
    notifyListeners();
  }

  Future<void> setImageQuality(double quality) async {
    if (quality < 50 || quality > 100) {
      debugPrint('⚠️  Qualité invalide: $quality (50-100 autorisé)');
      return;
    }
    
    _imageQuality = quality;
    await _savePreferences();
    debugPrint('⚙️  Qualité: $quality%');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  // CAPTURE MANUELLE
  // ═══════════════════════════════════════════════════════

  Future<File?> takeManualPhoto() async {
    if (_cameraController == null || !isCameraReady) {
      debugPrint('⚠️  Caméra non prête');
      return null;
    }
    
    try {
      final XFile photo = await _cameraController!.takePicture();
      
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '${directory.path}/manual_$timestamp.jpg';
      
      final File savedPhoto = await File(photo.path).copy(newPath);
      
      debugPrint('📸 Photo manuelle: ${savedPhoto.path}');
      
      return savedPhoto;
    } catch (e) {
      debugPrint('❌ Erreur photo manuelle: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════
  // STATISTIQUES
  // ═══════════════════════════════════════════════════════

  Map<String, dynamic> getStats() {
    return {
      'is_enabled': _isEnabled,
      'state': _state.toString().split('.').last,
      'is_capturing': isCapturing,
      'is_camera_ready': isCameraReady,
      'capture_interval_seconds': _captureIntervalSeconds,
      'max_photos_per_session': _maxPhotosPerSession,
      'image_quality': _imageQuality,
      'current_session': _currentSession != null ? {
        'session_id': _currentSession!.sessionId,
        'start_time': _currentSession!.startTime.toIso8601String(),
        'photo_count': _currentSession!.photoCount,
        'duration_seconds': _currentSession!.duration.inSeconds,
        'is_active': _currentSession!.isActive,
      } : null,
      'total_sessions': _totalSessions,
      'total_photos': _totalPhotos,
      'failed_captures': _failedCaptures,
      'success_rate': _totalPhotos > 0
          ? ((_totalPhotos - _failedCaptures) / _totalPhotos * 100).toStringAsFixed(1)
          : '0.0',
    };
  }

  void printStats() {
    final stats = getStats();
    debugPrint('📸 ═══════════════════════════════════');
    debugPrint('📸 AUTO-CAPTURE SERVICE STATS');
    debugPrint('📸 ═══════════════════════════════════');
    debugPrint('   Activé: ${stats['is_enabled']}');
    debugPrint('   État: ${stats['state']}');
    debugPrint('   Caméra prête: ${stats['is_camera_ready']}');
    debugPrint('   Sessions: ${stats['total_sessions']}');
    debugPrint('   Photos: ${stats['total_photos']}');
    debugPrint('   Échecs: ${stats['failed_captures']}');
    debugPrint('   Taux succès: ${stats['success_rate']}%');
    if (stats['current_session'] != null) {
      final session = stats['current_session'] as Map;
      debugPrint('   Session active:');
      debugPrint('     - Photos: ${session['photo_count']}');
      debugPrint('     - Durée: ${session['duration_seconds']}s');
    }
    debugPrint('📸 ═══════════════════════════════════');
  }

  // ═══════════════════════════════════════════════════════
  // MÉTHODES UTILITAIRES
  // ═══════════════════════════════════════════════════════

  void _setState(CaptureState newState) {
    if (_state != newState) {
      _state = newState;
      debugPrint('📸 État: ${newState.toString().split('.').last}');
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════

  @override
  void dispose() {
    _captureTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }
}