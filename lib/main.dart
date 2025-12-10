import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiosque_samsung_ultra/screen/auto_capture_indicator.dart';
import 'package:kiosque_samsung_ultra/screen/bluetooth_setup.dart';
import 'package:kiosque_samsung_ultra/service/auto_capture_orchestrator.dart';
import 'package:kiosque_samsung_ultra/service/auto_capture_service.dart';
import 'package:kiosque_samsung_ultra/service/bluetooth_fridge_service.dart';
import 'package:provider/provider.dart';
import 'package:kiosque_samsung_ultra/service/scan_mode_service.dart';
import 'dart:async';
import 'service/api.dart';
import 'package:kiosque_samsung_ultra/screen/alerts.dart';
import 'package:kiosque_samsung_ultra/screen/vision_scan.dart';
import 'package:kiosque_samsung_ultra/screen/inventory.dart';
import 'package:kiosque_samsung_ultra/service/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await ThemeSwitcher().init();

  // Initialiser services Auto-Capture
  final bluetoothService = BluetoothFridgeService();
  final captureService = AutoCaptureService();
  final api = KioskApiService();

  await bluetoothService.init();
  await captureService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bluetoothService),
        ChangeNotifierProvider.value(value: captureService),
        // L'orchestrateur sera créé plus tard avec le context
      ],
      child: SmartFridgeKioskApp(
        bluetoothService: bluetoothService,
        captureService: captureService,
        api: api,
      ),
    ),
  );
}

class SmartFridgeKioskApp extends StatelessWidget {
  final BluetoothFridgeService bluetoothService;
  final AutoCaptureService captureService;
  final KioskApiService api;

  const SmartFridgeKioskApp({
    super.key,
    required this.bluetoothService,
    required this.captureService,
    required this.api,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeSwitcher(),
      builder: (context, child) {
        return MaterialApp(
          title: 'Smart Fridge Kiosk',
          debugShowCheckedModeBanner: false,
          theme: ThemeSwitcher.lightTheme,
          darkTheme: ThemeSwitcher.darkTheme,
          themeMode: ThemeSwitcher().themeMode,
          home: KioskHomePage(
            bluetoothService: bluetoothService,
            captureService: captureService,
            api: api,
          ),
        );
      },
    );
  }
}

class KioskHomePage extends StatefulWidget {
  final BluetoothFridgeService bluetoothService;
  final AutoCaptureService captureService;
  final KioskApiService api;

  const KioskHomePage({
    super.key,
    required this.bluetoothService,
    required this.captureService,
    required this.api,
  });

  @override
  State<KioskHomePage> createState() => _KioskHomePageState();
}

class _KioskHomePageState extends State<KioskHomePage>
    with SingleTickerProviderStateMixin {
  final KioskApiService _api = KioskApiService();

  String? _kioskId;
  String? _pairingCode;
  int? _fridgeId;
  String? _fridgeName;
  bool _isPaired = false;
  bool _isInitializing = true;
  String? _errorMessage;

  Timer? _heartbeatTimer;
  Timer? _statusCheckTimer;
  Timer? _codeExpirationTimer;
  int _remainingSeconds = 300;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  AutoCaptureOrchestrator? _orchestrator;

  @override
  void initState() {
    super.initState();
    _initializePulseAnimation();
    _checkExistingKiosk();
    ScanModeService().init();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _statusCheckTimer?.cancel();
    _codeExpirationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _initializePulseAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  int _safeGetExpirationSeconds(Map<String, dynamic> data) {
    try {
      final expiresIn = data['expires_in_minutes'];

      if (expiresIn == null) {
        debugPrint(
          '⚠️ expires_in_minutes est null, utilisation de 5 min par défaut',
        );
        return 300;
      }

      if (expiresIn is int) {
        return expiresIn * 60;
      }

      if (expiresIn is double) {
        return (expiresIn * 60).toInt();
      }

      if (expiresIn is String) {
        final parsed = int.tryParse(expiresIn);
        if (parsed != null) {
          return parsed * 60;
        }
      }

      debugPrint(
        '⚠️ Type inattendu pour expires_in_minutes: ${expiresIn.runtimeType}',
      );
      return 300;
    } catch (e) {
      debugPrint('❌ Erreur lors de l\'extraction de expires_in_minutes: $e');
      return 300;
    }
  }

  void _applyInitData(Map<String, dynamic> initData, {bool isPaired = false}) {
    setState(() {
      _kioskId = initData['kiosk_id'] as String?;
      _isPaired = isPaired || (initData['is_paired'] as bool? ?? false);
      _fridgeId = initData['fridge_id'] as int?;
      _fridgeName = initData['fridge_name'] as String?;

      if (_isPaired) {
        _pairingCode = null;
        _remainingSeconds = 0;
      } else {
        _pairingCode = initData['pairing_code'] as String?;
        _remainingSeconds = _safeGetExpirationSeconds(initData);
      }

      _isInitializing = false;
      _errorMessage = null;
    });

    debugPrint(
      '📱 Kiosk initialisé: ID=$_kioskId, Paired=$_isPaired, Code=$_pairingCode',
    );
  }

  Future<void> _checkExistingKiosk() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      debugPrint('🔍 Vérification d\'un kiosk existant...');

      final initData = await _api.initKiosk(
        deviceName: 'Samsung Galaxy S22 Kiosk',
      );

      debugPrint('✅ Réponse API reçue: $initData');

      _applyInitData(initData);

      if (_isPaired) {
        _startHeartbeat();

        // Initialiser auto-capture après pairing
        if (_fridgeId != null && mounted) {
          _initializeOrchestrator();
        }
      } else {
        _startCodeExpiration();
        _startHeartbeat();
        _startStatusCheck();
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Erreur lors de l\'initialisation: $e');
      debugPrint('Stack trace: $stackTrace');

      setState(() {
        _isInitializing = false;
        _errorMessage = 'Erreur d\'initialisation: ${e.toString()}';
      });

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_isPaired) {
          _checkExistingKiosk();
        }
      });
    }
  }

  /// 🆕 Initialiser l'orchestrateur avec le context
  void _initializeOrchestrator() {
    if (_fridgeId == null || _orchestrator != null) return;

    _orchestrator = AutoCaptureOrchestrator(
      bluetoothService: widget.bluetoothService,
      captureService: widget.captureService,
      api: widget.api,
      context: context, // 🎯 Passer le context
    );

    _orchestrator!.init(_fridgeId!);

    debugPrint(
      '🎯 Auto-capture orchestrator initialisé pour frigo #$_fridgeId',
    );
  }

  Future<void> _regenerateCode() async {
    debugPrint('🔄 Régénération du code demandée...');

    _codeExpirationTimer?.cancel();
    _statusCheckTimer?.cancel();
    _heartbeatTimer?.cancel();

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
      _pairingCode = null;
      _remainingSeconds = 0;
    });

    try {
      if (_kioskId != null) {
        debugPrint('🗑️ Suppression de l\'ancien kiosk: $_kioskId');
        try {
          await _api.clearKioskId();
        } catch (e) {
          debugPrint('⚠️ Erreur suppression (ignorée): $e');
        }
      }

      debugPrint('📡 Création d\'un nouveau kiosk...');

      final initData = await _api.initKiosk(
        deviceName: 'Samsung Galaxy S22 Kiosk',
        forceNew: true,
      );

      debugPrint('✅ Nouveau code reçu: $initData');

      _applyInitData(initData, isPaired: false);

      _startCodeExpiration();
      _startHeartbeat();
      _startStatusCheck();

      if (mounted) {
        _showSuccess('Nouveau code généré avec succès');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Erreur lors de la régénération: $e');
      debugPrint('Stack trace: $stackTrace');

      setState(() {
        _isInitializing = false;
        _errorMessage =
            'Impossible de générer un nouveau code.\n${e.toString()}';
      });

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_isPaired && _pairingCode == null) {
          _regenerateCode();
        }
      });
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_kioskId != null) {
        _api.sendHeartbeat(_kioskId!);
      }
    });
  }

  void _startStatusCheck() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      if (_kioskId != null && !_isPaired) {
        try {
          final status = await _api.checkKioskStatus(_kioskId!);

          if (status['is_paired'] == true) {
            setState(() {
              _isPaired = true;
              _fridgeId = status['fridge_id'] as int?;
              _fridgeName = status['fridge_name'] as String?;
              _pairingCode = null;
              _errorMessage = null;
            });

            timer.cancel();
            _codeExpirationTimer?.cancel();
            _showSuccess('Kiosk pairé avec succès !');

            // Initialiser auto-capture après pairing
            if (_fridgeId != null && mounted) {
              _initializeOrchestrator();
            }
          }
        } catch (e) {
          debugPrint('⚠️ Erreur polling (ignorée): $e');
        }
      }
    });
  }

  void _startCodeExpiration() {
    _codeExpirationTimer?.cancel();

    if (_remainingSeconds <= 0) {
      debugPrint('⚠️ Aucun temps restant, timer non démarré');
      return;
    }

    _codeExpirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            _pairingCode = null;
            timer.cancel();
            debugPrint('⏰ Code expiré');
          }
        });
      }
    });
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: _isInitializing
            ? _buildLoadingView()
            : _errorMessage != null
            ? _buildErrorView()
            : _isPaired
            ? _buildPairedView()
            : _buildPairingView(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.kitchen, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Smart Fridge',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(
                'Mode Kiosque',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:
                (_isPaired ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                    .withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  (_isPaired
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B))
                      .withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                color: _isPaired
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
                size: 8,
              ),
              const SizedBox(width: 6),
              Text(
                _isPaired ? 'Pairé' : 'En attente',
                style: TextStyle(
                  color: _isPaired
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (_isPaired && _fridgeId != null)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              switch (value) {
                case 'auto_capture':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BluetoothSetupPage(),
                    ),
                  );
                  break;
                case 'scan':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          VisionScanPage(fridgeId: _fridgeId!),
                    ),
                  );
                  break;
                case 'inventory':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          KioskInventoryPage(fridgeId: _fridgeId!),
                    ),
                  );
                  break;
                case 'alerts':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          KioskAlertsPage(fridgeId: _fridgeId!),
                    ),
                  );
                  break;
                case 'theme':
                  ThemeSwitcher().toggleTheme();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'auto_capture',
                child: Row(
                  children: [
                    Icon(Icons.settings_bluetooth, size: 20),
                    SizedBox(width: 12),
                    Text('Auto-Capture'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'scan',
                child: Row(
                  children: [
                    Icon(Icons.camera_alt, size: 20),
                    SizedBox(width: 12),
                    Text('Scanner'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'inventory',
                child: Row(
                  children: [
                    Icon(Icons.inventory_2, size: 20),
                    SizedBox(width: 12),
                    Text('Inventaire'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'alerts',
                child: Row(
                  children: [
                    Icon(Icons.notifications, size: 20),
                    SizedBox(width: 12),
                    Text('Alertes'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(
                      Theme.of(context).brightness == Brightness.dark
                          ? Icons.light_mode
                          : Icons.dark_mode,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Theme.of(context).brightness == Brightness.dark
                          ? 'Mode clair'
                          : 'Mode sombre',
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: () => ThemeSwitcher().toggleTheme(),
          ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Initialisation...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Connexion au serveur',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
            const SizedBox(height: 24),
            Text(
              'Erreur de connexion',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Une erreur est survenue',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _checkExistingKiosk,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairingView() {
    if (_pairingCode == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.link_off,
              size: 80,
              color: Theme.of(context).iconTheme.color?.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text('Code expiré', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _regenerateCode,
              icon: const Icon(Icons.refresh),
              label: const Text('Générer un nouveau code'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              'Code de jumelage',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Text(
                  _pairingCode!,
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: 20,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.schedule,
                    color: Color(0xFFF59E0B),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Expire dans ${(_remainingSeconds ~/ 60)}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPairedView() {
    if (_orchestrator == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Indicateur auto-capture
        ListenableBuilder(
          listenable: _orchestrator!,
          builder: (context, _) {
            return AutoCaptureIndicator(orchestrator: _orchestrator!);
          },
        ),

        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 80,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Frigo connecté !',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _fridgeName ?? 'Mon Frigo',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Comment connecter',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInstructionStep('1', 'Ouvrez l\'application mobile'),
          _buildInstructionStep('2', 'Touchez "Connecter un frigo"'),
          _buildInstructionStep('3', 'Entrez le code affiché ci-dessus'),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
