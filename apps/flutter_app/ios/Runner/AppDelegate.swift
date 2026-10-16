import Flutter
import FirebaseAuth
import FirebaseCore
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrustKeyperAuthCallbacks") {
      FirebaseAuthCallbackPlugin.register(with: registrar)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

final class FirebaseAuthCallbackPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private let appID: () -> String?
  private let forwardToAuth: (URL) -> Void

  init(
    appID: @escaping () -> String? = {
      FirebaseApp.app()?.options.googleAppID ?? FirebaseOptions.defaultOptions()?.googleAppID
    },
    forwardToAuth: @escaping (URL) -> Void = { url in
      if let app = FirebaseApp.app() {
        _ = Auth.auth(app: app).canHandle(url)
      }
    }
  ) {
    self.appID = appID
    self.forwardToAuth = forwardToAuth
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = FirebaseAuthCallbackPlugin()
    registrar.publish(plugin)
    registrar.addApplicationDelegate(plugin)
    registrar.addSceneDelegate(plugin)
  }

  func handleCallbacks(_ urls: [URL]) -> Bool {
    guard let appID = appID(), !appID.isEmpty else { return false }
    let scheme = "app-" + appID.replacingOccurrences(of: ":", with: "-").lowercased()
    var handled = false
    for url in urls where url.scheme?.lowercased() == scheme
      && url.host?.lowercased() == "firebaseauth" && url.path == "/link" {
      forwardToAuth(url)
      handled = true
    }
    return handled
  }

  func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return handleCallbacks([url])
  }

  func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) -> Bool {
    return handleCallbacks(urlContexts.map { $0.url })
  }

  @objc(scene:willConnectToSession:options:)
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    return handleCallbacks(connectionOptions?.urlContexts.map { $0.url } ?? [])
  }
}
