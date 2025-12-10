import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════════
/// Service Bluetooth avec debug amélioré
/// ═══════════════════════════════════════════════════════════

enum FridgeEvent {
  ready,
  opening,
  open,
  stillOpen,
  closing,
  closed,
  config,
  heartbeat,
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

  // ═══════════ État ═══════════
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
  DateTime? _lastHeartbeat;
  int _totalSessions = 0;
  int _totalPhotos = 0;

  // Reconnexion
  Timer? _reconnectionTimer;
  int _reconnectionAttempts = 0;
  static const int MAX_RECONNECTION_ATTEMPTS = 5;

  // 🆕 Compteur de messages reçus pour vérifier la connexion
  int _messagesReceived = 0;
  DateTime? _lastMessageTime;

  // ═══════════ GETTERS ═══════════
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get currentState => _currentState;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  int get referenceDistance => _referenceDistance;
  bool get isSessionActive => _sessionStartTime != null;
  int get sessionPhotoCount => _sessionPhotoCount;
  int get messagesReceived => _messagesReceived;
  DateTime? get lastMessageTime => _lastMessageTime;

  Duration? get sessionDuration => _sessionStartTime != null
      ? DateTime.now().difference(_sessionStartTime!)
      : null;

  // ═══════════════════════════════════════════════════════
  // INIT
  // ═══════════════════════════════════════════════════════

  Future<void> init() async {
    debugPrint('🔷 BluetoothFridgeService: Initialisation');

    bool? isEnabled = await _bluetooth.isEnabled;
    if (isEnabled == false) {
      debugPrint('⚠️  Bluetooth désactivé');
      return;
    }

    await _loadSavedDevice();

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
  // 🆕 DÉCONNEXION FORCÉE ET COMPLÈTE
  // ═══════════════════════════════════════════════════════

  Future<void> forceDisconnect() async {
    debugPrint('🔌 ═══════════════════════════════════');
    debugPrint('🔌 DÉCONNEXION FORCÉE');
    debugPrint('🔌 ═══════════════════════════════════');

    // Annuler tous les timers
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;

    // Fermer le stream de données
    if (_dataSubscription != null) {
      debugPrint('📡 Fermeture du stream de données...');
      await _dataSubscription?.cancel();
      _dataSubscription = null;
    }

    // Fermer la connexion Bluetooth
    if (_connection != null) {
      debugPrint('📡 Fermeture de la connexion Bluetooth...');
      try {
        await _connection?.close();
        await _connection?.finish();
      } catch (e) {
        debugPrint('⚠️  Erreur lors de la fermeture: $e');
      }
      _connection = null;
    }

    // Reset de tous les états
    _isConnected = false;
    _isConnecting = false;
    _connectedDevice = null;
    _currentState = 'IDLE';
    _messagesReceived = 0;
    _lastMessageTime = null;
    _lastHeartbeat = null;
    _sessionStartTime = null;
    _sessionPhotoCount = 0;

    debugPrint('✅ Déconnexion complète');
    notifyListeners();

    // Petit délai pour s'assurer que tout est libéré
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ═══════════════════════════════════════════════════════
  // CONNEXION AMÉLIORÉE
  // ═══════════════════════════════════════════════════════

  Future<bool> connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) {
      debugPrint('⚠️  Connexion déjà en cours');
      return false;
    }

    debugPrint('🔗 ═══════════════════════════════════');
    debugPrint('🔗 CONNEXION À: ${device.name ?? device.address}');
    debugPrint('🔗 Adresse: ${device.address}');
    debugPrint('🔗 ═══════════════════════════════════');

    _isConnecting = true;
    notifyListeners();

    try {
      // 1️⃣ DÉCONNEXION FORCÉE de tout appareil existant
      await forceDisconnect();

      debugPrint('📡 Établissement de la connexion...');

      // 2️⃣ NOUVELLE CONNEXION
      _connection = await BluetoothConnection.toAddress(device.address);

      if (_connection == null || !_connection!.isConnected) {
        throw Exception('Connexion échouée');
      }

      debugPrint('✅ Connexion Bluetooth établie');

      // 3️⃣ MISE À JOUR DES ÉTATS
      _connectedDevice = device;
      _isConnected = true;
      _isConnecting = false;
      _reconnectionAttempts = 0;
      _messagesReceived = 0;

      await _saveDevice(device);

      // 4️⃣ ÉCOUTE DES DONNÉES
      _listenToData();

      // 5️⃣ TEST DE LA CONNEXION
      debugPrint('📤 Envoi de commandes de test...');
      await _sendCommand('PING');
      await Future.delayed(const Duration(milliseconds: 500));
      await _sendCommand('STATUS');

      // 6️⃣ ATTENDRE UNE RÉPONSE (timeout 3s)
      debugPrint('⏳ Attente de réponse Arduino...');
      final responseReceived = await _waitForResponse(
        timeout: const Duration(seconds: 3),
      );

      if (responseReceived) {
        debugPrint('✅ ═══════════════════════════════════');
        debugPrint('✅ CONNEXION RÉUSSIE');
        debugPrint('✅ Device: ${device.name}');
        debugPrint('✅ Messages reçus: $_messagesReceived');
        debugPrint('✅ ═══════════════════════════════════');
        notifyListeners();
        return true;
      } else {
        debugPrint('⚠️  Aucune réponse de l\'Arduino');
        debugPrint('⚠️  Vérifiez que le HC-05 est bien connecté à l\'Arduino');
        await forceDisconnect();
        return false;
      }
    } catch (e) {
      debugPrint('❌ ═══════════════════════════════════');
      debugPrint('❌ ERREUR CONNEXION: $e');
      debugPrint('❌ ═══════════════════════════════════');

      _isConnected = false;
      _isConnecting = false;
      notifyListeners();

      await forceDisconnect();

      return false;
    }
  }

  // 🆕 Attendre une réponse de l'Arduino
  Future<bool> _waitForResponse({required Duration timeout}) async {
    final startCount = _messagesReceived;
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < timeout) {
      if (_messagesReceived > startCount) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return false;
  }

  // ═══════════════════════════════════════════════════════
  // ÉCOUTE DES DONNÉES
  // ═══════════════════════════════════════════════════════

  void _listenToData() {
    if (_connection == null) return;

    debugPrint('👂 Démarrage de l\'écoute des données...');

    _dataSubscription = _connection!.input!.listen(
      _handleIncomingData,
      onDone: () {
        debugPrint('📡 Stream fermé (onDone)');
        _handleDisconnection();
      },
      onError: (error) {
        debugPrint('❌ Erreur stream: $error');
        _handleDisconnection();
      },
    );

    debugPrint('✅ Écoute activée');
  }

  // ═══════════════════════════════════════════════════════
  // TRAITEMENT DES DONNÉES
  // ═══════════════════════════════════════════════════════

  String _buffer = '';

  void _handleIncomingData(Uint8List data) {
    String message = utf8.decode(data);
    _buffer += message;

    _messagesReceived++;
    _lastMessageTime = DateTime.now();

    // Traiter les lignes complètes
    while (_buffer.contains('\n')) {
      int index = _buffer.indexOf('\n');
      String line = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);

      if (line.isNotEmpty) {
        debugPrint('📥 Arduino: $line'); // 🆕 Log chaque message
        _processMessage(line);
      }
    }
  }

  void _processMessage(String message) {
    // Heartbeat
    if (message == 'HEARTBEAT' || message == 'PONG') {
      _lastHeartbeat = DateTime.now();
      debugPrint('💓 Heartbeat reçu');
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

    List<String> parts = eventStr.split(':');
    String eventName = parts[0];

    debugPrint('📨 Événement: $eventName');

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
      debugPrint('📤 Envoyé: $command');
    } catch (e) {
      debugPrint('❌ Erreur envoi: $e');
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
    debugPrint('🔌 Déconnexion demandée par l\'utilisateur');
    _autoReconnect = false;
    await forceDisconnect();
  }

  void _handleDisconnection() {
    debugPrint('⚠️  Connexion perdue');

    _isConnected = false;
    _connection = null;
    _currentState = 'IDLE';

    notifyListeners();

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
  // SCAN
  // ═══════════════════════════════════════════════════════

  Future<List<BluetoothDevice>> getAvailableDevices() async {
    try {
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
  // STATS
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
      'messages_received': _messagesReceived,
      'last_message': _lastMessageTime?.toIso8601String(),
    };
  }

  void printStats() {
    final stats = getStats();
    debugPrint('📊 ═══════════════════════════════════');
    debugPrint('📊 BLUETOOTH SERVICE STATS');
    debugPrint('📊 ═══════════════════════════════════');
    debugPrint('   Connecté: ${stats['is_connected']}');
    debugPrint('   Device: ${stats['device_name']}');
    debugPrint('   Adresse: ${stats['device_address']}');
    debugPrint('   État: ${stats['current_state']}');
    debugPrint('   Messages reçus: ${stats['messages_received']}');
    debugPrint('   Dernier message: ${stats['last_message'] ?? "Jamais"}');
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
