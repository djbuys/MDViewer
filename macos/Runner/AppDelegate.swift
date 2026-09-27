import Cocoa
import FlutterMacOS

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
