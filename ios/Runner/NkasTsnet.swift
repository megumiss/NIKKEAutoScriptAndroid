import Foundation
import NkasTsnet

final class NkasControlSettings {
  private let defaults = UserDefaults.standard
  var endpoint: String { defaults.string(forKey: "nkas_control_endpoint") ?? defaults.string(forKey: "nkas_serial") ?? "" }
  var hostname: String { defaults.string(forKey: "nkas_tsnet_hostname") ?? "nkas-ios" }
  var tailscaleEnabled: Bool { defaults.bool(forKey: "nkas_tsnet_enabled") }
  var endpoints: [String: String] { defaults.dictionary(forKey: "nkas_control_endpoints") as? [String: String] ?? [:] }

  func snapshot() -> [String: Any] {
    ["mode": "remote_adb", "endpoint": endpoint, "hostname": hostname, "tailscaleEnabled": tailscaleEnabled,
     "endpoints": endpoints]
  }

  func save(_ values: [String: Any]) throws -> [String: Any] {
    guard (values["mode"] as? String ?? "remote_adb") == "remote_adb" else {
      throw NkasIosAdbError.protocolError("iOS 仅支持远程 Android 控制")
    }
    let endpoint = (values["endpoint"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !endpoint.isEmpty { _ = try NkasIosAdbEndpoint(endpoint) }
    let hostname = (values["hostname"] as? String ?? "nkas-ios").trimmingCharacters(in: .whitespacesAndNewlines)
    guard hostname.range(of: "^[A-Za-z0-9][A-Za-z0-9-]{0,62}$", options: .regularExpression) != nil else {
      throw NkasIosAdbError.protocolError("节点名称只能包含字母、数字和连字符")
    }
    var endpoints: [String: String] = [:]
    for (name, address) in values["endpoints"] as? [String: String] ?? [:] {
      let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { throw NkasIosAdbError.protocolError("实例名不能为空") }
      if !value.isEmpty {
        _ = try NkasIosAdbEndpoint(value)
        endpoints[name] = value
      }
    }
    defaults.set(endpoint, forKey: "nkas_control_endpoint")
    defaults.set(endpoint, forKey: "nkas_serial")
    defaults.set(hostname, forKey: "nkas_tsnet_hostname")
    defaults.set(values["tailscaleEnabled"] as? Bool ?? false, forKey: "nkas_tsnet_enabled")
    defaults.set(endpoints, forKey: "nkas_control_endpoints")
    return snapshot()
  }
}

final class NkasTsnetClient {
  private let client = NkasNativetsnetNewClient()!
  private let settings: NkasControlSettings
  private var stateDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("tsnet", isDirectory: true)
  }

  init(settings: NkasControlSettings) { self.settings = settings }

  func configure(_ authKey: String) throws {
    client.close()
    var directory = stateDirectory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    try client.configure(authKey, hostname: settings.hostname, stateDir: directory.path)
  }

  func connect() throws {
    let phase = status()["phase"] as? String ?? "new"
    if !["configured", "connecting", "connected", "error"].contains(phase) { try configure("") }
    try client.connect()
  }

  func startForward(_ endpoint: NkasIosAdbEndpoint, localPort: Int = 0) throws -> [String: Any] {
    try connect()
    // A nonnull string return keeps gomobile's NSError parameter explicit in Swift.
    var error: NSError?
    let result = client.startForward(endpoint.host, remotePort: endpoint.port, localPort: localPort, error: &error)
    if let error { throw error }
    guard let value = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any] else {
      throw NkasIosAdbError.protocolError("Tailscale 转发响应无效")
    }
    return value
  }

  func stopForward(_ id: String) throws { try client.stopForward(id) }
  func stopAll() { client.stopAll() }
  func close() { client.close() }
  func interrupt() { client.interrupt() }

  func clearState() throws {
    client.close()
    if client.hasPersistedLogin(stateDirectory.path) { try configure("") }
    try client.clearState()
    if FileManager.default.fileExists(atPath: stateDirectory.path) {
      try FileManager.default.removeItem(at: stateDirectory)
    }
  }

  func status() -> [String: Any] {
    var value = (try? JSONSerialization.jsonObject(with: Data(client.status().utf8))) as? [String: Any] ?? [:]
    value["hostname"] = settings.hostname
    value["hasPersistedLogin"] = client.hasPersistedLogin(stateDirectory.path)
    if value["addresses"] is NSNull { value["addresses"] = [String]() }
    return value
  }
}
