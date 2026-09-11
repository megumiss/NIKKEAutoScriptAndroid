import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:nkas_mobile_preview/core/api/system_status.dart';
import 'package:nkas_mobile_preview/core/api/instance_info.dart';
import 'package:nkas_mobile_preview/core/api/queue_info.dart';
import 'package:nkas_mobile_preview/core/api/calendar_info.dart';
import 'package:nkas_mobile_preview/core/api/log_info.dart';
import 'package:nkas_mobile_preview/core/api/update_info.dart';
import 'package:nkas_mobile_preview/core/api/screenshot_frame.dart';
import 'package:nkas_mobile_preview/core/api/schedule_info.dart';
import 'package:nkas_mobile_preview/core/api/schema_info.dart';

class ApiClient {
  ApiClient({http.Client? client, this.timeout = const Duration(seconds: 5)})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static String normalizeBaseUrl(String value) {
    var input = value.trim();
    if (input.isEmpty) {
      throw const FormatException('请输入后端地址');
    }
    if (!input.contains('://')) {
      input = 'http://$input';
    }

    final uri = Uri.tryParse(input);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入有效的 HTTP 或 HTTPS 地址');
    }

    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: path).toString().replaceFirst(RegExp(r'/+$'), '');
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

  void close() => _client.close();
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
