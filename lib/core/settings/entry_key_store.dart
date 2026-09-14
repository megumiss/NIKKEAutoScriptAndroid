import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackendAccess {
  const BackendAccess({
    required this.baseUrl,
    this.key,
    this.localDeployment = false,
  });
  final String baseUrl;
  final String? key;
  final bool localDeployment;
}

abstract interface class EntryKeyStore {
  Future<BackendAccess?> read();
  Future<void> write(BackendAccess access);
}

class MemoryEntryKeyStore implements EntryKeyStore {
  BackendAccess? access;
  @override
  Future<BackendAccess?> read() async => access;
  @override
  Future<void> write(BackendAccess access) async => this.access = access;
}

class SecureEntryKeyStore implements EntryKeyStore {
  static const _name = 'nkas_backend_access';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  final _webSession = MemoryEntryKeyStore();

  @override
  Future<BackendAccess?> read() async {
    if (kIsWeb) return _webSession.read();
    final raw = await _storage.read(key: _name);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      return BackendAccess(
        baseUrl: value['baseUrl'] as String,
        key: value['key'] as String?,
        localDeployment: value['localDeployment'] == true,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> write(BackendAccess access) async {
    if (kIsWeb) return _webSession.write(access);
    await _storage.write(
      key: _name,
      value: jsonEncode({
        'baseUrl': access.baseUrl,
        'key': access.key,
        'localDeployment': access.localDeployment,
      }),
    );
  }
}
