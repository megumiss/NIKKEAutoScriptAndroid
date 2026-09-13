import Flutter
import CoreVideo
import Foundation

final class NkasIosVideoTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private weak var registry: FlutterTextureRegistry?
  private(set) var textureId: Int64 = 0
  private var pixelBuffer: CVPixelBuffer?
  private var disposed = false

  init(registry: FlutterTextureRegistry) {
    precondition(Thread.isMainThread)
    self.registry = registry
    super.init()
    textureId = registry.register(self)
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard !disposed, let pixelBuffer else { return nil }
    return Unmanaged.passRetained(pixelBuffer)
  }

  func publish(_ buffer: CVPixelBuffer) {
    lock.lock()
    guard !disposed else { lock.unlock(); return }
    pixelBuffer = buffer
    lock.unlock()
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.lock.lock()
      let active = !self.disposed
      self.lock.unlock()
      if active { self.registry?.textureFrameAvailable(self.textureId) }
    }
  }

  func dispose() {
    lock.lock()
    guard !disposed else { lock.unlock(); return }
    disposed = true
    pixelBuffer = nil
    lock.unlock()
    let unregister = { [self] in registry?.unregisterTexture(textureId) }
    if Thread.isMainThread { unregister() }
    else { DispatchQueue.main.async { unregister() } }
  }
}
