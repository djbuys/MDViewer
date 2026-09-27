import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DocumentAccessPlugin") {
      DocumentAccessPlugin.register(with: registrar)
    }
  }
}

/// Document picking with security-scoped bookmarks, and "Open in" hand-offs.
/// Channels: `mdviewer/ios_documents` and `mdviewer/incoming`.
final class DocumentAccessPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate, UIDocumentPickerDelegate {
  private static var instance: DocumentAccessPlugin?

  private let documents: FlutterMethodChannel
  private let incoming: FlutterMethodChannel
  private var pendingIncoming: [[String: String]] = []
  private var dartReady = false
  private var pickResult: FlutterResult?
  private var scopedURLs: [URL] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = DocumentAccessPlugin(messenger: registrar.messenger())
    registrar.addSceneDelegate(plugin)
    instance = plugin
  }

  init(messenger: FlutterBinaryMessenger) {
    documents = FlutterMethodChannel(name: "mdviewer/ios_documents", binaryMessenger: messenger)
    incoming = FlutterMethodChannel(name: "mdviewer/incoming", binaryMessenger: messenger)
    super.init()
    documents.setMethodCallHandler { [weak self] call, result in self?.handleDocuments(call, result) }
    incoming.setMethodCallHandler { [weak self] call, result in self?.handleIncoming(call, result) }
  }

  // MARK: - Dart calls

  private func handleIncoming(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "takePending" else {
      result(FlutterMethodNotImplemented)
      return
    }
    dartReady = true
    result(pendingIncoming)
    pendingIncoming.removeAll()
  }

  private func handleDocuments(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "pickFile":
      let types = [
        UTType("net.daringfireball.markdown"),
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
        UTType.plainText,
      ].compactMap { $0 }
      present(UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false), result)
    case "pickFolder":
      present(UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false), result)
    case "resolveBookmark":
      guard let args = call.arguments as? [String: Any], let bookmark = args["bookmark"] as? String else {
        result(nil)
        return
      }
      result(resolve(bookmark: bookmark))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Picking

  private func present(_ picker: UIDocumentPickerViewController, _ result: @escaping FlutterResult) {
    guard pickResult == nil else {
      result(FlutterError(code: "busy", message: "A picker is already open", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: "no_ui", message: "No view controller to present from", details: nil))
      return
    }
    pickResult = result
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let result = pickResult
    pickResult = nil
    result?(urls.first.flatMap(describe))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pickResult
    pickResult = nil
    result?(nil)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  // MARK: - Security scope and bookmarks

  /// Starts (and keeps) security-scoped access and returns the path plus a
  /// fresh bookmark for recents.
  private func describe(_ url: URL) -> [String: String]? {
    let scoped = url.startAccessingSecurityScopedResource()
    guard scoped || FileManager.default.isReadableFile(atPath: url.path) else { return nil }
    if scoped { scopedURLs.append(url) }
    var map = ["path": url.path]
    if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      map["bookmark"] = data.base64EncodedString()
    }
    return map
  }

  private func resolve(bookmark: String) -> [String: String]? {
    guard let data = Data(base64Encoded: bookmark) else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    else { return nil }
    return describe(url)
  }

  // MARK: - "Open in" / Files app hand-offs

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions?) -> Bool {
    if let contexts = connectionOptions?.urlContexts { receive(contexts) }
    return false
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    return receive(URLContexts)
  }

  @discardableResult
  private func receive(_ contexts: Set<UIOpenURLContext>) -> Bool {
    let docs = contexts.map(\.url).filter(\.isFileURL).compactMap(describe)
    guard !docs.isEmpty else { return false }
    if dartReady {
      incoming.invokeMethod("open", arguments: docs)
    } else {
      pendingIncoming.append(contentsOf: docs)
    }
    return true
  }
}
