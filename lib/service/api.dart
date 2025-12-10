import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:kiosque_samsung_ultra/service/device_id_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class KioskApiService {
  static const String baseUrl = 'http://localhost:8000/api/v1';
  static const Duration timeout = Duration(seconds: 30);
  final DeviceIdService _deviceIdService = DeviceIdService();

  Future<Map<String, String>> _getKioskHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final kioskId = prefs.getString('kiosk_id');

    if (kioskId == null) {
      throw Exception('Kiosk not initialized');
    }

    return {'Content-Type': 'application/json', 'X-Kiosk-ID': kioskId};
  }

  Future<Map<String, dynamic>> initKiosk({
    String? deviceName,
    bool forceNew = false,
  }) async {
    try {
      final deviceId = await _deviceIdService.getDeviceId();
      debugPrint('Device ID (stable): $deviceId');

      if (!forceNew) {
        final existingKiosk = await _checkExistingDevice(deviceId);

        if (existingKiosk != null) {
          debugPrint('Kiosk existant trouvé: ${existingKiosk['kiosk_id']}');

          final isPaired = existingKiosk['is_paired'] == true;

          if (isPaired) {
            debugPrint('Kiosk valide restauré');
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('kiosk_id', existingKiosk['kiosk_id']);
            return existingKiosk;
          } else {
            debugPrint('Kiosk non pairé trouvé, on demande un nouveau code');
            forceNew = true;
          }
        }
      }

      debugPrint(
        '🆕 ${forceNew ? "Régénération du code" : "Création"} du kiosk...',
      );

      final body = <String, dynamic>{'device_id': deviceId};

      if (forceNew) {
        body['regenerate'] = true;
      }

      if (deviceName != null) {
        body['device_name'] = deviceName;
      }

      debugPrint('📤 Body envoyé: $body');

      final response = await http
          .post(
            Uri.parse('$baseUrl/fridges/kiosk/init'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(timeout);

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('kiosk_id', data['kiosk_id']);

        debugPrint(
          'Kiosk ${forceNew ? "mis à jour" : "créé"}: ${data['kiosk_id']}',
        );
        debugPrint('🔑 Code: ${data['pairing_code']}');

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

  Future<Map<String, dynamic>> regeneratePairingCode(String kioskId) async {
    try {
      debugPrint('Régénération du code pour kiosk: $kioskId');

      final response = await http
          .post(
            Uri.parse('$baseUrl/fridges/kiosk/$kioskId/regenerate-code'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeout);

      debugPrint('Regenerate response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Nouveau code: ${data['pairing_code']}');
        return data;
      } else if (response.statusCode == 404) {
        throw Exception('Kiosk non trouvé');
      } else {
        throw Exception('Erreur ${response.statusCode}: ${response.body}');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }

  Future<Map<String, dynamic>?> _checkExistingDevice(String deviceId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/fridges/kiosk/device/$deviceId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Erreur lors de la vérification du device: $e');
      return null;
    }
  }

  Future<void> sendHeartbeat(String kioskId) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/fridges/kiosk/$kioskId/heartbeat'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // Ignorer les erreurs de heartbeat
    }
  }

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

  Future<String?> getStoredKioskId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('kiosk_id');
  }

  Future<void> clearKioskId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('kiosk_id');
    debugPrint('Kiosk ID supprimé du stockage local');
  }

  Future<List<dynamic>> getInventory(int fridgeId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/fridges/$fridgeId/inventory'),
            headers: await _getKioskHeaders(),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Kiosk non authentifié');
      } else if (response.statusCode == 403) {
        throw Exception('Accès refusé à ce frigo');
      } else {
        throw Exception('Erreur de chargement');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }

  Future<List<dynamic>> getAlerts(int fridgeId, {String? status}) async {
    try {
      var url = '$baseUrl/fridges/$fridgeId/alerts';
      if (status != null) url += '?status=$status';

      final response = await http
          .get(Uri.parse(url), headers: await _getKioskHeaders())
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

  Future<Map<String, dynamic>> analyzeImage(
    int fridgeId,
    File imageFile,
  ) async {
    try {
      final kioskHeaders = await _getKioskHeaders();

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/fridges/$fridgeId/vision/analyze'),
      );

      request.headers['X-Kiosk-ID'] = kioskHeaders['X-Kiosk-ID']!;

      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      final streamedResponse = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Kiosk non authentifié');
      } else if (response.statusCode == 403) {
        throw Exception('Accès refusé à ce frigo');
      } else {
        throw Exception('Échec d\'analyse: ${response.body}');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }

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

  Future<Map<String, dynamic>> getFridgeInfo(int fridgeId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/fridges/$fridgeId'),
            headers: await _getKioskHeaders(),
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

  Future<Map<String, dynamic>> analyzeImageForConsumption(
    int fridgeId,
    File imageFile,
  ) async {
    try {
      final kioskHeaders = await _getKioskHeaders();

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/fridges/$fridgeId/vision/analyze-consume'),
      );

      request.headers['X-Kiosk-ID'] = kioskHeaders['X-Kiosk-ID']!;
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

  Future<Map<String, dynamic>> consumeBatch(
    int fridgeId,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/fridges/$fridgeId/inventory/consume-batch'),
            headers: await _getKioskHeaders(),
            body: json.encode({'items': items}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Erreur de consommation');
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }
}
