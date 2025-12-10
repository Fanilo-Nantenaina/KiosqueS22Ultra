import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════════
/// Service de gestion Bluetooth avec l'Arduino
/// Gère la connexion, les événements, et la communication
/// ═══════════════════════════════════════════════════════════

enum FridgeEvent {
  ready, // Arduino prêt
  opening, // Détection ouverture
  open, // Ouverture confirmée → START CAPTURE
  stillOpen, // Heartbeat pendant ouverture
  closing, // Détection fermeture
  closed, // Fermeture confirmée → STOP & UPLOAD
  config, // Configuration reçue
  heartbeat, // Heartbeat normal
}

class FridgeEventData {
  final FridgeEvent event;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  FridgeEventData(this.event, {this.data}) : timestamp = DateTime.now();
}

class BluetoothFridgeService extends ChangeNotifier {
  static final BluetoothFridgeService _instance =
      BluetoothFridgeService._internal();

  factory BluetoothFridgeService() => _instance;
  BluetoothFridgeService._internal();

  // ═══════════ État de la connexion ═══════════
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothConnection? _connection;
  BluetoothDevice? _connectedDevice;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _autoReconnect = true;

  // ═══════════ Streams ═══════════
  StreamSubscription<Uint8List>? _dataSubscription;
  final StreamController<FridgeEventData> _eventController =
      StreamController<FridgeEventData>.broadcast();

  Stream<FridgeEventData> get eventStream => _eventController.stream;

  // ═══════════ État du frigo ═══════════
  String _currentState = 'IDLE';
  int _referenceDistance = 0;
  DateTime? _sessionStartTime;
  int _sessionPhotoCount = 0;

  // ═══════════ Statistiques ═══════════
  DateTime? _lastHeartbeat;
  int _totalSessions = 0;
  int _totalPhotos = 0;

  // Reconnexion automatique
  Timer? _reconnectionTimer;
  int _reconnectionAttempts = 0;
  static const int MAX_RECONNECTION_ATTEMPTS = 5;

  // ═══════════ GETTERS ═══════════
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get currentState => _currentState;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  int get referenceDistance => _referenceDistance;
  bool get isSessionActive => _sessionStartTime != null;
  int get sessionPhotoCount => _sessionPhotoCount;
  Duration? get sessionDuration => _sessionStartTime != null
      ? DateTime.now().difference(_sessionStartTime!)
      : null;

  // ═══════════════════════════════════════════════════════
  // INITIALISATION
  // ═══════════════════════════════════════════════════════

  Future<void> init() async {
    debugPrint('🔷 BluetoothFridgeService: Initialisation');

    // Vérifier si Bluetooth activé
    bool? isEnabled = await _bluetooth.isEnabled;
    if (isEnabled == false) {
      debugPrint('⚠️  Bluetooth désactivé');
      return;
    }

    // Charger le dernier device connecté
    await _loadSavedDevice();

    // Tenter reconnexion automatique
    if (_autoReconnect && _connectedDevice != null) {
      await connectToDevice(_connectedDevice!);
    }
  }

  Future<void> _loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAddress = prefs.getString('last_bluetooth_device');

    if (savedAddress != null) {
      final devices = await _bluetooth.getBondedDevices();
      _connectedDevice = devices.firstWhere(
        (d) => d.address == savedAddress,
        orElse: () => devices.first,
      );

      debugPrint('📱 Device sauvegardé: ${_connectedDevice?.name}');
    }
  }

  Future<void> _saveDevice(BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_bluetooth_device', device.address);
  }

  // ═══════════════════════════════════════════════════════
  // SCAN & PAIRING
  // ═══════════════════════════════════════════════════════

  Future<List<BluetoothDevice>> getAvailableDevices() async {
    try {
      // Appareils déjà appairés
      final bondedDevices = await _bluetooth.getBondedDevices();

      debugPrint('📱 ${bondedDevices.length} devices appairés');
      for (var device in bondedDevices) {
        debugPrint('  - ${device.name} (${device.address})');
      }

      return bondedDevices;
    } catch (e) {
      debugPrint('❌ Erreur scan: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════
  // CONNEXION
  // ═══════════════════════════════════════════════════════

  Future<bool> connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) {
      debugPrint('⚠️  Connexion déjà en cours');
      return false;
    }

    _isConnecting = true;
    notifyListeners();

    try {
      debugPrint('🔗 Connexion à ${device.name}...');

      // Fermer connexion existante
      await disconnect();

      // Nouvelle connexion
      _connection = await BluetoothConnection.toAddress(device.address);
      _connectedDevice = device;
      _isConnected = true;
      _isConnecting = false;
      _reconnectionAttempts = 0;

      await _saveDevice(device);

      // Écouter les données
      _listenToData();

      // Ping initial
      await _sendCommand('PING');
      await _sendCommand('STATUS');

      debugPrint('✅ Connecté à ${device.name}');
      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('❌ Erreur connexion: $e');
      _isConnected = false;
      _isConnecting = false;
      notifyListeners();

      // Tenter reconnexion
      _scheduleReconnection();

      return false;
    }
  }

  void _listenToData() {
    if (_connection == null) return;

    _dataSubscription = _connection!.input!.listen(
      _handleIncomingData,
      onDone: _handleDisconnection,
      onError: (error) {
        debugPrint('❌ Erreur stream: $error');
        _handleDisconnection();
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // TRAITEMENT DES DONNÉES
  // ═══════════════════════════════════════════════════════

  String _buffer = '';

  void _handleIncomingData(Uint8List data) {
    String message = utf8.decode(data);
    _buffer += message;

    // Traiter les lignes complètes
    while (_buffer.contains('\n')) {
      int index = _buffer.indexOf('\n');
      String line = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);

      if (line.isNotEmpty) {
        _processMessage(line);
      }
    }
  }

  void _processMessage(String message) {
    debugPrint('📥 Arduino: $message');

    // Heartbeat simple
    if (message == 'HEARTBEAT' || message == 'PONG') {
      _lastHeartbeat = DateTime.now();
      return;
    }

    // Événements
    if (message.startsWith('EVENT:')) {
      _handleEvent(message.substring(6));
    }
    // Configuration
    else if (message.startsWith('CONFIG:')) {
      _handleConfig(message.substring(7));
    }
  }

  void _handleEvent(String eventStr) {
    FridgeEvent? event;
    Map<String, dynamic>? data;

    // Parser l'événement
    List<String> parts = eventStr.split(':');
    String eventName = parts[0];

    switch (eventName) {
      case 'READY':
        event = FridgeEvent.ready;
        _currentState = 'IDLE';
        break;

      case 'OPENING':
        event = FridgeEvent.opening;
        _currentState = 'OPENING';
        break;

      case 'OPEN':
        event = FridgeEvent.open;
        _currentState = 'OPEN';
        _sessionStartTime = DateTime.now();
        _sessionPhotoCount = 0;
        debugPrint('📸 SESSION DÉMARRÉE');
        break;

      case 'STILL_OPEN':
        event = FridgeEvent.stillOpen;
        break;

      case 'CLOSING':
        event = FridgeEvent.closing;
        _currentState = 'CLOSING';
        break;

      case 'CLOSED':
        event = FridgeEvent.closed;
        _currentState = 'CLOSED';

        // Parser les stats: CLOSED:photoCount:duration
        if (parts.length >= 3) {
          data = {
            'photo_count': int.tryParse(parts[1]) ?? 0,
            'duration_seconds': int.tryParse(parts[2]) ?? 0,
          };

          _totalSessions++;
          _totalPhotos += data['photo_count'] as int;

          debugPrint(
            '📊 Session terminée: ${data['photo_count']} photos, ${data['duration_seconds']}s',
          );
        }

        _sessionStartTime = null;
        _sessionPhotoCount = 0;
        _currentState = 'IDLE';
        break;
    }

    if (event != null) {
      _eventController.add(FridgeEventData(event, data: data));
      notifyListeners();
    }
  }

  void _handleConfig(String configStr) {
    // CONFIG:distance
    try {
      _referenceDistance = int.parse(configStr);
      debugPrint('⚙️  Distance référence: $_referenceDistance cm');

      _eventController.add(
        FridgeEventData(
          FridgeEvent.config,
          data: {'reference_distance': _referenceDistance},
        ),
      );

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Erreur parsing config: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // COMMANDES
  // ═══════════════════════════════════════════════════════

  Future<void> _sendCommand(String command) async {
    if (_connection == null || !_isConnected) {
      debugPrint('⚠️  Pas de connexion pour envoyer: $command');
      return;
    }

    try {
      _connection!.output.add(utf8.encode('$command\n'));
      await _connection!.output.allSent;
      debugPrint('📤 Commande envoyée: $command');
    } catch (e) {
      debugPrint('❌ Erreur envoi commande: $e');
    }
  }

  Future<void> requestStatus() async {
    await _sendCommand('STATUS');
  }

  Future<void> requestRecalibration() async {
    debugPrint('🔧 Demande de recalibration');
    await _sendCommand('RECALIBRATE');
  }

  Future<void> notifyPhotoTaken() async {
    _sessionPhotoCount++;
    await _sendCommand('PHOTO_OK');
    notifyListeners();
  }

  Future<void> ping() async {
    await _sendCommand('PING');
  }

  // ═══════════════════════════════════════════════════════
  // DÉCONNEXION
  // ═══════════════════════════════════════════════════════

  Future<void> disconnect() async {
    if (_connection == null) return;

    debugPrint('🔌 Déconnexion Bluetooth');

    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _autoReconnect = false;

    await _dataSubscription?.cancel();
    _dataSubscription = null;

    await _connection?.close();
    _connection = null;

    _isConnected = false;
    _connectedDevice = null;
    _currentState = 'IDLE';

    debugPrint('✅ Déconnecté');
    notifyListeners();
  }

  void _handleDisconnection() {
    debugPrint('⚠️  Connexion perdue');

    _isConnected = false;
    _connection = null;
    _currentState = 'IDLE';

    notifyListeners();

    // Tenter reconnexion automatique
    if (_autoReconnect && _connectedDevice != null) {
      _scheduleReconnection();
    }
  }

  void _scheduleReconnection() {
    if (_reconnectionAttempts >= MAX_RECONNECTION_ATTEMPTS) {
      debugPrint('❌ Nombre max de tentatives atteint');
      return;
    }

    _reconnectionAttempts++;
    final delay = Duration(seconds: 5 * _reconnectionAttempts);

    debugPrint(
      '🔄 Reconnexion dans ${delay.inSeconds}s (tentative $_reconnectionAttempts/$MAX_RECONNECTION_ATTEMPTS)',
    );

    _reconnectionTimer?.cancel();
    _reconnectionTimer = Timer(delay, () async {
      if (_connectedDevice != null && !_isConnected) {
        debugPrint('🔄 Tentative de reconnexion...');
        await connectToDevice(_connectedDevice!);
      }
    });
  }

  // ═══════════════════════════════════════════════════════
  // STATISTIQUES
  // ═══════════════════════════════════════════════════════

  Map<String, dynamic> getStats() {
    return {
      'is_connected': _isConnected,
      'device_name': _connectedDevice?.name ?? 'Aucun',
      'device_address': _connectedDevice?.address ?? '-',
      'current_state': _currentState,
      'reference_distance': _referenceDistance,
      'last_heartbeat': _lastHeartbeat?.toIso8601String(),
      'session_active': _sessionStartTime != null,
      'session_photo_count': _sessionPhotoCount,
      'session_duration_seconds': sessionDuration?.inSeconds ?? 0,
      'total_sessions': _totalSessions,
      'total_photos': _totalPhotos,
      'reconnection_attempts': _reconnectionAttempts,
    };
  }

  void printStats() {
    final stats = getStats();
    debugPrint('📊 ═══════════════════════════════════');
    debugPrint('📊 BLUETOOTH SERVICE STATS');
    debugPrint('📊 ═══════════════════════════════════');
    debugPrint('   Connecté: ${stats['is_connected']}');
    debugPrint('   Device: ${stats['device_name']}');
    debugPrint('   État: ${stats['current_state']}');
    debugPrint('   Sessions: ${stats['total_sessions']}');
    debugPrint('   Photos: ${stats['total_photos']}');
    debugPrint('📊 ═══════════════════════════════════');
  }

  @override
  void dispose() {
    _reconnectionTimer?.cancel();
    _dataSubscription?.cancel();
    _connection?.close();
    _eventController.close();
    super.dispose();
  }
}
