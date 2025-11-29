import 'package:flutter/material.dart';
import 'package:kiosque_samsung_ultra/main.dart';

class KioskAlertsPage extends StatefulWidget {
  const KioskAlertsPage({super.key});

  @override
  State<KioskAlertsPage> createState() => _KioskAlertsPageState();
}

class _KioskAlertsPageState extends State<KioskAlertsPage> {
  final ApiService _api = ApiService();
  List<dynamic> _alerts = [];
  bool _isLoading = true;
  String _filter = 'pending';

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);

    try {
      final alerts = await _api.getAlerts(status: _filter);
      setState(() {
        _alerts = alerts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erreur: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Alertes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAlerts,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _alerts.isEmpty
                ? _buildEmptyState()
                : _buildAlertsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildFilterChip('En attente', 'pending'),
          const SizedBox(width: 8),
          _buildFilterChip('Toutes', null),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value) {
    final isSelected = _filter == value;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _filter = value ?? 'pending');
          _loadAlerts();
        }
      },
      backgroundColor: Colors.white.withOpacity(0.05),
      selectedColor: Colors.deepPurple.withOpacity(0.3),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white54,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? Colors.deepPurple : Colors.white.withOpacity(0.1),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 100, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'Aucune alerte',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _alerts.length,
      itemBuilder: (context, index) {
        final alert = _alerts[index];
        return _buildAlertCard(alert);
      },
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final type = alert['type'] ?? '';
    final alertColor = _getAlertColor(type);
    final alertIcon = _getAlertIcon(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            alertColor.withOpacity(0.1),
            alertColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: alertColor.withOpacity(0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: alertColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(alertIcon, color: alertColor),
        ),
        title: Text(
          _getAlertTitle(type),
          style: TextStyle(color: alertColor, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            alert['message'] ?? '',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getStatusColor(alert['status']).withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            alert['status'] ?? 'pending',
            style: TextStyle(
              color: _getStatusColor(alert['status']),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Color _getAlertColor(String type) {
    switch (type) {
      case 'EXPIRED':
        return Colors.red;
      case 'EXPIRY_SOON':
        return Colors.orange;
      case 'LOST_ITEM':
        return Colors.yellow;
      case 'LOW_STOCK':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getAlertIcon(String type) {
    switch (type) {
      case 'EXPIRED':
        return Icons.dangerous;
      case 'EXPIRY_SOON':
        return Icons.warning;
      case 'LOST_ITEM':
        return Icons.search_off;
      case 'LOW_STOCK':
        return Icons.trending_down;
      default:
        return Icons.notification_important;
    }
  }

  String _getAlertTitle(String type) {
    switch (type) {
      case 'EXPIRED':
        return 'Produit expiré';
      case 'EXPIRY_SOON':
        return 'Expiration proche';
      case 'LOST_ITEM':
        return 'Objet non détecté';
      case 'LOW_STOCK':
        return 'Stock faible';
      default:
        return 'Alerte';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'resolved':
        return Colors.green;
      case 'acknowledged':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }
}