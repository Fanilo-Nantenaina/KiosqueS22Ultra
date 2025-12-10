import 'package:flutter/material.dart';
import 'package:kiosque_samsung_ultra/service/auto_capture_orchestrator.dart';
import 'package:kiosque_samsung_ultra/service/auto_capture_service.dart';
import 'package:kiosque_samsung_ultra/service/bluetooth_fridge_service.dart';

class AutoCaptureDebugPanel extends StatelessWidget {
  final BluetoothFridgeService bluetoothService;
  final AutoCaptureService captureService;
  final AutoCaptureOrchestrator orchestrator;

  const AutoCaptureDebugPanel({
    super.key,
    required this.bluetoothService,
    required this.captureService,
    required this.orchestrator,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: ExpansionTile(
        leading: const Icon(Icons.bug_report),
        title: const Text('Debug Auto-Capture'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bluetooth Stats
                _buildSection(
                  'Bluetooth',
                  bluetoothService.getStats(),
                  Icons.bluetooth,
                ),

                const Divider(height: 32),

                // Capture Stats
                _buildSection(
                  'Capture',
                  captureService.getStats(),
                  Icons.camera_alt,
                ),

                const Divider(height: 32),

                // Orchestrator Stats
                _buildSection(
                  'Orchestrateur',
                  orchestrator.getStats(),
                  Icons.settings,
                ),

                const SizedBox(height: 16),

                // Actions rapides
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        bluetoothService.printStats();
                        captureService.printStats();
                      },
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('Print Stats'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await captureService.cleanupAllSessions();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cache nettoyé')),
                        );
                      },
                      icon: const Icon(Icons.cleaning_services, size: 18),
                      label: const Text('Cleanup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    String title,
    Map<String, dynamic> stats,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...stats.entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(entry.key, style: const TextStyle(fontSize: 13)),
                ),
                Text(
                  entry.value.toString(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
