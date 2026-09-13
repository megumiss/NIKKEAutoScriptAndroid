class SystemStatus {
  const SystemStatus({
    required this.apiVersion,
    required this.spaVersion,
    required this.version,
    required this.capabilities,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    final apiVersion = json['api_version'];
    if (apiVersion is! int) {
      throw const FormatException('缺少 api_version');
    }
    final rawCapabilities = json['capabilities'];
    return SystemStatus(
      apiVersion: apiVersion,
      spaVersion: json['spa_version']?.toString(),
      version: json['version']?.toString(),
      capabilities: rawCapabilities is Map<String, dynamic>
          ? Map.unmodifiable(rawCapabilities)
          : const {},
    );
  }

  final int apiVersion;
  final String? spaVersion;
  final String? version;
  final Map<String, dynamic> capabilities;
}
