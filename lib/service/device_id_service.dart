import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class DeviceIdService {
  static final DeviceIdService _instance = DeviceIdService._internal();
  factory DeviceIdService() => _instance;
  DeviceIdService._internal();

  String? _cachedDeviceId;

  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    final prefs = await SharedPreferences.getInstance();
    String? storedDeviceId = prefs.getString('device_id');

    if (storedDeviceId != null && storedDeviceId.isNotEmpty) {
      _cachedDeviceId = storedDeviceId;
      return storedDeviceId;
    }

    String deviceId = await _getHardwareDeviceId();

    await prefs.setString('device_id', deviceId);
    _cachedDeviceId = deviceId;

    return deviceId;
  }

  Future<String> _getHardwareDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      String androidId = androidInfo.id;

      return 'android_$androidId';
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      String identifierForVendor = iosInfo.identifierForVendor ?? 'unknown';

      return 'ios_$identifierForVendor';
    } else {
      return 'device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<void> clearDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_id');
    _cachedDeviceId = null;
  }
}
