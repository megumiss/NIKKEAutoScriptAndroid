enum NativeControlMode { remoteAdb, localVirtualDisplay }

/// 从实例配置 JSON 中取后端配置的 ADB Serial；空值或 "auto" 不可直连，返回 null
String? backendSerialOf(Map<String, dynamic> config) {
  final emulator = config['Emulator'];
  if (emulator is! Map) return null;
  final group = emulator['Emulator'];
  if (group is! Map) return null;
  final serial = group['Serial']?.toString().trim() ?? '';
  return serial.isEmpty || serial == 'auto' ? null : serial;
}

class NativeControlSettings {
  const NativeControlSettings({
    this.mode = NativeControlMode.remoteAdb,
    this.endpoint = '',
    this.tailscaleEnabled = false,
    this.hostname = 'nkas-mobile',
    this.endpoints = const {},
  });

  final NativeControlMode mode;
  final String endpoint;
  final bool tailscaleEnabled;
  final String hostname;

  /// 每个实例单独覆盖的控制地址（实例名 → 地址），优先于后端 Serial
  final Map<String, String> endpoints;
  String get modeName => mode == NativeControlMode.remoteAdb
      ? 'remote_adb'
      : 'local_virtual_display';

  /// 生效控制地址：实例覆盖 → 后端 Serial；都为空返回空串。
  /// 本机手填的固定地址（endpoint）不参与多实例解析，
  /// 仅在后端实例列表不可用时由调用方兜底，避免多个实例共用同一地址
  String endpointFor(String instance, {String? backendSerial}) {
    final override = endpoints[instance]?.trim() ?? '';
    if (override.isNotEmpty) return override;
    return backendSerial?.trim() ?? '';
  }

  factory NativeControlSettings.fromMap(Map<Object?, Object?> value) =>
      NativeControlSettings(
        mode: value['mode'] == 'local_virtual_display'
            ? NativeControlMode.localVirtualDisplay
            : NativeControlMode.remoteAdb,
        endpoint: value['endpoint'] as String? ?? '',
        tailscaleEnabled: value['tailscaleEnabled'] == true,
        hostname: value['hostname'] as String? ?? 'nkas-mobile',
        endpoints:
            (value['endpoints'] as Map?)?.map(
              (key, item) => MapEntry(key.toString(), item.toString()),
            ) ??
            const {},
      );

  Map<String, Object> toMap() => {
    'mode': modeName,
    'endpoint': endpoint,
    'tailscaleEnabled': tailscaleEnabled,
    'hostname': hostname,
    'endpoints': endpoints,
  };
}

class TsnetStatus {
  const TsnetStatus({
    this.phase = 'new',
    this.hostname = '',
    this.addresses = const [],
    this.magicDNS = '',
    this.forwardCount = 0,
    this.hasPersistedLogin = false,
    this.error = '',
  });
  final String phase;
  final String hostname;
  final List<String> addresses;
  final String magicDNS;
  final int forwardCount;
  final bool hasPersistedLogin;
  final String error;

  factory TsnetStatus.fromMap(Map<Object?, Object?> value) => TsnetStatus(
    phase: value['phase'] as String? ?? 'new',
    hostname: value['hostname'] as String? ?? '',
    addresses:
        (value['addresses'] as List?)?.whereType<String>().toList() ?? const [],
    magicDNS: value['magicDNS'] as String? ?? '',
    forwardCount: (value['forwardCount'] as num?)?.toInt() ?? 0,
    hasPersistedLogin: value['hasPersistedLogin'] == true,
    error: value['error'] as String? ?? '',
  );
}
