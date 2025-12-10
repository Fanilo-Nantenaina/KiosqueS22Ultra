import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:kiosque_samsung_ultra/screen/bluetooth_debug.dart';
import 'package:kiosque_samsung_ultra/service/bluetooth_fridge_service.dart';
import 'package:kiosque_samsung_ultra/service/auto_capture_service.dart';
import 'package:provider/provider.dart';
import 'dart:async';

/// ═══════════════════════════════════════════════════════════
/// Page de configuration Bluetooth et Auto-Capture
/// Permet de connecter l'Arduino et configurer la capture auto
/// ═══════════════════════════════════════════════════════════

class BluetoothSetupPage extends StatefulWidget {
  const BluetoothSetupPage({super.key});

  @override
  State<BluetoothSetupPage> createState() => _BluetoothSetupPageState();
}

class _BluetoothSetupPageState extends State<BluetoothSetupPage>
    with SingleTickerProviderStateMixin {
  List<BluetoothDevice> _bondedDevices = [];
  List<BluetoothDiscoveryResult> _discoveredDevices = [];
  bool _isScanning = false;
  bool _bluetoothEnabled = false;
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySubscription;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkBluetoothState();
    _loadDevices();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _discoverySubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkBluetoothState() async {
    try {
      final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      setState(() {
        _bluetoothEnabled = isEnabled ?? false;
      });
    } catch (e) {
      debugPrint('Erreur vérification Bluetooth: $e');
    }
  }

  Future<void> _loadDevices() async {
    setState(() => _isScanning = true);

    try {
      // 1. Charger les devices appairés
      final bluetoothService = context.read<BluetoothFridgeService>();
      final bonded = await bluetoothService.getAvailableDevices();

      setState(() {
        _bondedDevices = bonded;
      });

      debugPrint('📱 ${bonded.length} devices appairés');

      // 2. Lancer le scan pour découvrir de nouveaux appareils
      await _startDiscovery();
    } catch (e) {
      setState(() => _isScanning = false);
      _showError('Erreur chargement: $e');
    }
  }

  /// 🆕 SCAN POUR DÉCOUVRIR DE NOUVEAUX PÉRIPHÉRIQUES
  Future<void> _startDiscovery() async {
    // Annuler le scan précédent
    await _discoverySubscription?.cancel();

    setState(() {
      _discoveredDevices.clear();
      _isScanning = true;
    });

    debugPrint('🔍 Démarrage du scan Bluetooth...');

    try {
      _discoverySubscription = FlutterBluetoothSerial.instance
          .startDiscovery()
          .listen((result) {
            debugPrint(
              '🔵 Découvert: ${result.device.name ?? "Unknown"} (${result.device.address})',
            );

            setState(() {
              // Éviter les doublons
              final existingIndex = _discoveredDevices.indexWhere(
                (r) => r.device.address == result.device.address,
              );

              if (existingIndex >= 0) {
                _discoveredDevices[existingIndex] = result;
              } else {
                _discoveredDevices.add(result);
              }
            });
          });

      // Arrêter le scan après 12 secondes
      Future.delayed(const Duration(seconds: 12), () {
        _stopDiscovery();
      });
    } catch (e) {
      debugPrint('❌ Erreur scan: $e');
      setState(() => _isScanning = false);
      _showError('Erreur scan: $e');
    }
  }

  void _stopDiscovery() {
    _discoverySubscription?.cancel();
    setState(() => _isScanning = false);
    debugPrint('🛑 Scan terminé');
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _showLoading('Connexion à ${device.name ?? device.address}...');

    try {
      final bluetoothService = context.read<BluetoothFridgeService>();

      // Vérifier si c'est un appareil compatible (HC-05, HC-06, etc.)
      if (!_isCompatibleDevice(device)) {
        Navigator.pop(context);
        _showWarning(
          'Cet appareil ne semble pas être un module HC-05/HC-06.\n'
          'Êtes-vous sûr de vouloir continuer ?',
          onConfirm: () async {
            _showLoading('Tentative de connexion...');
            await _attemptConnection(bluetoothService, device);
          },
        );
        return;
      }

      await _attemptConnection(bluetoothService, device);
    } catch (e) {
      Navigator.pop(context);
      _showError('Échec connexion: $e');
    }
  }

  /// Vérifie si l'appareil semble être un module Bluetooth compatible
  bool _isCompatibleDevice(BluetoothDevice device) {
    final name = (device.name ?? '').toUpperCase();
    return name.contains('HC-') ||
        name.contains('ARDUINO') ||
        name.contains('BT') ||
        name == 'HC-05' ||
        name == 'HC-06' ||
        name.isEmpty; // HC-05 non configuré
  }

  Future<void> _attemptConnection(
    BluetoothFridgeService bluetoothService,
    BluetoothDevice device,
  ) async {
    try {
      final success = await bluetoothService.connectToDevice(device);

      if (mounted) {
        Navigator.pop(context); // Fermer loading

        if (success) {
          _showSuccess('Connecté à ${device.name ?? device.address}');
        } else {
          _showError(
            'Impossible de se connecter.\n'
            'Vérifiez que l\'Arduino est allumé et à proximité.',
          );
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        Navigator.pop(context);

        // Erreurs spécifiques
        if (e.toString().contains('read failed')) {
          _showError(
            'Connexion refusée par l\'appareil.\n'
            'Cet appareil n\'accepte peut-être pas les connexions Serial.',
          );
        } else if (e.toString().contains('timeout')) {
          _showError(
            'Timeout de connexion.\n'
            'Assurez-vous que l\'appareil est allumé et à portée.',
          );
        } else {
          _showError('Erreur de connexion: $e');
        }
      }
    }
  }

  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showWarning(String message, {VoidCallback? onConfirm}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Attention'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm?.call();
            },
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Configuration Auto-Capture'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: 'Bluetooth'),
            Tab(icon: Icon(Icons.settings), text: 'Paramètres'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildBluetoothTab(isDark), _buildSettingsTab(isDark)],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 1: BLUETOOTH
  // ═══════════════════════════════════════════════════════

  Widget _buildBluetoothTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // État Bluetooth
          _buildBluetoothStatusCard(isDark),

          const SizedBox(height: 24),

          // État connexion
          _buildConnectionStatusCard(isDark),

          const SizedBox(height: 24),

          // 🆕 PANNEAU DE DEBUG (AJOUTÉ ICI)
          Consumer<BluetoothFridgeService>(
            builder: (context, bluetoothService, _) {
              return BluetoothDebugPanel(bluetoothService: bluetoothService);
            },
          ),

          const SizedBox(height: 24),

          // Liste des devices
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Appareils Bluetooth',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  if (_isScanning)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    onPressed: _isScanning ? _stopDiscovery : _loadDevices,
                    icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
                    color: _isScanning ? Colors.red : Colors.blue,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Appareils appairés
          if (_bondedDevices.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.link, size: 16, color: Color(0xFF3B82F6)),
                const SizedBox(width: 8),
                Text(
                  'Appairés (${_bondedDevices.length})',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._bondedDevices.map(
              (device) => _buildDeviceCard(device, isDark, isBonded: true),
            ),
            const SizedBox(height: 16),
          ],

          // Appareils découverts
          if (_discoveredDevices.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.bluetooth_searching,
                  size: 16,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(width: 8),
                Text(
                  'Découverts (${_discoveredDevices.length})',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._discoveredDevices.map(
              (result) => _buildDeviceCard(
                result.device,
                isDark,
                isBonded: false,
                rssi: result.rssi,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // État vide
          if (!_isScanning &&
              _bondedDevices.isEmpty &&
              _discoveredDevices.isEmpty)
            _buildEmptyDevicesList(isDark),

          const SizedBox(height: 24),

          // Instructions
          _buildInstructionsCard(isDark),
        ],
      ),
    );
  }

  Widget _buildBluetoothStatusCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _bluetoothEnabled
              ? [const Color(0xFF10B981).withOpacity(0.15), Colors.transparent]
              : [const Color(0xFFEF4444).withOpacity(0.15), Colors.transparent],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _bluetoothEnabled
              ? const Color(0xFF10B981).withOpacity(0.3)
              : const Color(0xFFEF4444).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bluetoothEnabled
                  ? const Color(0xFF10B981).withOpacity(0.2)
                  : const Color(0xFFEF4444).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _bluetoothEnabled
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: _bluetoothEnabled
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bluetoothEnabled
                      ? 'Bluetooth activé'
                      : 'Bluetooth désactivé',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _bluetoothEnabled
                      ? 'Prêt à se connecter'
                      : 'Activez le Bluetooth pour continuer',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (!_bluetoothEnabled)
            ElevatedButton(
              onPressed: () async {
                await FlutterBluetoothSerial.instance.requestEnable();
                _checkBluetoothState();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
              ),
              child: const Text('Activer'),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatusCard(bool isDark) {
    return Consumer<BluetoothFridgeService>(
      builder: (context, bluetoothService, _) {
        final isConnected = bluetoothService.isConnected;
        final deviceName = bluetoothService.connectedDevice?.name ?? 'Aucun';
        final referenceDistance = bluetoothService.referenceDistance;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? const Color(0xFF10B981).withOpacity(0.15)
                          : const Color(0xFF64748B).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isConnected ? Icons.check_circle : Icons.cancel,
                      color: isConnected
                          ? const Color(0xFF10B981)
                          : const Color(0xFF64748B),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isConnected ? 'Connecté' : 'Non connecté',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              if (isConnected) ...[
                const SizedBox(height: 16),
                _buildInfoRow('Appareil', deviceName, isDark),
                _buildInfoRow('Distance ref.', '$referenceDistance cm', isDark),
                _buildInfoRow('État', bluetoothService.currentState, isDark),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          bluetoothService.requestRecalibration();
                        },
                        icon: const Icon(
                          Icons.settings_backup_restore,
                          size: 18,
                        ),
                        label: const Text('Recalibrer'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          bluetoothService.disconnect();
                        },
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('Déconnecter'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(
    BluetoothDevice device,
    bool isDark, {
    bool isBonded = false,
    int? rssi,
  }) {
    return Consumer<BluetoothFridgeService>(
      builder: (context, bluetoothService, _) {
        final isConnected =
            bluetoothService.connectedDevice?.address == device.address;
        final isCompatible = _isCompatibleDevice(device);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isConnected ? null : () => _connectToDevice(device),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isConnected
                        ? const Color(0xFF10B981).withOpacity(0.5)
                        : isCompatible
                        ? const Color(0xFF3B82F6).withOpacity(0.3)
                        : (isDark
                              ? const Color(0xFF475569)
                              : const Color(0xFFE2E8F0)),
                    width: isConnected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Icône
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:
                            (isConnected
                                    ? const Color(0xFF10B981)
                                    : isCompatible
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFF64748B))
                                .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isCompatible ? Icons.developer_board : Icons.bluetooth,
                        color: isConnected
                            ? const Color(0xFF10B981)
                            : isCompatible
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF64748B),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  device.name ?? 'HC-05 (non configuré)',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isCompatible)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Compatible',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                device.address,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                              if (rssi != null) ...[
                                const SizedBox(width: 12),
                                Icon(
                                  _getSignalIcon(rssi),
                                  size: 14,
                                  color: _getSignalColor(rssi),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$rssi dBm',
                                  style: TextStyle(
                                    color: _getSignalColor(rssi),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (isConnected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Connecté',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Icon(
                        isBonded ? Icons.link : Icons.add_link,
                        size: 16,
                        color: const Color(0xFF64748B),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getSignalIcon(int rssi) {
    if (rssi >= -50) return Icons.signal_cellular_4_bar;
    if (rssi >= -60) return Icons.signal_cellular_alt_2_bar;
    if (rssi >= -70) return Icons.signal_cellular_alt_1_bar;
    return Icons.signal_cellular_0_bar;
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -50) return const Color(0xFF10B981); // Excellent
    if (rssi >= -60) return const Color(0xFF3B82F6); // Bon
    if (rssi >= -70) return const Color(0xFFF59E0B); // Moyen
    return const Color(0xFFEF4444); // Faible
  }

  Widget _buildEmptyDevicesList(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            _isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
            size: 64,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 16),
          Text(
            _isScanning ? 'Recherche en cours...' : 'Aucun appareil trouvé',
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black54,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isScanning
                ? 'Assurez-vous que l\'Arduino HC-05\nest allumé et visible'
                : 'Appuyez sur ⟳ pour rechercher des appareils',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF3B82F6).withOpacity(0.1),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF3B82F6)),
              const SizedBox(width: 12),
              Text(
                'Instructions',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInstructionStep('1', 'Allumez l\'Arduino avec le module HC-05'),
          _buildInstructionStep(
            '2',
            'L\'application scanne automatiquement les appareils',
          ),
          _buildInstructionStep(
            '3',
            'Sélectionnez le HC-05 dans la liste découverte',
          ),
          _buildInstructionStep('4', 'Le HC-05 va automatiquement se calibrer'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFF59E0B).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.tips_and_updates,
                  color: Color(0xFFF59E0B),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Si le HC-05 n\'apparaît pas, vérifiez qu\'il clignote (mode découverte)',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Color(0xFF3B82F6),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 2: PARAMÈTRES
  // ═══════════════════════════════════════════════════════

  Widget _buildSettingsTab(bool isDark) {
    return Consumer<AutoCaptureService>(
      builder: (context, captureService, _) {
        final isEnabled = captureService.isEnabled;
        final captureInterval = captureService.captureInterval;
        final maxPhotos = captureService.maxPhotos;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Toggle principal
              _buildSettingCard(
                isDark,
                title: 'Capture automatique',
                subtitle: 'Déclencher la caméra à l\'ouverture du frigo',
                trailing: Switch(
                  value: isEnabled,
                  onChanged: (value) {
                    captureService.setEnabled(value);
                  },
                  activeColor: const Color(0xFF10B981),
                ),
              ),

              const SizedBox(height: 16),

              // Intervalle de capture
              _buildSettingCard(
                isDark,
                title: 'Intervalle de capture',
                subtitle: 'Temps entre chaque photo',
                trailing: DropdownButton<int>(
                  value: captureInterval,
                  items: [1, 2, 3, 4, 5, 7, 10].map((sec) {
                    return DropdownMenuItem(value: sec, child: Text('${sec}s'));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      captureService.setCaptureInterval(value);
                    }
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Max photos
              _buildSettingCard(
                isDark,
                title: 'Photos maximum',
                subtitle: 'Limite par session d\'ouverture',
                trailing: DropdownButton<int>(
                  value: maxPhotos,
                  items: [10, 15, 20, 25, 30, 40, 50].map((max) {
                    return DropdownMenuItem(value: max, child: Text('$max'));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      captureService.setMaxPhotos(value);
                    }
                  },
                ),
              ),

              const SizedBox(height: 32),

              // Statistiques
              Text(
                'Statistiques',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              _buildStatCard(
                isDark,
                'Sessions totales',
                captureService.getStats()['total_sessions'].toString(),
                Icons.access_time,
              ),
              _buildStatCard(
                isDark,
                'Photos capturées',
                captureService.getStats()['total_photos'].toString(),
                Icons.camera_alt,
              ),
              _buildStatCard(
                isDark,
                'Échecs capture',
                captureService.getStats()['failed_captures'].toString(),
                Icons.error_outline,
              ),

              const SizedBox(height: 32),

              // Actions
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await captureService.cleanupAllSessions();
                    _showSuccess('Cache nettoyé');
                  },
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('Nettoyer le cache'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingCard(
    bool isDark, {
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    bool isDark,
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF3B82F6), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
