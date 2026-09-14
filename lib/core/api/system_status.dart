class SystemStatus {
  const SystemStatus({
    required this.apiVersion,
    required this.spaVersion,
    required this.version,
    required this.capabilities,
    this.securityEntryEnabled = false,
    this.authorized = true,
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
      securityEntryEnabled:
          (json['security_entry'] as Map?)?['enabled'] == true,
      authorized: (json['security_entry'] as Map?)?['authorized'] != false,
      capabilities: rawCapabilities is Map<String, dynamic>
          ? Map.unmodifiable(rawCapabilities)
          : const {},
    );
  }

  final int apiVersion;
  final String? spaVersion;
  final String? version;
  final Map<String, dynamic> capabilities;
  final bool securityEntryEnabled;
  final bool authorized;
}
