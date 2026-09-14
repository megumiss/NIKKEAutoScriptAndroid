import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:nkas_mobile/core/api/api_client.dart';
import 'package:nkas_mobile/core/api/backend_address.dart';
import 'package:nkas_mobile/core/settings/entry_key_store.dart';
import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/queue_info.dart';
import 'package:nkas_mobile/core/api/calendar_info.dart';
import 'package:nkas_mobile/core/api/log_info.dart';
import 'package:nkas_mobile/core/api/update_info.dart';
import 'package:nkas_mobile/core/api/screenshot_frame.dart';
import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/api/schema_info.dart';
import 'package:nkas_mobile/core/api/deploy_info.dart';
import 'package:nkas_mobile/core/api/system_status.dart';
import 'package:nkas_mobile/core/settings/backend_settings.dart';

const defaultBackendBaseUrl = 'http://127.0.0.1:12271';
const supportedApiVersion = 2;

enum ConnectionPhase { connecting, connected, disconnected, incompatible }

@immutable
class BackendConnectionState {
  const BackendConnectionState({
    required this.phase,
    required this.baseUrl,
    this.status,
    this.message,
  });

  final ConnectionPhase phase;
  final String baseUrl;
  final SystemStatus? status;
  final String? message;

  String get label => switch (phase) {
    ConnectionPhase.connecting => '连接中',
    ConnectionPhase.connected => '已连接',
    ConnectionPhase.disconnected => '已断开',
    ConnectionPhase.incompatible => '版本不兼容',
  };
}

class ConnectionController extends ChangeNotifier {
  ConnectionController({
    required ApiClient api,
    required BackendSettings settings,
    EntryKeyStore? keyStore,
    this.localEntryLoader,
  }) : _api = api,
       _settings = settings,
       _keyStore = keyStore ?? MemoryEntryKeyStore(),
       _state = const BackendConnectionState(
         phase: ConnectionPhase.connecting,
         baseUrl: defaultBackendBaseUrl,
       ) {
    _api.onEntryChanged = _acceptEntry;
    _api.onUnauthorized = (_) {
      unawaited(refreshAuthorization());
    };
  }

  final ApiClient _api;
  final BackendSettings _settings;
  final EntryKeyStore _keyStore;
  final Future<BackendAddress?> Function()? localEntryLoader;
  bool _localDeployment = false;
  int _generation = 0;
  int _credentialRevision = 0;
  bool _disposed = false;
  Future<bool>? _recovery;
  BackendConnectionState _state;

  BackendConnectionState get state => _state;
  int get credentialRevision => _credentialRevision;
  bool get isLocalDeployment => _localDeployment;
  Map<String, String> headersFor(Uri uri) => _api.headersFor(uri);
  Map<String, String> get websocketHeaders =>
      headersFor(websocketUri('/ws/state'));

  Future<void> initialize() async {
    final saved = await _settings.readBaseUrl();
    BackendAccess? access;
    try {
      access = await _keyStore.read();
    } catch (_) {
      /* A locked keychain must not prevent opening settings. */
    }
    await connect(
      saved == null || saved.trim().isEmpty ? defaultBackendBaseUrl : saved,
      localDeployment:
          (saved == null && localEntryLoader != null) ||
          (access?.baseUrl == saved && access?.localDeployment == true),
    );
  }

  Future<bool> connect(
    String value, {
    bool persist = false,
    bool? localDeployment,
  }) async {
    final generation = ++_generation;
    late final String baseUrl;
    String? key;
    try {
      final input = value.trim();
      final address = BackendAddress.parse(
        input.isEmpty ? defaultBackendBaseUrl : input,
      );
      baseUrl = address.baseUrl;
      key = address.entryKey;
    } on FormatException catch (error) {
      _setState(
        BackendConnectionState(
          phase: ConnectionPhase.disconnected,
          baseUrl: _state.baseUrl,
          message: error.message,
        ),
      );
      return false;
    }

    _localDeployment =
        localDeployment ??
        (!persist && baseUrl == _state.baseUrl && _localDeployment);

    _setState(
      BackendConnectionState(
        phase: ConnectionPhase.connecting,
        baseUrl: baseUrl,
      ),
    );

    try {
      final saved = await _keyStore.read();
      if (generation != _generation || _disposed) return false;
      // A manually entered address is a remote profile even when it happens
      // to use loopback (for example an SSH tunnel). Never reuse its local key.
      key ??=
          saved?.baseUrl == baseUrl &&
              (saved?.localDeployment != true || _localDeployment)
          ? saved?.key
          : null;
      if (key != null && !BackendAddress.validKey(key)) key = null;
      _configureEntry(baseUrl, key);
      var status = await _api.fetchSystemStatus(baseUrl);
      if (generation != _generation || _disposed) return false;
      if (!status.authorized && _localDeployment && localEntryLoader != null) {
        final local = await localEntryLoader!();
        if (generation != _generation || _disposed) return false;
        if (local != null && local.baseUrl == baseUrl) {
          _configureEntry(baseUrl, local.entryKey);
          status = await _api.fetchSystemStatus(baseUrl);
        }
      }
      if (generation != _generation || _disposed) return false;
      if (persist || _api.entryKey != key) await _persistAccess(baseUrl);
      if (!status.authorized) {
        _disconnect(baseUrl, const EntryAuthorizationException().toString());
        return false;
      }
      if (status.apiVersion != supportedApiVersion) {
        _setState(
          BackendConnectionState(
            phase: ConnectionPhase.incompatible,
            baseUrl: baseUrl,
            status: status,
            message: '需要 API v$supportedApiVersion，当前为 v${status.apiVersion}',
          ),
        );
        return false;
      }
      _setState(
        BackendConnectionState(
          phase: ConnectionPhase.connected,
          baseUrl: baseUrl,
          status: status,
          message: status.version == null ? null : '后端版本 ${status.version}',
        ),
      );
      return true;
    } on TimeoutException {
      if (generation != _generation || _disposed) return false;
      _disconnect(baseUrl, '连接超时，请检查地址和网络');
    } on EntryAuthorizationException catch (error) {
      if (generation != _generation || _disposed) return false;
      _disconnect(baseUrl, error.toString());
    } on ApiException catch (error) {
      if (generation != _generation || _disposed) return false;
      _disconnect(baseUrl, error.message);
    } on FormatException catch (error) {
      if (generation != _generation || _disposed) return false;
      _disconnect(baseUrl, '后端数据无效：${error.message}');
    } catch (_) {
      if (generation != _generation || _disposed) return false;
      _disconnect(baseUrl, '无法连接后端，请检查地址和服务状态');
    }
    return false;
  }

  void _configureEntry(String baseUrl, String? key) {
    if (_api.entryKey != key || _state.baseUrl != baseUrl) {
      _credentialRevision++;
    }
    _api.configureEntry(baseUrl, key);
  }

  Future<void> _persistAccess(String baseUrl) async {
    await _keyStore.write(
      BackendAccess(
        baseUrl: baseUrl,
        key: _api.entryKey,
        localDeployment: _localDeployment,
      ),
    );
    await _settings.writeBaseUrl(baseUrl);
  }

  Future<bool> connectLocalDeployment() async {
    try {
      final address = await localEntryLoader?.call();
      if (address == null) {
        _disconnect(_state.baseUrl, '无法读取本机部署，请确认 Termux 已初始化并授予运行命令权限');
        return false;
      }
      return await connect(
        address.entryKey == null
            ? address.baseUrl
            : '${address.baseUrl}/entry/${address.entryKey}',
        persist: true,
        localDeployment: true,
      );
    } catch (_) {
      _disconnect(_state.baseUrl, '无法读取本机入口，请检查 Termux 部署与运行命令权限');
      return false;
    }
  }

  Future<void> _acceptEntry(String baseUrl, Map<String, dynamic> entry) async {
    if (_disposed || baseUrl != _state.baseUrl) return;
    final key = entry['enabled'] == true ? entry['key'] as String? : null;
    if (entry['enabled'] == true &&
        (key == null || !BackendAddress.validKey(key))) {
      throw const ApiException('后端返回了无效安全入口');
    }
    _configureEntry(baseUrl, key);
    await _persistAccess(baseUrl);
    if (_disposed || baseUrl != _state.baseUrl) return;
    final old = _state.status;
    _setState(
      BackendConnectionState(
        phase: _state.phase,
        baseUrl: baseUrl,
        message: _state.message,
        status: old == null
            ? null
            : SystemStatus(
                apiVersion: old.apiVersion,
                spaVersion: old.spaVersion,
                version: old.version,
                capabilities: old.capabilities,
                securityEntryEnabled: entry['enabled'] == true,
                authorized: true,
              ),
      ),
    );
  }

  Future<Map<String, dynamic>> securityEntry({bool regenerate = false}) =>
      _api.securityEntry(_state.baseUrl, regenerate: regenerate);

  Future<bool> refreshAuthorization() {
    return _recovery ??= _refreshAuthorization().whenComplete(
      () => _recovery = null,
    );
  }

  Future<bool> _refreshAuthorization() async {
    final baseUrl = _state.baseUrl;
    final generation = _generation;
    try {
      await _api.waitForEntryChange();
      final status = await _api.fetchSystemStatus(baseUrl);
      if (_disposed || baseUrl != _state.baseUrl || generation != _generation) {
        return false;
      }
      if (status.authorized) return true;
      if (_localDeployment) {
        return await connect(baseUrl, localDeployment: true);
      }
      _disconnect(baseUrl, const EntryAuthorizationException().toString());
    } catch (_) {
      /* Normal transport failures use the existing retry path. */
    }
    return false;
  }

  Future<List<InstanceInfo>> fetchInstances() {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchInstances(_state.baseUrl);
  }

  Future<void> setInstanceRunning(String name, bool running) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.setInstanceRunning(_state.baseUrl, name, running);
  }

  Future<QueueInfo> fetchQueue(String name) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchQueue(_state.baseUrl, name);
  }

  Future<CalendarInfo> fetchCalendar({bool refresh = false}) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchCalendar(_state.baseUrl, refresh: refresh);
  }

  Future<List<LogFileRef>> fetchLogFiles() {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchLogFiles(_state.baseUrl);
  }

  Future<LogQueryResult> fetchLogs({
    required String date,
    String source = '',
    String level = 'info',
  }) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchLogs(
      _state.baseUrl,
      date: date,
      source: source,
      level: level,
    );
  }

  Uri logDownloadUri({required String date, required String source}) =>
      _api.logDownloadUri(_state.baseUrl, date: date, source: source);

  Future<List<int>> downloadLog({
    required String date,
    required String source,
  }) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.downloadLog(_state.baseUrl, date: date, source: source);
  }

  Future<UpdateInfo> fetchUpdateInfo() {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchUpdateInfo(_state.baseUrl);
  }

  Future<void> checkForUpdate() {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.checkForUpdate(_state.baseUrl);
  }

  Future<void> applyUpdate() {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.applyUpdate(_state.baseUrl);
  }

  Future<ScreenshotFrame?> fetchScreenshot(String name) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchScreenshot(_state.baseUrl, name);
  }

  Future<List<ScheduleTask>> fetchSchedule(String name) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchSchedule(_state.baseUrl, name);
  }

  Future<void> saveSchedule(String name, List<Map<String, dynamic>> changes) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.saveSchedule(_state.baseUrl, name, changes);
  }

  Future<void> resetSchedule(String name) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.resetSchedule(_state.baseUrl, name);
  }

  Future<SchemaInfo> fetchSchema(String name) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchSchema(_state.baseUrl, name);
  }

  Future<void> patchConfig(String name, String key, Object? value) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.patchConfig(_state.baseUrl, name, key, value);
  }

  Future<DeployInfo> fetchDeploy() {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.fetchDeployInfo(_state.baseUrl);
  }

  Future<Object?> patchDeploy(String key, Object? value) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.patchDeploy(_state.baseUrl, key, value);
  }

  Future<void> resetDeploy({String template = 'intl'}) {
    if (_state.phase != ConnectionPhase.connected) {
      return Future.error(const ApiException('后端未连接'));
    }
    return _api.resetDeploy(_state.baseUrl, template: template);
  }

  Uri avatarUri(String filename) => _api.endpoint(
    _state.baseUrl,
    '/avatars/${Uri.encodeComponent(filename)}',
  );

  Uri assetUri(String path) => _api.endpoint(_state.baseUrl, path);

  Uri websocketUri(String path) => _api.websocketUri(_state.baseUrl, path);

  Uri get webUiUri => _api.endpoint(
    _state.baseUrl,
    _api.entryKey == null ? '/app/' : '/entry/${_api.entryKey}',
  );

  void _disconnect(String baseUrl, String message) {
    _setState(
      BackendConnectionState(
        phase: ConnectionPhase.disconnected,
        baseUrl: baseUrl,
        message: message,
      ),
    );
  }

  void _setState(BackendConnectionState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _api.close();
    super.dispose();
  }
}
