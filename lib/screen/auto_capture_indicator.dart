import 'package:flutter/material.dart';
import 'package:kiosque_samsung_ultra/screen/auto_capture_orchestrator.dart';

class AutoCaptureIndicator extends StatelessWidget {
  final AutoCaptureOrchestrator orchestrator;

  const AutoCaptureIndicator({super.key, required this.orchestrator});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: orchestrator,
      builder: (context, _) {
        final stats = orchestrator.getStats();
        final isActive = stats['is_active'] as bool;
        final isUploading = stats['is_uploading'] as bool;
        final pendingPhotos = stats['pending_photos'] as int;

        if (!isActive && !isUploading) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF3B82F6).withOpacity(0.1),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              // Icône animée
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isActive || isUploading)
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    Icon(
                      isUploading ? Icons.cloud_upload : Icons.camera_alt,
                      color: const Color(0xFF3B82F6),
                      size: 24,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Texte d'état
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isUploading
                          ? 'Upload en cours...'
                          : 'Capture automatique',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isUploading
                          ? '$pendingPhotos photo${pendingPhotos > 1 ? 's' : ''} à envoyer'
                          : 'Session en cours',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),

              // Bouton annuler (seulement si capture active, pas upload)
              if (isActive && !isUploading)
                IconButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Annuler la capture ?'),
                        content: const Text(
                          'Les photos capturées ne seront pas envoyées.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Non'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Oui, annuler'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await orchestrator.cancelCurrentSession();
                    }
                  },
                  icon: const Icon(Icons.close),
                  tooltip: 'Annuler',
                ),
            ],
          ),
        );
      },
    );
  }
}
