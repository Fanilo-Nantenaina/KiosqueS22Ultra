import 'package:flutter/material.dart';
import 'package:kiosque_samsung_ultra/service/api.dart';

class ConsumptionReviewPage extends StatefulWidget {
  final int fridgeId;
  final Map<String, dynamic> analysisResult;

  const ConsumptionReviewPage({
    super.key,
    required this.fridgeId,
    required this.analysisResult,
  });

  @override
  State<ConsumptionReviewPage> createState() => _ConsumptionReviewPageState();
}

class _ConsumptionReviewPageState extends State<ConsumptionReviewPage> {
  final KioskApiService _api = KioskApiService();

  late List<Map<String, dynamic>> _items;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initializeItems();
  }

  void _initializeItems() {
    final detected = widget.analysisResult['detected_products'] as List;

    _items = detected.map((product) {
      return {
        'detected_name': product['detected_name'],
        'detected_count': product['detected_count'],
        'confidence': product['confidence'],

        // Matching auto
        'matched_item_id': product['matched_item_id'],
        'matched_product_name': product['matched_product_name'],
        'available_quantity': product['available_quantity'],
        'match_score': product['match_score'],

        // État local
        'selected_item_id': product['matched_item_id'], // ID sélectionné
        'quantity_to_consume': product['detected_count'].toDouble(),
        'possible_matches': product['possible_matches'] ?? [],
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final requiresReview =
        widget.analysisResult['requires_manual_review'] ?? false;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Valider la consommation'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      ),
      body: Column(
        children: [
          if (requiresReview)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFF59E0B).withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Certains produits nécessitent une vérification manuelle',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _items.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      return _buildProductCard(_items[index], index, isDark);
                    },
                  ),
          ),

          _buildBottomBar(isDark),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item, int index, bool isDark) {
    final matchScore = item['match_score'] as double?;
    final hasGoodMatch = matchScore != null && matchScore >= 80;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasGoodMatch
              ? const Color(0xFF10B981).withOpacity(0.3)
              : const Color(0xFFF59E0B).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (hasGoodMatch
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B))
                      .withOpacity(0.15),
                  Colors.transparent,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasGoodMatch ? Icons.check_circle : Icons.help_outline,
                  color: hasGoodMatch
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['detected_name'],
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Détecté : ${item['detected_count']} unité(s)',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (matchScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: hasGoodMatch
                          ? const Color(0xFF10B981).withOpacity(0.2)
                          : const Color(0xFFF59E0B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${matchScore.toInt()}%',
                      style: TextStyle(
                        color: hasGoodMatch
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _removeItem(index),
                  icon: const Icon(Icons.close),
                  color: const Color(0xFFEF4444),
                  tooltip: 'Retirer ce produit',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Produit correspondant:',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),

                if (item['matched_item_id'] != null)
                  _buildMatchedProductTile(item, isDark)
                else
                  _buildManualSelection(item, index, isDark),
                const SizedBox(height: 16),
                _buildQuantitySelector(item, index, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchedProductTile(Map<String, dynamic> item, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2, color: Color(0xFF10B981), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['matched_product_name'],
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Disponible : ${item['available_quantity']} unité(s)',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showAlternatives(item),
            child: const Text('Changer'),
          ),
        ],
      ),
    );
  }

  Widget _buildManualSelection(
    Map<String, dynamic> item,
    int index,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.search, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              Text(
                'Aucune correspondance automatique',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAlternatives(item),
              icon: const Icon(Icons.list),
              label: const Text('Sélectionner manuellement'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantitySelector(
    Map<String, dynamic> item,
    int index,
    bool isDark,
  ) {
    final maxQuantity = item['available_quantity'] as double? ?? 999.0;
    final currentQuantity = item['quantity_to_consume'] as double;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quantité à retirer:',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: currentQuantity > 0.5
                    ? () {
                        setState(() {
                          item['quantity_to_consume'] = currentQuantity - 0.5;
                        });
                      }
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: const Color(0xFFEF4444),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${currentQuantity.toStringAsFixed(1)} unité(s)',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: currentQuantity < maxQuantity
                    ? () {
                        setState(() {
                          item['quantity_to_consume'] = (currentQuantity + 0.5)
                              .clamp(0, maxQuantity);
                        });
                      }
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                color: const Color(0xFF10B981),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _removeItem(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Retirer ce produit ?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Le produit "${_items[index]['detected_name']}" ne sera pas retiré de l\'inventaire.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _items.removeAt(index);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Produit retiré de la liste'),
                  backgroundColor: Color(0xFF64748B),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text(
              'Retirer',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF64748B).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 80,
                color: isDark
                    ? Colors.white.withOpacity(0.3)
                    : Colors.black.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucun produit à retirer',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tous les produits détectés ont été retirés de la liste',
              style: TextStyle(
                color: isDark ? Colors.white.withOpacity(0.6) : Colors.black54,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Retour'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                backgroundColor: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAlternatives(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _AlternativesSheet(
        fridgeId: widget.fridgeId,
        item: item,
        onSelected: (selectedId, selectedName, selectedQty) {
          setState(() {
            item['selected_item_id'] = selectedId;
            item['matched_product_name'] = selectedName;
            item['available_quantity'] = selectedQty;
            item['match_score'] = 100.0;

            final detectedCount = (item['detected_count'] as num).toDouble();
            final availableQty = selectedQty;

            if (detectedCount > availableQty) {
              item['quantity_to_consume'] = availableQty;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Quantité ajustée à $availableQty (stock max)'),
                  backgroundColor: const Color(0xFFF59E0B),
                  duration: const Duration(seconds: 3),
                ),
              );
            } else {
              item['quantity_to_consume'] = detectedCount;
            }
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildBottomBar(bool isDark) {
    final totalItems = _items.length;
    final validItems = _items
        .where((item) => item['selected_item_id'] != null)
        .length;

    final canSubmit =
        totalItems > 0 && validItems == totalItems && !_isSubmitting;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  totalItems > 0 ? 'Produits validés:' : 'Liste vide',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                  ),
                ),
                if (totalItems > 0)
                  Text(
                    '$validItems / $totalItems',
                    style: TextStyle(
                      color: validItems == totalItems
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSubmit ? _submitConsumption : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFFEF4444),
                  disabledBackgroundColor: Colors.grey,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        totalItems > 0
                            ? 'Confirmer la sortie ($validItems produits)'
                            : 'Aucun produit à retirer',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitConsumption() async {
    setState(() => _isSubmitting = true);

    try {
      final itemsToConsume = _items
          .where((item) => item['selected_item_id'] != null)
          .map(
            (item) => {
              'inventory_item_id': item['selected_item_id'],
              'quantity_consumed': item['quantity_to_consume'],
              'detected_product_name': item['detected_name'],
            },
          )
          .toList();

      final result = await _api.consumeBatch(widget.fridgeId, itemsToConsume);

      if (!mounted) return;

      final successCount = result['success_count'] as int;
      final failedCount = result['failed_count'] as int;

      if (failedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount produit(s) retirés avec succès'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount réussis, $failedCount échoués'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _AlternativesSheet extends StatefulWidget {
  final int fridgeId;
  final Map<String, dynamic> item;
  final Function(int, String, double) onSelected;

  const _AlternativesSheet({
    required this.fridgeId,
    required this.item,
    required this.onSelected,
  });

  @override
  State<_AlternativesSheet> createState() => _AlternativesSheetState();
}

class _AlternativesSheetState extends State<_AlternativesSheet> {
  final KioskApiService _api = KioskApiService();
  List<dynamic> _allInventory = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    try {
      final inventory = await _api.getInventory(widget.fridgeId);
      setState(() {
        _allInventory = inventory;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _filteredInventory {
    if (_searchQuery.isEmpty) {
      return _allInventory;
    }
    return _allInventory.where((product) {
      final name = (product['product_name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final alternatives = widget.item['possible_matches'] as List? ?? [];

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 24),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Titre
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Sélectionner le produit',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(24),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Rechercher un produit...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF334155),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Contenu scrollable
          Flexible(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  )
                : _buildProductsList(alternatives),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList(List alternatives) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        // Section : Suggestions (si disponibles)
        if (alternatives.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.stars, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text(
                'Suggestions (${alternatives.length})',
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...alternatives.map(
            (alt) => _buildAlternativeTile(alt, isFromMatching: true),
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFF475569), height: 1),
          const SizedBox(height: 24),
        ],

        // Section : Tous les produits
        Row(
          children: [
            const Icon(Icons.inventory_2, color: Color(0xFF3B82F6), size: 18),
            const SizedBox(width: 8),
            Text(
              'Tous les produits (${_filteredInventory.length})',
              style: const TextStyle(
                color: Color(0xFF3B82F6),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_filteredInventory.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Aucun produit trouvé',
              style: TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._filteredInventory.map((product) => _buildInventoryTile(product)),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildAlternativeTile(
    Map<String, dynamic> alt, {
    bool isFromMatching = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onSelected(
            alt['item_id'],
            alt['product_name'],
            alt['available_quantity'],
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(12),
              border: isFromMatching
                  ? Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    color: Color(0xFF3B82F6),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alt['product_name'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Disponible : ${alt['available_quantity']} unité(s)',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isFromMatching)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${alt['score'].toInt()}%',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryTile(Map<String, dynamic> product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onSelected(
            product['id'],
            product['product_name'] ?? 'Produit #${product['product_id']}',
            (product['quantity'] as num).toDouble(),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF64748B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shopping_basket,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['product_name'] ??
                            'Produit #${product['product_id']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            'Stock : ${product['quantity']} ${product['unit']}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          if (product['product_category'] != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF475569),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                product['product_category'],
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white24,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
