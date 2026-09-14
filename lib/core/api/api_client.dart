import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nkas_mobile/core/api/backend_address.dart';
import 'package:nkas_mobile/core/api/entry_http_client.dart';

import 'package:nkas_mobile/core/api/system_status.dart';
import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/queue_info.dart';
import 'package:nkas_mobile/core/api/calendar_info.dart';
import 'package:nkas_mobile/core/api/log_info.dart';
import 'package:nkas_mobile/core/api/update_info.dart';
import 'package:nkas_mobile/core/api/screenshot_frame.dart';
import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/api/schema_info.dart';
import 'package:nkas_mobile/core/api/deploy_info.dart';

class ApiClient {
  ApiClient({http.Client? client, this.timeout = const Duration(seconds: 5)})
    : _client = EntryHttpClient(client ?? http.Client());

  final EntryHttpClient _client;
  final Duration timeout;
  Future<void>? _entryChange;
  Future<void> waitForEntryChange() async => await _entryChange;

  Future<T> _withEntryChange<T>(Future<T> Function() action) async {
    final previous = _entryChange;
    final done = Completer<void>();
    _entryChange = done.future;
    try {
      await previous;
      return await action();
    } finally {
      done.complete();
      if (identical(_entryChange, done.future)) _entryChange = null;
    }
  }

  Future<void> Function(String baseUrl, Map<String, dynamic> entry)?
  onEntryChanged;
  set onUnauthorized(void Function(Uri)? value) =>
      _client.onUnauthorized = value;
  void configureEntry(String baseUrl, String? key) =>
      _client.configure(baseUrl, key);
  String? get entryKey => _client.key;
  Map<String, String> headersFor(Uri uri) => _client.headersFor(uri);

  static String normalizeBaseUrl(String value) {
    return BackendAddress.parse(value).baseUrl;
  }

  Uri endpoint(String baseUrl, String path) {
    final normalized = normalizeBaseUrl(baseUrl);
    return Uri.parse(
      '$normalized/',
    ).resolve(path.replaceFirst(RegExp(r'^/+'), ''));
  }

  Uri websocketUri(String baseUrl, String path) {
    final uri = endpoint(baseUrl, path);
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws');
  }

  Future<SystemStatus> fetchSystemStatus(String baseUrl) async {
    final response = await _client
        .get(endpoint(baseUrl, '/api/system/status'))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException('后端返回了无效数据');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('后端返回了无效数据');
    }
    return SystemStatus.fromJson(decoded);
  }

  Future<List<InstanceInfo>> fetchInstances(String baseUrl) async {
    final response = await _client
        .get(endpoint(baseUrl, '/api/instances'))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException('后端返回了无效实例数据');
    }
    if (decoded is! List) {
      throw const ApiException('后端返回了无效实例数据');
    }
    try {
      return decoded
          .map((item) => InstanceInfo.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException {
      throw const ApiException('后端返回了无效实例数据');
    } on TypeError {
      throw const ApiException('后端返回了无效实例数据');
    }
  }

  Future<void> setInstanceRunning(
    String baseUrl,
    String name,
    bool running,
  ) async {
    final response = await _client
        .post(
          endpoint(
            baseUrl,
            '/api/${Uri.encodeComponent(name)}/${running ? 'start' : 'stop'}',
          ),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
  }

  Future<QueueInfo> fetchQueue(String baseUrl, String name) async {
    final response = await _client
        .get(endpoint(baseUrl, '/api/${Uri.encodeComponent(name)}/queue'))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return QueueInfo.fromJson(decoded);
    } on FormatException {
      throw const ApiException('后端返回了无效队列数据');
    } on TypeError {
      throw const ApiException('后端返回了无效队列数据');
    }
  }

  Future<CalendarInfo> fetchCalendar(
    String baseUrl, {
    bool refresh = false,
  }) async {
    final uri = endpoint(baseUrl, '/api/calendar').replace(
      queryParameters: {'language': 'zh-CN', if (refresh) 'refresh': '1'},
    );
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return CalendarInfo.fromJson(decoded);
    } on FormatException {
      throw const ApiException('后端返回了无效活动数据');
    }
  }

  Future<List<LogFileRef>> fetchLogFiles(String baseUrl) async {
    final response = await _client
        .get(endpoint(baseUrl, '/api/system/logs/files'))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['files'] is! List) {
        throw const FormatException();
      }
      return (decoded['files'] as List)
          .whereType<Map<String, dynamic>>()
          .map(LogFileRef.fromJson)
          .where((file) => file.date.isNotEmpty && file.source.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      throw const ApiException('后端返回了无效日志文件数据');
    }
  }

  Future<LogQueryResult> fetchLogs(
    String baseUrl, {
    required String date,
    String source = '',
    String level = 'info',
    int limit = 500,
  }) async {
    final uri = endpoint(baseUrl, '/api/system/logs').replace(
      queryParameters: {
        'date': date,
        'source': source,
        'level': level,
        'limit': '$limit',
      },
    );
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return LogQueryResult.fromJson(decoded);
    } on FormatException {
      throw const ApiException('后端返回了无效日志数据');
    }
  }

  Uri logDownloadUri(
    String baseUrl, {
    required String date,
    required String source,
  }) => endpoint(
    baseUrl,
    '/api/system/logs/download',
  ).replace(queryParameters: {'date': date, 'source': source});

  Future<List<int>> downloadLog(
    String baseUrl, {
    required String date,
    required String source,
  }) async {
    final response = await _client
        .get(logDownloadUri(baseUrl, date: date, source: source))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<UpdateInfo> fetchUpdateInfo(String baseUrl) async {
    final response = await _client
        .get(endpoint(baseUrl, '/api/system/update'))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return UpdateInfo.fromJson(decoded);
    } on FormatException {
      throw const ApiException('后端返回了无效更新状态');
    }
  }

  Future<void> checkForUpdate(String baseUrl) async {
    await _postUpdateAction(baseUrl, '/api/update/check');
  }

  Future<void> applyUpdate(String baseUrl) async {
    await _postUpdateAction(baseUrl, '/api/update');
  }

  Future<void> _postUpdateAction(String baseUrl, String path) async {
    final response = await _client
        .post(endpoint(baseUrl, path))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
  }

  Future<ScreenshotFrame?> fetchScreenshot(String baseUrl, String name) async {
    final response = await _client
        .get(endpoint(baseUrl, '/api/${Uri.encodeComponent(name)}/screenshot'))
        .timeout(timeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    return ScreenshotFrame(
      bytes: response.bodyBytes,
      capturedAt: double.tryParse(response.headers['x-captured-at'] ?? ''),
    );
  }

  Future<List<ScheduleTask>> fetchSchedule(String baseUrl, String name) async {
    final response = await _client
        .get(endpoint(baseUrl, '/api/${Uri.encodeComponent(name)}/schedule'))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['tasks'] is! List) {
        throw const FormatException();
      }
      return (decoded['tasks'] as List)
          .whereType<Map<String, dynamic>>()
          .map(ScheduleTask.fromJson)
          .where((task) => task.command.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      throw const ApiException('后端返回了无效调度数据');
    }
  }

  Future<void> saveSchedule(
    String baseUrl,
    String name,
    List<Map<String, dynamic>> changes,
  ) async {
    final response = await _client
        .post(
          endpoint(baseUrl, '/api/${Uri.encodeComponent(name)}/schedule/save'),
          body: jsonEncode({'changes': changes}),
          headers: {'content-type': 'application/json'},
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
  }

  Future<void> resetSchedule(String baseUrl, String name) async {
    final response = await _client
        .post(
          endpoint(baseUrl, '/api/${Uri.encodeComponent(name)}/schedule/reset'),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
  }

  Future<SchemaInfo> fetchSchema(String baseUrl, String name) async {
    final response = await _client
        .get(endpoint(baseUrl, '/api/${Uri.encodeComponent(name)}/schema'))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return SchemaInfo.fromJson(decoded);
    } on FormatException {
      throw const ApiException('后端返回了无效任务配置结构');
    }
  }

  Future<void> patchConfig(
    String baseUrl,
    String name,
    String key,
    Object? value,
  ) async {
    final response = await _client
        .patch(
          endpoint(baseUrl, '/api/${Uri.encodeComponent(name)}/config'),
          body: jsonEncode({'key': key, 'value': value}),
          headers: {'content-type': 'application/json'},
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
  }

  Future<DeployInfo> fetchDeployInfo(String baseUrl) async {
    final response = await _client
        .get(endpoint(baseUrl, '/api/system/deploy'))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return DeployInfo.fromJson(decoded);
    } on FormatException {
      throw const ApiException('后端返回了无效部署配置');
    }
  }

  Future<Object?> patchDeploy(String baseUrl, String key, Object? value) =>
      key == 'SecurityEntryEnabled'
      ? _withEntryChange(() => _patchDeploy(baseUrl, key, value))
      : _patchDeploy(baseUrl, key, value);

  Future<Object?> _patchDeploy(
    String baseUrl,
    String key,
    Object? value,
  ) async {
    final response = await _client
        .patch(
          endpoint(baseUrl, '/api/system/deploy'),
          body: jsonEncode({'key': key, 'value': value}),
          headers: {'content-type': 'application/json'},
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        decoded = null;
      }
      final message = decoded is Map<String, dynamic>
          ? decoded['message']?.toString()
          : null;
      throw ApiException(
        message?.isNotEmpty == true
            ? message!
            : '后端返回 HTTP ${response.statusCode}',
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (decoded['security_entry'] is Map<String, dynamic>) {
        await onEntryChanged?.call(
          baseUrl,
          decoded['security_entry'] as Map<String, dynamic>,
        );
      }
      return decoded['value'];
    } on FormatException {
      throw const ApiException('后端返回了无效部署数据');
    }
  }

  Future<void> resetDeploy(String baseUrl, {String template = 'intl'}) async {
    final response = await _client
        .post(
          endpoint(baseUrl, '/api/system/deploy/reset'),
          body: jsonEncode({'template': template}),
          headers: {'content-type': 'application/json'},
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> securityEntry(
    String baseUrl, {
    bool regenerate = false,
  }) => regenerate
      ? _withEntryChange(() => _securityEntry(baseUrl, regenerate: true))
      : _securityEntry(baseUrl);

  Future<Map<String, dynamic>> _securityEntry(
    String baseUrl, {
    bool regenerate = false,
  }) async {
    final uri = endpoint(
      baseUrl,
      regenerate ? '/api/security/entry/regenerate' : '/api/security/entry',
    );
    final response = await (regenerate ? _client.post(uri) : _client.get(uri))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw ApiException('后端返回 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['security_entry'] is! Map<String, dynamic>) {
      throw const ApiException('后端返回了无效安全入口数据');
    }
    final entry = decoded['security_entry'] as Map<String, dynamic>;
    await onEntryChanged?.call(baseUrl, entry);
    return entry;
  }

  void close() => _client.close();
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
