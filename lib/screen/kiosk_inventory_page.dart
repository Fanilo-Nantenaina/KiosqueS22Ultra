import 'package:flutter/material.dart';
import 'package:kiosque_samsung_ultra/main.dart';

class KioskInventoryPage extends StatefulWidget {
  const KioskInventoryPage({super.key});

  @override
  State<KioskInventoryPage> createState() => _KioskInventoryPageState();
}

class _KioskInventoryPageState extends State<KioskInventoryPage> {
  final ApiService _api = ApiService();
  List<dynamic> _inventory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);

    try {
      final inventory = await _api.getInventory();
      setState(() {
        _inventory = inventory;
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
        title: const Text('Inventaire du frigo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInventory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _inventory.isEmpty
          ? _buildEmptyState()
          : _buildInventoryList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 100, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'Aucun produit dans le frigo',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _inventory.length,
      itemBuilder: (context, index) {
        final item = _inventory[index];
        return _buildInventoryCard(item);
      },
    );
  }

  Widget _buildInventoryCard(Map<String, dynamic> item) {
    final expiryDate = item['expiry_date'] != null
        ? DateTime.parse(item['expiry_date'])
        : null;
    final daysUntilExpiry = expiryDate?.difference(DateTime.now()).inDays;

    Color expiryColor = Colors.green;
    if (daysUntilExpiry != null) {
      if (daysUntilExpiry < 0) {
        expiryColor = Colors.red;
      } else if (daysUntilExpiry <= 3) {
        expiryColor = Colors.orange;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.shopping_basket, color: Colors.white),
        ),
        title: Text(
          'Produit #${item['product_id']}',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.inventory_2, size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Text(
                  '${item['quantity']} ${item['unit']}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
            if (expiryDate != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: expiryColor),
                  const SizedBox(width: 8),
                  Text(
                    daysUntilExpiry! < 0
                        ? 'Expiré'
                        : 'Expire dans $daysUntilExpiry jour${daysUntilExpiry > 1 ? 's' : ''}',
                    style: TextStyle(color: expiryColor),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getSourceColor(item['source']).withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            item['source'] ?? 'manual',
            style: TextStyle(
              color: _getSourceColor(item['source']),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Color _getSourceColor(String? source) {
    switch (source) {
      case 'vision':
        return Colors.blue;
      case 'barcode':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
