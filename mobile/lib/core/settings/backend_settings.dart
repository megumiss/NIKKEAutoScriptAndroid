import 'package:shared_preferences/shared_preferences.dart';

abstract interface class BackendSettings {
  Future<String?> readBaseUrl();
  Future<void> writeBaseUrl(String value);
}

class SharedPreferencesBackendSettings implements BackendSettings {
  static const _baseUrlKey = 'control_base_url';

  @override
  Future<String?> readBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_baseUrlKey);
  }

  @override
  Future<void> writeBaseUrl(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_baseUrlKey, value);
  }
}
