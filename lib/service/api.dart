// ============================================================================
// lib/services/kiosk_api_service.dart - VERSION REFACTORISÉE
// ============================================================================
// ✅ Cohérent avec les nouvelles routes kiosk (fridges.py)
// ✅ Gestion complète du cycle de vie du kiosk
// ============================================================================

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class KioskApiService {
  // ⚠️ CONFIGURATION : Remplacer par l'IP réelle de votre backend
  static const String baseUrl = 'http://localhost:8000/api/v1';
  static const Duration timeout = Duration(seconds: 30);

  // ============================================================================
  // KIOSK LIFECYCLE
  // ============================================================================

  /// ✅ ÉTAPE 1 : Initialise un nouveau kiosk
  ///
  /// Appelé au démarrage du kiosk Samsung.
  /// Le backend crée un frigo non-pairé avec un code 6 chiffres.
  ///
  /// Returns:
  ///   {
  ///     "kiosk_id": "uuid",
  ///     "pairing_code": "123456",
  ///     "expires_in_minutes": 5
  ///   }
  Future<Map<String, dynamic>> initKiosk({String? deviceName}) async {
    try {
      final body = <String, dynamic>{};
      if (deviceName != null) body['device_name'] = deviceName;

      final response = await http
          .post(
            Uri.parse('$baseUrl/fridges/kiosk/init'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Sauvegarder le kiosk_id localement
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('kiosk_id', data['kiosk_id']);

        return data;
      } else {
        throw Exception('Échec d\'initialisation: ${response.body}');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    } on SocketException {
      throw Exception('Pas de connexion réseau');
    }
  }

  /// ✅ ÉTAPE 2 : Heartbeat (appelé toutes les 30s)
  ///
  /// Maintient la connexion active entre le kiosk et le backend.
  Future<void> sendHeartbeat(String kioskId) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/fridges/kiosk/$kioskId/heartbeat'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // Ignorer les erreurs de heartbeat (non-bloquant)
    }
  }

  /// ✅ ÉTAPE 3 : Vérifier si le kiosk a été pairé (polling toutes les 5s)
  ///
  /// Le kiosk poll cette route après génération du code.
  /// Dès que le client mobile entre le code, cette route retourne is_paired=true.
  ///
  /// Returns:
  ///   {
  ///     "kiosk_id": "uuid",
  ///     "is_paired": false,
  ///     "fridge_id": null,
  ///     "fridge_name": null,
  ///     "last_heartbeat": "2025-11-30T12:00:00",
  ///     "paired_at": null
  ///   }
  Future<Map<String, dynamic>> checkKioskStatus(String kioskId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/fridges/kiosk/$kioskId/status'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Kiosk non trouvé');
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }

  /// Récupère le kiosk_id stocké localement
  Future<String?> getStoredKioskId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('kiosk_id');
  }

  /// Efface le kiosk_id stocké (reset du kiosk)
  Future<void> clearKioskId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('kiosk_id');
  }

  // ============================================================================
  // FRIDGE OPERATIONS (nécessitent fridgeId après pairing)
  // ============================================================================

  /// Récupère l'inventaire du frigo
  ///
  /// Note: Ne fonctionne qu'après le pairing (quand fridgeId est disponible)
  Future<List<dynamic>> getInventory(int fridgeId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/fridges/$fridgeId/inventory'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Erreur de chargement');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }

  /// Récupère les alertes du frigo
  Future<List<dynamic>> getAlerts(int fridgeId, {String? status}) async {
    try {
      var url = '$baseUrl/fridges/$fridgeId/alerts';
      if (status != null) url += '?status=$status';

      final response = await http
          .get(Uri.parse(url), headers: {'Content-Type': 'application/json'})
          .timeout(timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Erreur de chargement');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }

  /// Analyse une image du frigo avec Vision AI
  ///
  /// Note: Nécessite le fridgeId (après pairing)
  Future<Map<String, dynamic>> analyzeImage(
    int fridgeId,
    File imageFile,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/fridges/$fridgeId/vision/analyze'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      final streamedResponse = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Échec d\'analyse: ${response.body}');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Teste la connexion au backend
  Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/../health'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Récupère les informations du frigo après pairing
  Future<Map<String, dynamic>> getFridgeInfo(int fridgeId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/fridges/$fridgeId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Frigo non trouvé');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }
}
