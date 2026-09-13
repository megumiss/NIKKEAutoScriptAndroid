import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      NkasStarBridge.shared.register(binaryMessenger: controller.binaryMessenger)
    }
    connectionOptions.urlContexts.forEach { NkasStarBridge.shared.handle(url: $0.url) }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    URLContexts.forEach { NkasStarBridge.shared.handle(url: $0.url) }
  }

}
