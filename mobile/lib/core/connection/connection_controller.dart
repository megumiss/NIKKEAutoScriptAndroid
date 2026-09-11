import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:nkas_mobile/core/api/api_client.dart';
import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/queue_info.dart';
import 'package:nkas_mobile/core/api/calendar_info.dart';
import 'package:nkas_mobile/core/api/log_info.dart';
import 'package:nkas_mobile/core/api/update_info.dart';
import 'package:nkas_mobile/core/api/screenshot_frame.dart';
import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/api/schema_info.dart';
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
  }) : _api = api,
       _settings = settings,
       _state = const BackendConnectionState(
         phase: ConnectionPhase.connecting,
         baseUrl: defaultBackendBaseUrl,
       );

  final ApiClient _api;
  final BackendSettings _settings;
  BackendConnectionState _state;

  BackendConnectionState get state => _state;

  Future<void> initialize() async {
    final saved = await _settings.readBaseUrl();
    await connect(saved ?? defaultBackendBaseUrl);
  }

  Future<bool> connect(String value, {bool persist = false}) async {
    late final String baseUrl;
    try {
      baseUrl = ApiClient.normalizeBaseUrl(value);
    } on FormatException catch (error) {
      _setState(
        BackendConnectionState(
          phase: ConnectionPhase.disconnected,
          baseUrl: value.trim(),
          message: error.message,
        ),
      );
      return false;
    }

    _setState(
      BackendConnectionState(
        phase: ConnectionPhase.connecting,
        baseUrl: baseUrl,
      ),
    );

    try {
      final status = await _api.fetchSystemStatus(baseUrl);
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
      if (persist) {
        await _settings.writeBaseUrl(baseUrl);
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
      _disconnect(baseUrl, '连接超时，请检查地址和网络');
    } on ApiException catch (error) {
      _disconnect(baseUrl, error.message);
    } on FormatException catch (error) {
      _disconnect(baseUrl, '后端数据无效：${error.message}');
    } catch (_) {
      _disconnect(baseUrl, '无法连接后端，请检查地址和服务状态');
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

  Uri avatarUri(String filename) => _api.endpoint(
    _state.baseUrl,
    '/avatars/${Uri.encodeComponent(filename)}',
  );

  Uri assetUri(String path) => _api.endpoint(_state.baseUrl, path);

  Uri websocketUri(String path) => _api.websocketUri(_state.baseUrl, path);

  Uri get webUiUri => _api.endpoint(_state.baseUrl, '/app/');

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
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }
}
