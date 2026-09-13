import Flutter
import CoreVideo
import Foundation

final class NkasIosVideoTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private weak var registry: FlutterTextureRegistry?
  private(set) var textureId: Int64 = 0
  private var pixelBuffer: CVPixelBuffer?

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
    super.init()
    textureId = registry.register(self)
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let pixelBuffer else { return nil }
    return Unmanaged.passRetained(pixelBuffer)
  }

  func publish(_ buffer: CVPixelBuffer) {
    lock.lock()
    pixelBuffer = buffer
    lock.unlock()
    registry?.textureFrameAvailable(textureId)
  }

  func dispose() {
    registry?.unregisterTexture(textureId)
    lock.lock()
    pixelBuffer = nil
    lock.unlock()
  }
}
