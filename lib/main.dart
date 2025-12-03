import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  runApp(const SmartFridgeKioskApp());
}

class SmartFridgeKioskApp extends StatelessWidget {
  const SmartFridgeKioskApp({super.key});

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
          home: const KioskHomePage(),
        );
      },
    );
  }
}

class KioskHomePage extends StatefulWidget {
  const KioskHomePage({super.key});

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

  @override
  void initState() {
    super.initState();
    _initializePulseAnimation();
    _checkExistingKiosk();
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

  Future<void> _checkExistingKiosk() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      final storedKioskId = await _api.getStoredKioskId();

      if (storedKioskId != null) {
        // Vérifier le statut du kiosk existant
        try {
          final status = await _api.checkKioskStatus(storedKioskId);

          setState(() {
            _kioskId = storedKioskId;
            _isPaired = status['is_paired'] ?? false;
            _fridgeId = status['fridge_id'];
            _fridgeName = status['fridge_name'];
            _isInitializing = false;
          });

          if (_isPaired) {
            _startHeartbeat();
          } else {
            // Kiosk existe mais pas pairé, générer un nouveau code
            await _initializeNewKiosk();
          }
        } catch (e) {
          // Le kiosk stocké n'est plus valide, en créer un nouveau
          await _api.clearKioskId();
          await _initializeNewKiosk();
        }
      } else {
        // Pas de kiosk stocké, en créer un nouveau
        await _initializeNewKiosk();
      }
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Erreur d\'initialisation: ${e.toString()}';
      });
    }
  }

  Future<void> _initializeNewKiosk() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
      _pairingCode = null;
    });

    try {
      final initData = await _api.initKiosk(
        deviceName: 'Samsung Galaxy S22 Kiosk',
      );

      setState(() {
        _kioskId = initData['kiosk_id'];
        _pairingCode = initData['pairing_code'];
        _remainingSeconds = (initData['expires_in_minutes'] as int) * 60;
        _isInitializing = false;
        _isPaired = false;
      });

      _startCodeExpiration();
      _startHeartbeat();
      _startStatusCheck();
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage =
            'Impossible de se connecter au serveur.\n${e.toString()}';
      });

      // Réessayer après 5 secondes
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_isPaired && _pairingCode == null) {
          _initializeNewKiosk();
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
              _fridgeId = status['fridge_id'];
              _fridgeName = status['fridge_name'];
              _pairingCode = null;
              _errorMessage = null;
            });

            timer.cancel();
            _codeExpirationTimer?.cancel();
            _showSuccess('Kiosk pairé avec succès !');
          }
        } catch (e) {
          // Ignorer les erreurs de polling
        }
      }
    });
  }

  void _startCodeExpiration() {
    _codeExpirationTimer?.cancel();
    _codeExpirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            _pairingCode = null;
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> _regenerateCode() async {
    _codeExpirationTimer?.cancel();
    _statusCheckTimer?.cancel();
    await _initializeNewKiosk();
  }
/* 
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } */

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
            _buildInstructions(),
          ],
        ),
      ),
    );
  }

  Widget _buildPairedView() {
    return Center(
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
          const SizedBox(height: 4),
          Text('ID: $_fridgeId', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 48),
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildActionCard(
            'Scanner le frigo',
            Icons.camera_alt,
            const Color(0xFF3B82F6),
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VisionScanPage(fridgeId: _fridgeId!),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            'Voir l\'inventaire',
            Icons.inventory_2,
            const Color(0xFF10B981),
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      KioskInventoryPage(fridgeId: _fridgeId!),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            'Consulter les alertes',
            Icons.notifications,
            const Color(0xFFF59E0B),
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => KioskAlertsPage(fridgeId: _fridgeId!),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Theme.of(context).iconTheme.color?.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
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
