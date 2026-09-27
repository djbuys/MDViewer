import Cocoa
import FlutterMacOS
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
