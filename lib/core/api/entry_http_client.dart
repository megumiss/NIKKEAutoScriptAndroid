import 'package:http/http.dart' as http;
import 'package:nkas_mobile/core/api/backend_address.dart';

class EntryHttpClient extends http.BaseClient {
  EntryHttpClient(this.inner);
  final http.Client inner;
  Uri? _backend;
  String? _key;
  void Function(Uri)? onUnauthorized;

  String? get key => _key;
  void configure(String baseUrl, String? key) {
    _backend = Uri.parse(baseUrl);
    _key = key;
  }

  Map<String, String> headersFor(Uri uri) {
    final base = _backend;
    if (base == null || _key == null) return const {};
    final scheme = uri.scheme == 'ws'
        ? 'http'
        : uri.scheme == 'wss'
        ? 'https'
        : uri.scheme;
    final httpUri = uri.replace(scheme: scheme).normalizePath();
    if (scheme != base.scheme ||
        uri.host != base.host ||
        httpUri.port != base.port ||
        !httpUri.path.startsWith('${base.path}/')) {
      return const {};
    }
    return {'Authorization': 'Bearer $_key'};
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = headersFor(request.url);
    request.headers.addAll(headers);
    // Never forward a key through an HTTP redirect (including another path
    // on the same host that belongs to a different reverse-proxied service).
    if (headers.isNotEmpty) request.followRedirects = false;
    final response = await inner.send(request);
    if (response.statusCode == 401) {
      await response.stream.drain<void>();
      onUnauthorized?.call(request.url);
      throw const EntryAuthorizationException();
    }
    return response;
  }

  @override
  void close() => inner.close();
}
