class BackendAddress {
  const BackendAddress(this.baseUrl, {this.entryKey});

  final String baseUrl;
  final String? entryKey;

  static bool validKey(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);

  factory BackendAddress.parse(String value) {
    var input = value.trim();
    if (input.isEmpty) throw const FormatException('请输入后端地址');
    if (!input.contains('://')) input = 'http://$input';
    final uri = Uri.tryParse(input);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('请输入有效的 HTTP 或 HTTPS 地址，不要包含查询参数或账号密码');
    }
    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    String? key;
    final match = RegExp(r'/entry/([^/]+)$').firstMatch(path);
    if (match != null) {
      key = match.group(1)!;
      if (!validKey(key)) throw const FormatException('安全入口不完整，请复制部署页提供的完整入口');
      path = path.substring(0, match.start);
    } else if (uri.pathSegments.contains('entry')) {
      throw const FormatException('安全入口不完整，请复制部署页提供的完整入口');
    }
    return BackendAddress(
      uri.replace(path: path).toString().replaceFirst(RegExp(r'/+$'), ''),
      entryKey: key,
    );
  }
}

class EntryAuthorizationException implements Exception {
  const EntryAuthorizationException();
  @override
  String toString() => '安全入口已开启或已更新，请填写最新的完整入口地址';
}
