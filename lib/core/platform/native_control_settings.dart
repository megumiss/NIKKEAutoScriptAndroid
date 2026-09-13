enum NativeControlMode { remoteAdb, localVirtualDisplay }

class NativeControlSettings {
  const NativeControlSettings({
    this.mode = NativeControlMode.remoteAdb,
    this.endpoint = '',
    this.tailscaleEnabled = false,
    this.hostname = 'nkas-mobile',
  });

  final NativeControlMode mode;
  final String endpoint;
  final bool tailscaleEnabled;
  final String hostname;
  String get modeName => mode == NativeControlMode.remoteAdb
      ? 'remote_adb'
      : 'local_virtual_display';

  factory NativeControlSettings.fromMap(Map<Object?, Object?> value) =>
      NativeControlSettings(
        mode: value['mode'] == 'local_virtual_display'
            ? NativeControlMode.localVirtualDisplay
            : NativeControlMode.remoteAdb,
        endpoint: value['endpoint'] as String? ?? '',
        tailscaleEnabled: value['tailscaleEnabled'] == true,
        hostname: value['hostname'] as String? ?? 'nkas-mobile',
      );

  Map<String, Object> toMap() => {
    'mode': modeName,
    'endpoint': endpoint,
    'tailscaleEnabled': tailscaleEnabled,
    'hostname': hostname,
  };
}

class TsnetStatus {
  const TsnetStatus({
    this.phase = 'new',
    this.addresses = const [],
    this.forwardCount = 0,
    this.hasPersistedLogin = false,
    this.error = '',
  });
  final String phase;
  final List<String> addresses;
  final int forwardCount;
  final bool hasPersistedLogin;
  final String error;

  factory TsnetStatus.fromMap(Map<Object?, Object?> value) => TsnetStatus(
    phase: value['phase'] as String? ?? 'new',
    addresses:
        (value['addresses'] as List?)?.whereType<String>().toList() ?? const [],
    forwardCount: (value['forwardCount'] as num?)?.toInt() ?? 0,
    hasPersistedLogin: value['hasPersistedLogin'] == true,
    error: value['error'] as String? ?? '',
  );
}
