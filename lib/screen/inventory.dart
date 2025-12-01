import 'package:flutter/material.dart';
import 'package:kiosque_samsung_ultra/service/api.dart';

class KioskInventoryPage extends StatefulWidget {
  final int fridgeId;

  const KioskInventoryPage({super.key, required this.fridgeId});

  @override
  State<KioskInventoryPage> createState() => _KioskInventoryPageState();
}

class _KioskInventoryPageState extends State<KioskInventoryPage> {
  final KioskApiService _api = KioskApiService();
  List<dynamic> _inventory = [];
  bool _isLoading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);

    try {
      final inventory = await _api.getInventory(widget.fridgeId);

      setState(() {
        _inventory = _filterInventory(inventory);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erreur de chargement: $e');
    }
  }

  List<dynamic> _filterInventory(List<dynamic> items) {
    if (_filter == 'all') return items;

    return items.where((item) {
      final expiryDate = item['expiry_date'] != null
          ? DateTime.parse(item['expiry_date'])
          : null;

      if (expiryDate == null) return false;

      final daysUntilExpiry = expiryDate.difference(DateTime.now()).inDays;

      if (_filter == 'expired') {
        return daysUntilExpiry < 0;
      } else if (_filter == 'expiring') {
        return daysUntilExpiry >= 0 && daysUntilExpiry <= 3;
      }

      return true;
    }).toList();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
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
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _inventory.isEmpty
                ? _buildEmptyState()
                : _buildInventoryList(),
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
          _buildFilterChip('Tous', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('À consommer', 'expiring'),
          const SizedBox(width: 8),
          _buildFilterChip('Expirés', 'expired'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;

    return InkWell(
      onTap: () {
        setState(() => _filter = value);
        _loadInventory();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.deepPurple.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.deepPurple
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String message = 'Aucun produit dans le frigo';
    IconData icon = Icons.inbox_outlined;

    if (_filter == 'expiring') {
      message = 'Aucun produit à consommer rapidement';
      icon = Icons.check_circle_outline;
    } else if (_filter == 'expired') {
      message = 'Aucun produit expiré';
      icon = Icons.check_circle_outline;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 100, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryList() {
    return RefreshIndicator(
      onRefresh: _loadInventory,
      backgroundColor: const Color(0xFF1E293B),
      color: Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _inventory.length,
        itemBuilder: (context, index) {
          return _buildInventoryCard(_inventory[index]);
        },
      ),
    );
  }

  Widget _buildInventoryCard(Map<String, dynamic> item) {
    final expiryDate = item['expiry_date'] != null
        ? DateTime.parse(item['expiry_date'])
        : null;
    final daysUntilExpiry = expiryDate?.difference(DateTime.now()).inDays;

    Color expiryColor = Colors.green;
    IconData expiryIcon = Icons.check_circle;
    String expiryText = 'Frais';

    if (daysUntilExpiry != null) {
      if (daysUntilExpiry < 0) {
        expiryColor = Colors.red;
        expiryIcon = Icons.dangerous;
        expiryText = 'Expiré';
      } else if (daysUntilExpiry == 0) {
        expiryColor = Colors.orange;
        expiryIcon = Icons.warning;
        expiryText = 'Expire aujourd\'hui';
      } else if (daysUntilExpiry <= 3) {
        expiryColor = Colors.orange;
        expiryIcon = Icons.warning;
        expiryText =
            'Expire dans $daysUntilExpiry jour${daysUntilExpiry > 1 ? 's' : ''}';
      } else {
        expiryText = 'Expire dans $daysUntilExpiry jours';
      }
    }

    final productName =
        item['product']?['name'] ?? 'Produit #${item['product_id']}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            expiryColor.withOpacity(0.15),
            expiryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: expiryColor.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showItemDetails(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shopping_basket,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            productName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.inventory_2,
                                size: 16,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${item['quantity']} ${item['unit']}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getSourceColor(item['source']).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getSourceText(item['source']),
                        style: TextStyle(
                          color: _getSourceColor(item['source']),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (expiryDate != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: expiryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: expiryColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(expiryIcon, size: 16, color: expiryColor),
                        const SizedBox(width: 8),
                        Text(
                          expiryText,
                          style: TextStyle(
                            color: expiryColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showItemDetails(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shopping_basket,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['product']?['name'] ??
                            'Produit #${item['product_id']}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Quantité: ${item['quantity']} ${item['unit']}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDetailRow('Source', _getSourceText(item['source'])),
            if (item['expiry_date'] != null)
              _buildDetailRow(
                'Date d\'expiration',
                _formatDate(item['expiry_date']),
              ),
            if (item['open_date'] != null)
              _buildDetailRow(
                'Date d\'ouverture',
                _formatDate(item['open_date']),
              ),
            if (item['added_at'] != null)
              _buildDetailRow('Ajouté le', _formatDateTime(item['added_at'])),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Fermer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSourceColor(String? source) {
    switch (source) {
      case 'vision':
        return Colors.blue;
      case 'barcode':
        return Colors.green;
      case 'manual':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getSourceText(String? source) {
    switch (source) {
      case 'vision':
        return 'Vision IA';
      case 'barcode':
        return 'Code-barres';
      case 'manual':
        return 'Manuel';
      default:
        return 'Inconnu';
    }
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateTime(String dateStr) {
    final date = DateTime.parse(dateStr);
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
