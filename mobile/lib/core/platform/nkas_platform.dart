import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:nkas_mobile/core/platform/runtime_platform.dart';

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
  const SetupOutputEvent(this.output, {this.log = false});
  final String output;
  final bool log;
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

class NkasPlatform {
  NkasPlatform._();

  static final NkasPlatform instance = NkasPlatform._();
  static const _channel = MethodChannel('com.megumiss.nkas/platform');
  static const _events = EventChannel('com.megumiss.nkas/platform_events');

  Stream<NkasPlatformEvent>? _eventStream;

  /// Native STAR verification is implemented on Android and iOS. Android-only
  /// setup methods keep their own platform guard below.
  bool get supported => !kIsWeb && (isAndroid || isIOS);

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
      return SetupStatus(
        authorized: star.authorized,
        termuxInstalled: false,
        runCommandPermission: false,
        wirelessDebug: false,
        serial: '',
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

  Future<void> startSetup() async {
    if (!_androidSupported) throw UnsupportedError('初始化仅支持 Android');
    await _channel.invokeMethod<void>('startSetup');
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
    if (!_androidSupported) return '';
    return await _channel.invokeMethod<String>('getSerial') ?? '';
  }

  Future<void> setSerial(String serial) async {
    if (!_androidSupported) return;
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

  Future<bool> initialNoticeShown() async {
    if (!_androidSupported) return false;
    return await _channel.invokeMethod<bool>('getInitialNoticeShown') ?? false;
  }

  Future<void> setInitialNoticeShown() async {
    if (!_androidSupported) return;
    await _channel.invokeMethod<void>('setInitialNoticeShown');
  }

  NkasPlatformEvent _parseEvent(Map<Object?, Object?> value) {
    switch (value['type']) {
      case 'star':
        return StarAuthorizationEvent(StarAuthorization.fromMap(value));
      case 'setupLog':
        return SetupOutputEvent(value['output'] as String? ?? '', log: true);
      case 'setupCommand':
        return SetupOutputEvent(value['output'] as String? ?? '');
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
