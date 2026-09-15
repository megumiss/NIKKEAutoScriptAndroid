import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:nkas_mobile/core/platform/runtime_platform.dart';
import 'package:nkas_mobile/core/platform/native_control_settings.dart';
import 'package:nkas_mobile/core/api/backend_address.dart';

class InitConfigSource {
  const InitConfigSource({required this.label, required this.value});

  final String label;
  final String value;
}

/// Android 初始化（Termux 安装）使用的下载源与仓库配置，
/// 与原生 SettingsStore 的 SharedPreferences 保持一致。
class InitConfig {
  const InitConfig({
    required this.webUiUrl,
    required this.repository,
    required this.aptSource,
    required this.dockerImage,
    this.repositorySources = const [],
    this.aptSources = const [],
  });

  final String webUiUrl;
  final String repository;
  final String aptSource;
  final String dockerImage;
  final List<InitConfigSource> repositorySources;
  final List<InitConfigSource> aptSources;

  factory InitConfig.fromMap(Map<Object?, Object?> map) {
    List<InitConfigSource> sources(Object? raw) => raw is List
        ? [
            for (final item in raw)
              if (item is Map)
                InitConfigSource(
                  label: item['label'] as String? ?? '',
                  value: item['value'] as String? ?? '',
                ),
          ]
        : const [];
    return InitConfig(
      webUiUrl: map['webUiUrl'] as String? ?? '',
      repository: map['repository'] as String? ?? '',
      aptSource: map['aptSource'] as String? ?? '',
      dockerImage: map['dockerImage'] as String? ?? '',
      repositorySources: sources(map['repositorySources']),
      aptSources: sources(map['aptSources']),
    );
  }
}

class StarAuthorization {
  const StarAuthorization({
    required this.authorized,
    this.username,
    this.repository,
    this.expiresAt,
    this.error,
  });

  final bool authorized;
  final String? username;
  final String? repository;
  final int? expiresAt;
  final String? error;

  factory StarAuthorization.fromMap(Map<Object?, Object?> map) {
    return StarAuthorization(
      authorized: map['authorized'] == true,
      username: map['username'] as String?,
      repository: map['repository'] as String?,
      expiresAt: (map['expiresAt'] as num?)?.toInt(),
      error: map['error'] as String?,
    );
  }
}

class SetupStatus {
  const SetupStatus({
    required this.authorized,
    required this.termuxInstalled,
    required this.runCommandPermission,
    required this.wirelessDebug,
    required this.serial,
    this.termuxVersion,
    this.artifacts = const {},
    this.commandExitCode,
    this.connectResult = '',
    this.error,
  });

  final bool authorized;
  final bool termuxInstalled;
  final bool runCommandPermission;
  final bool wirelessDebug;
  final String serial;
  final String? termuxVersion;
  final Map<String, bool> artifacts;
  final int? commandExitCode;
  final String connectResult;
  final String? error;

  factory SetupStatus.fromMap(Map<Object?, Object?> map) {
    final rawArtifacts = map['artifacts'];
    return SetupStatus(
      authorized: map['authorized'] == true,
      termuxInstalled: map['termuxInstalled'] == true,
      runCommandPermission: map['runCommandPermission'] == true,
      wirelessDebug: map['wirelessDebug'] == true,
      serial: map['serial'] as String? ?? '',
      termuxVersion: map['termuxVersion'] as String?,
      artifacts: rawArtifacts is Map
          ? rawArtifacts.map(
              (key, value) => MapEntry(key.toString(), value == true),
            )
          : const {},
      commandExitCode: (map['commandExitCode'] as num?)?.toInt(),
      connectResult: map['adbConnect'] as String? ?? '',
      error: map['error'] as String?,
    );
  }

  bool get environmentReady =>
      authorized && termuxInstalled && runCommandPermission && wirelessDebug;

  bool get initialized => artifactsReady;

  bool get artifactsReady => const [
    'termux_setting',
    'adb_device',
    'tools',
    'source',
    'config',
    'container',
    'service',
  ].every((key) => artifacts[key] == true);
}

sealed class NkasPlatformEvent {
  const NkasPlatformEvent();
}

class StarAuthorizationEvent extends NkasPlatformEvent {
  const StarAuthorizationEvent(this.status);
  final StarAuthorization status;
}

class SetupOutputEvent extends NkasPlatformEvent {
  const SetupOutputEvent(this.output, {this.log = false, this.exitCode});
  final String output;
  final bool log;
  final int? exitCode;
}

class SetupStateEvent extends NkasPlatformEvent {
  const SetupStateEvent(this.state, this.message);
  final String state;
  final String? message;
}

class TermuxDownloadEvent extends NkasPlatformEvent {
  const TermuxDownloadEvent({this.progress = 0, this.message, this.error});
  final int progress;
  final String? message;
  final String? error;
}

class SetupSerialEvent extends NkasPlatformEvent {
  const SetupSerialEvent(this.serial);
  final String serial;
}

class SetupNoticeEvent extends NkasPlatformEvent {
  const SetupNoticeEvent(this.message);
  final String message;
}

class ScrcpyVideoEvent extends NkasPlatformEvent {
  const ScrcpyVideoEvent({
    required this.state,
    this.requestId,
    this.textureId,
    this.deviceName,
    this.codecId,
    this.width,
    this.height,
    this.error,
  });

  final String state;
  final String? requestId;
  final int? textureId;
  final String? deviceName;
  final int? codecId;
  final int? width;
  final int? height;
  final String? error;
}

class NativeNetworkEvent extends NkasPlatformEvent {
  const NativeNetworkEvent(this.state);
  final String state;
}

class TsnetStateEvent extends NkasPlatformEvent {
  const TsnetStateEvent(this.status);
  final TsnetStatus status;
}

class ScrcpyServerEvent extends NkasPlatformEvent {
  const ScrcpyServerEvent(this.state, {this.message, this.error});
  final String state;
  final String? message;
  final String? error;
}

class NativeScrcpyStart {
  const NativeScrcpyStart({
    required this.scid,
    this.command,
    this.deviceName,
    this.codecId,
    this.textureId,
    required this.video,
    required this.control,
  });

  final int scid;
  final String? command;
  final String? deviceName;
  final int? codecId;
  final int? textureId;
  final bool video;
  final bool control;

  factory NativeScrcpyStart.fromMap(Map<Object?, Object?> map) {
    return NativeScrcpyStart(
      scid: (map['scid'] as num?)?.toInt() ?? 0,
      command: map['command'] as String?,
      deviceName: map['deviceName'] as String?,
      codecId: (map['codecId'] as num?)?.toInt(),
      textureId: (map['textureId'] as num?)?.toInt(),
      video: map['video'] == true,
      control: map['control'] == true,
    );
  }
}

class NkasPlatform {
  NkasPlatform._() : _supportedOverride = null;

  @visibleForTesting
  NkasPlatform.testing({required Stream<NkasPlatformEvent> events})
    : _supportedOverride = true,
      _eventStream = events;

  final bool? _supportedOverride;

  static final NkasPlatform instance = NkasPlatform._();
  static const _channel = MethodChannel('com.megumiss.nkas/platform');
  static const _events = EventChannel('com.megumiss.nkas/platform_events');

  Stream<NkasPlatformEvent>? _eventStream;

  /// Native STAR, ADB, and scrcpy entry points are implemented on Android and
  /// iOS. Android-only setup methods keep their own platform guard below.
  bool get supported => _supportedOverride ?? (!kIsWeb && (isAndroid || isIOS));

  bool get _androidSupported => !kIsWeb && isAndroid;

  Stream<NkasPlatformEvent> get events => _eventStream ??= _events
      .receiveBroadcastStream()
      .where((value) => value is Map)
      .map((value) => _parseEvent(_map(value)));

  Future<StarAuthorization> starStatus() async {
    if (!supported) return const StarAuthorization(authorized: false);
    final value = await _channel.invokeMethod<Object?>('getStarStatus');
    return StarAuthorization.fromMap(_map(value));
  }

  Future<void> beginStarVerification() async {
    if (!supported) throw UnsupportedError('STAR 验证仅支持 Android 和 iOS');
    await _channel.invokeMethod<void>('beginStarVerification');
  }

  Future<SetupStatus> setupStatus() async {
    if (isIOS) {
      final star = await starStatus();
      final serial = await getSerial();
      return SetupStatus(
        authorized: star.authorized,
        termuxInstalled: false,
        runCommandPermission: false,
        wirelessDebug: false,
        serial: serial,
      );
    }
    if (!_androidSupported) {
      return const SetupStatus(
        authorized: false,
        termuxInstalled: false,
        runCommandPermission: false,
        wirelessDebug: false,
        serial: '',
      );
    }
    final value = await _channel.invokeMethod<Object?>('getSetupStatus');
    return SetupStatus.fromMap(_map(value));
  }

  Future<InitConfig?> initConfig() async {
    if (!_androidSupported) return null;
    return InitConfig.fromMap(
      _map(await _channel.invokeMethod<Object?>('getInitConfig')),
    );
  }

  Future<void> saveInitConfig({
    required String webUiUrl,
    required String repository,
    required String aptSource,
    required String dockerImage,
  }) async {
    if (!_androidSupported) throw UnsupportedError('初始化配置仅支持 Android');
    await _channel.invokeMethod<void>('saveInitConfig', <String, Object?>{
      'webUiUrl': webUiUrl,
      'repository': repository,
      'aptSource': aptSource,
      'dockerImage': dockerImage,
    });
  }

  Future<void> startSetup() async {
    if (!_androidSupported) throw UnsupportedError('初始化仅支持 Android');
    await _channel.invokeMethod<void>('startSetup');
  }

  Future<BackendAddress?> localBackendEntry() async {
    if (!_androidSupported) return null;
    final value = _map(
      await _channel.invokeMethod<Object?>('getLocalBackendEntry'),
    );
    final base = value['baseUrl'];
    if (base is! String) return null;
    final address = BackendAddress.parse(base);
    final key = value['key'];
    if (key != null && (key is! String || !BackendAddress.validKey(key))) {
      throw const FormatException('本机安全入口数据无效');
    }
    return BackendAddress(address.baseUrl, entryKey: key as String?);
  }

  Future<void> downloadTermux() async {
    if (!_androidSupported) throw UnsupportedError('Termux 仅支持 Android');
    await _channel.invokeMethod<void>('downloadTermux');
  }

  Future<void> requestRunCommandPermission() async {
    if (!_androidSupported) return;
    await _channel.invokeMethod<void>('requestRunCommandPermission');
  }

  Future<void> openAppSettings() async {
    if (!_androidSupported) return;
    await _channel.invokeMethod<void>('openAppSettings');
  }

  Future<void> openTermux() async {
    if (!_androidSupported) return;
    await _channel.invokeMethod<void>('openTermux');
  }

  Future<void> pairDevice({String code = '', String serial = ''}) async {
    if (!_androidSupported) throw UnsupportedError('无线调试配对仅支持 Android');
    await _channel.invokeMethod<void>('pairDevice', <String, Object?>{
      'code': code,
      'serial': serial,
    });
  }

  Future<void> openWirelessSettings() async {
    if (!_androidSupported) return;
    await _channel.invokeMethod<void>('openWirelessSettings');
  }

  Future<String> getAppLog() async {
    if (!_androidSupported) return '';
    return await _channel.invokeMethod<String>('getAppLog') ?? '';
  }

  Future<String> getSerial() async {
    if (!supported) return '';
    return await _channel.invokeMethod<String>('getSerial') ?? '';
  }

  Future<void> setSerial(String serial) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('setSerial', <String, Object?>{
      'serial': serial,
    });
  }

  Future<String> getNkasSerial() async {
    if (!_androidSupported) return '';
    return await _channel.invokeMethod<String>('getNkasSerial') ?? '';
  }

  Future<void> setNkasSerial(String serial) async {
    if (!_androidSupported) return;
    await _channel.invokeMethod<void>('setNkasSerial', <String, Object?>{
      'serial': serial,
    });
  }

  Future<Map<Object?, Object?>> nativeAdbConnect(
    String endpoint, {
    bool useTailscale = false,
  }) async {
    if (!supported) throw UnsupportedError('原生 ADB 仅支持 Android 和 iOS');
    final value = await _channel.invokeMethod<Object?>('nativeAdbConnect', {
      'endpoint': endpoint,
      'useTailscale': useTailscale,
    });
    return _map(value);
  }

  Future<String> nativeAdbShell(String command) async {
    if (!supported) throw UnsupportedError('原生 ADB 仅支持 Android 和 iOS');
    return await _channel.invokeMethod<String>('nativeAdbShell', {
          'command': command,
        }) ??
        '';
  }

  Future<void> nativeAdbPush(
    Uint8List data,
    String remotePath, {
    int mode = 420,
  }) async {
    if (!supported) throw UnsupportedError('原生 ADB 仅支持 Android 和 iOS');
    await _channel.invokeMethod<void>('nativeAdbPush', {
      'data': data,
      'remotePath': remotePath,
      'mode': mode,
    });
  }

  Future<Uint8List> nativeAdbPull(String remotePath) async {
    if (!supported) throw UnsupportedError('原生 ADB 仅支持 Android 和 iOS');
    final value = await _channel.invokeMethod<Object?>('nativeAdbPull', {
      'remotePath': remotePath,
    });
    if (value is Uint8List) return value;
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return Uint8List(0);
  }

  Future<void> nativeAdbClose() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('nativeAdbClose');
  }

  Future<NativeControlSettings> nativeControlSettings() async {
    if (!supported) return const NativeControlSettings();
    return NativeControlSettings.fromMap(
      _map(await _channel.invokeMethod<Object?>('getNativeControlSettings')),
    );
  }

  Future<void> saveNativeControlSettings(NativeControlSettings settings) async {
    if (!supported) throw UnsupportedError('原生控制仅支持 Android 和 iOS');
    await _channel.invokeMethod<void>(
      'saveNativeControlSettings',
      settings.toMap(),
    );
  }

  Future<TsnetStatus> tsnetStatus() async {
    if (!supported) return const TsnetStatus();
    return TsnetStatus.fromMap(
      _map(await _channel.invokeMethod<Object?>('tsnetStatus')),
    );
  }

  Future<TsnetStatus> tsnetConfigure(String authKey) async =>
      TsnetStatus.fromMap(
        _map(
          await _channel.invokeMethod<Object?>('tsnetConfigure', {
            'authKey': authKey,
          }),
        ),
      );

  Future<TsnetStatus> tsnetConnect() async => TsnetStatus.fromMap(
    _map(await _channel.invokeMethod<Object?>('tsnetConnect')),
  );

  Future<Map<Object?, Object?>> tsnetStartForward(
    String endpoint, {
    int localPort = 0,
  }) async => _map(
    await _channel.invokeMethod<Object?>('tsnetStartForward', {
      'endpoint': endpoint,
      'localPort': localPort,
    }),
  );

  Future<void> tsnetStopForward(String id) async =>
      _channel.invokeMethod<void>('tsnetStopForward', {'id': id});
  Future<void> tsnetStopAll() async =>
      _channel.invokeMethod<void>('tsnetStopAll');
  Future<void> tsnetClose() async => _channel.invokeMethod<void>('tsnetClose');
  Future<void> tsnetClearState() async =>
      _channel.invokeMethod<void>('tsnetClearState');

  Future<bool> initialNoticeShown() async {
    if (!_androidSupported) return false;
    return await _channel.invokeMethod<bool>('getInitialNoticeShown') ?? false;
  }

  Future<void> setInitialNoticeShown() async {
    if (!_androidSupported) return;
    await _channel.invokeMethod<void>('setInitialNoticeShown');
  }

  Future<NativeScrcpyStart> nativeScrcpyStart(
    String endpoint, {
    bool video = true,
    bool control = true,
    int maxSize = 0,
    int videoBitRate = 0,
    String videoCodec = 'h264',
    String? mode,
    bool? useTailscale,
    String? requestId,
  }) async {
    if (!supported) throw UnsupportedError('原生 scrcpy 仅支持 Android 和 iOS');
    final value = await _channel.invokeMethod<Object?>('nativeScrcpyStart', {
      'endpoint': endpoint,
      'video': video,
      'control': control,
      'maxSize': maxSize,
      'videoBitRate': videoBitRate,
      'videoCodec': videoCodec,
      'mode': ?mode,
      'useTailscale': ?useTailscale,
      'requestId': ?requestId,
    });
    return NativeScrcpyStart.fromMap(_map(value));
  }

  Future<void> nativeScrcpyStop({String? requestId}) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('nativeScrcpyStop', {
      'requestId': ?requestId,
    });
  }

  Future<void> nativeScrcpyBack({int action = 0, String? requestId}) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('nativeScrcpyBack', {
      'action': action,
      'requestId': ?requestId,
    });
  }

  Future<void> nativeScrcpyText(String text, {String? requestId}) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('nativeScrcpyText', {
      'text': text,
      'requestId': ?requestId,
    });
  }

  Future<void> nativeScrcpyKeycode({
    required int action,
    required int keycode,
    int repeat = 0,
    int metaState = 0,
    String? requestId,
  }) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('nativeScrcpyKeycode', {
      'action': action,
      'keycode': keycode,
      'repeat': repeat,
      'metaState': metaState,
      'requestId': ?requestId,
    });
  }

  Future<void> nativeScrcpyTouch({
    required int action,
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    int pointerId = 0,
    double pressure = 1,
    int actionButton = 0,
    int buttons = 0,
    String? requestId,
  }) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('nativeScrcpyTouch', {
      'action': action,
      'pointerId': pointerId,
      'x': x,
      'y': y,
      'screenWidth': screenWidth,
      'screenHeight': screenHeight,
      'pressure': pressure,
      'actionButton': actionButton,
      'buttons': buttons,
      'requestId': ?requestId,
    });
  }

  NkasPlatformEvent _parseEvent(Map<Object?, Object?> value) {
    switch (value['type']) {
      case 'star':
        return StarAuthorizationEvent(StarAuthorization.fromMap(value));
      case 'setupLog':
        return SetupOutputEvent(value['output'] as String? ?? '', log: true);
      case 'setupCommand':
        return SetupOutputEvent(
          value['output'] as String? ?? '',
          exitCode: (value['exitCode'] as num?)?.toInt(),
        );
      case 'setup':
        return SetupStateEvent(
          value['state'] as String? ?? 'idle',
          value['message'] as String?,
        );
      case 'termuxDownload':
        return TermuxDownloadEvent(
          progress: (value['progress'] as num?)?.toInt() ?? 0,
          message: value['message'] as String?,
          error: value['error'] as String?,
        );
      case 'setupSerial':
        return SetupSerialEvent(value['serial'] as String? ?? '');
      case 'setupNotice':
        return SetupNoticeEvent(value['message'] as String? ?? '');
      case 'scrcpyVideo':
        return ScrcpyVideoEvent(
          state: value['state'] as String? ?? 'unknown',
          requestId: value['requestId'] as String?,
          textureId: (value['textureId'] as num?)?.toInt(),
          deviceName: value['deviceName'] as String?,
          codecId: (value['codecId'] as num?)?.toInt(),
          width: (value['width'] as num?)?.toInt(),
          height: (value['height'] as num?)?.toInt(),
          error: value['error'] as String?,
        );
      case 'nativeNetwork':
        return NativeNetworkEvent(value['state'] as String? ?? 'unknown');
      case 'tsnet':
        return TsnetStateEvent(TsnetStatus.fromMap(value));
      case 'scrcpyServer':
        return ScrcpyServerEvent(
          value['state'] as String? ?? 'unknown',
          message: value['message'] as String?,
          error: value['error'] as String?,
        );
      default:
        return const SetupStateEvent('idle', null);
    }
  }

  static Map<Object?, Object?> _map(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    if (value is Map) return value.cast<Object?, Object?>();
    return const {};
  }
}
