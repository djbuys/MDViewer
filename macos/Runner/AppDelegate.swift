import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import WebKit

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Finder double-click, "Open With" and Dock drops.
  override func application(_ application: NSApplication, open urls: [URL]) {
    IncomingFilesChannel.shared.open(urls: urls)
    super.application(application, open: urls)
  }
}

/// Copy / Select All for the Edit menu (`mdviewer/edit`). Flutter's
/// `PlatformMenuBar` replaces the native Edit menu, so its items no longer
/// send `copy:`/`selectAll:` to the first responder. When the first responder
/// is (inside) a WKWebView this sends the action there and answers true;
/// otherwise it answers false and Dart routes the command to Flutter.
final class EditChannel {
  static let shared = EditChannel()

  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mdviewer/edit", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let selector: Selector
      switch call.method {
      case "copy":
        selector = #selector(NSText.copy(_:))
      case "selectAll":
        selector = #selector(NSText.selectAll(_:))
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        guard EditChannel.webViewIsFirstResponder() else {
          result(false)
          return
        }
        result(NSApp.sendAction(selector, to: nil, from: nil))
      }
    }
    self.channel = channel
  }

  private static func webViewIsFirstResponder() -> Bool {
    var view = NSApp.keyWindow?.firstResponder as? NSView
    while let current = view {
      if current is WKWebView { return true }
      view = current.superview
    }
    return false
  }
}

/// Default app for Markdown (`mdviewer/default_app`): `isDefault` and
/// `makeDefault` through LaunchServices. Apps are compared by bundle
/// identifier, so the /Applications copy and build copies count as the same.
final class DefaultAppChannel {
  static let shared = DefaultAppChannel()

  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mdviewer/default_app", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isDefault":
        result(DefaultAppChannel.isDefault())
      case "makeDefault":
        DefaultAppChannel.makeDefault { result($0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  /// The Markdown type, plus the `.md` extension's type if it differs.
  private static var markdownTypes: [UTType] {
    var types: [UTType] = []
    if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
    if let md = UTType(filenameExtension: "md"), !types.contains(md) { types.append(md) }
    return types
  }

  static func isDefault() -> Bool {
    guard let me = Bundle.main.bundleIdentifier, !markdownTypes.isEmpty else { return false }
    return markdownTypes.allSatisfy { type in
      guard let app = NSWorkspace.shared.urlForApplication(toOpen: type) else { return false }
      return Bundle(url: app)?.bundleIdentifier == me
    }
  }

  static func makeDefault(completion: @escaping (Bool) -> Void) {
    let types = markdownTypes
    guard !types.isEmpty else {
      completion(false)
      return
    }
    let group = DispatchGroup()
    var failed = false
    for type in types {
      group.enter()
      NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
        DispatchQueue.main.async {
          if error != nil { failed = true }
          group.leave()
        }
      }
    }
    group.notify(queue: .main) { completion(!failed && isDefault()) }
  }
}

/// Buffers documents the OS asks the app to open until Dart asks for them
/// (`takePending`), then forwards later ones immediately (`open`).
final class IncomingFilesChannel {
  static let shared = IncomingFilesChannel()

  private var channel: FlutterMethodChannel?
  private var pending: [[String: String]] = []
  private var dartReady = false

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mdviewer/incoming", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "takePending":
        self.dartReady = true
        result(self.pending)
        self.pending.removeAll()
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func open(urls: [URL]) {
    let documents = urls.filter(\.isFileURL).map { ["path": $0.path] }
    guard !documents.isEmpty else { return }
    if dartReady, let channel {
      channel.invokeMethod("open", arguments: documents)
    } else {
      pending.append(contentsOf: documents)
    }
  }
}
