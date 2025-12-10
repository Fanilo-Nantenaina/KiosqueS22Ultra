import 'package:flutter/material.dart';
import 'package:kiosque_samsung_ultra/service/bluetooth_fridge_service.dart';

/// Widget de debug pour vérifier l'état réel de la connexion Bluetooth
class BluetoothDebugPanel extends StatelessWidget {
  final BluetoothFridgeService bluetoothService;

  const BluetoothDebugPanel({super.key, required this.bluetoothService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: bluetoothService,
      builder: (context, _) {
        final stats = bluetoothService.getStats();
        final isConnected = stats['is_connected'] as bool;
        final messagesReceived = stats['messages_received'] as int;
        final lastMessage = stats['last_message'] as String?;

        return Card(
          margin: const EdgeInsets.all(16),
          color: const Color(0xFF1E293B),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titre
                Row(
                  children: [
                    Icon(
                      Icons.bug_report,
                      color: isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Debug Bluetooth',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: Color(0xFF475569)),
                const SizedBox(height: 16),

                // Statut connexion
                _buildInfoRow(
                  'État connexion',
                  isConnected ? '✅ Connecté' : '❌ Déconnecté',
                  isConnected ? Colors.green : Colors.red,
                ),

                _buildInfoRow(
                  'Device',
                  stats['device_name'] ?? 'Aucun',
                  Colors.blue,
                ),

                _buildInfoRow(
                  'Adresse',
                  stats['device_address'] ?? '-',
                  Colors.grey,
                ),

                const SizedBox(height: 16),
                const Divider(color: Color(0xFF475569)),
                const SizedBox(height: 16),

                // 🔥 INDICATEUR CLÉ : Messages reçus
                _buildInfoRow(
                  'Messages reçus',
                  '$messagesReceived',
                  messagesReceived > 0 ? Colors.green : Colors.orange,
                ),

                _buildInfoRow(
                  'Dernier message',
                  lastMessage != null ? _formatTime(lastMessage) : 'Jamais',
                  lastMessage != null ? Colors.green : Colors.grey,
                ),

                _buildInfoRow(
                  'État frigo',
                  stats['current_state'] ?? 'IDLE',
                  const Color(0xFF3B82F6),
                ),

                if (stats['reference_distance'] != null &&
                    stats['reference_distance'] > 0)
                  _buildInfoRow(
                    'Distance ref.',
                    '${stats['reference_distance']} cm',
                    Colors.purple,
                  ),

                const SizedBox(height: 20),

                // Boutons d'action
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          bluetoothService.printStats();
                        },
                        icon: const Icon(Icons.print, size: 18),
                        label: const Text('Print Stats'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isConnected
                            ? () async {
                                await bluetoothService.ping();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('PING envoyé'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('Ping'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Bouton de reconnexion
                if (isConnected)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await bluetoothService.forceDisconnect();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Déconnecté'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      },
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('Forcer déconnexion'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),

                // Message d'avertissement si pas de messages
                if (isConnected && messagesReceived == 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '⚠️ Connexion établie mais aucun message reçu.\n'
                            'Vérifiez que l\'Arduino est allumé.',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String isoString) {
    try {
      final time = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(time);

      if (diff.inSeconds < 5) return 'À l\'instant';
      if (diff.inSeconds < 60) return 'Il y a ${diff.inSeconds}s';
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
      return 'Il y a ${diff.inHours}h';
    } catch (e) {
      return 'Erreur';
    }
  }
}
