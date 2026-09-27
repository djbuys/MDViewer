import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let frameName = "MDViewerMainWindow"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    IncomingFilesChannel.shared.attach(messenger: messenger)
    EditChannel.shared.attach(messenger: messenger)
    DefaultAppChannel.shared.attach(messenger: messenger)
    WindowChannel.shared.attach(window: self, messenger: messenger)

    configureTitleBar()
    configureFrame()

    super.awakeFromNib()
  }

  /// One unified row: traffic lights, then Flutter's title bar (52 pt tall,
  /// drawn by Flutter under the transparent native title bar).
  private func configureTitleBar() {
    title = "MDViewer"  // Still used by the Window menu and Mission Control.
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    // An empty unified toolbar makes the title bar 52 pt tall and centres
    // the traffic lights in it, like Finder and Safari.
    let toolbar = NSToolbar(identifier: "MDViewerToolbar")
    toolbar.showsBaselineSeparator = false
    toolbar.allowsUserCustomization = false
    self.toolbar = toolbar
    toolbarStyle = .unified
    titlebarSeparatorStyle = .none
  }

  /// Restores the saved size and position, or opens 1280x820 centred.
  private func configureFrame() {
    contentMinSize = NSSize(width: 480, height: 360)
    let restored = setFrameUsingName(MainFlutterWindow.frameName)
    setFrameAutosaveName(MainFlutterWindow.frameName)
    if !restored {
      setContentSize(NSSize(width: 1280, height: 820))
      center()
    }
  }
}

/// Window dragging and zooming from the empty parts of Flutter's title bar
/// (`mdviewer/window`).
final class WindowChannel {
  static let shared = WindowChannel()

  private weak var window: NSWindow?
  private var channel: FlutterMethodChannel?
  private var monitor: Any?
  /// The most recent left mouse-down in the window. Dart's `startDrag`
  /// arrives after the event, so the event is kept for `performDrag(with:)`.
  private var lastMouseDown: NSEvent?

  func attach(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      if event.window === self?.window { self?.lastMouseDown = event }
      return event
    }
    let channel = FlutterMethodChannel(name: "mdviewer/window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, let window = self.window else {
        result(nil)
        return
      }
      switch call.method {
      case "startDrag":
        self.startDrag(window: window)
        result(nil)
      case "toggleZoom":
        WindowChannel.titleBarDoubleClick(window: window)
        result(nil)
      default:
        #if DEBUG
          if let handled = self.handleDebug(call, window: window) {
            result(handled)
            return
          }
        #endif
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func startDrag(window: NSWindow) {
    guard let event = lastMouseDown, NSEvent.pressedMouseButtons & 1 == 1 else { return }
    // performDrag runs its own tracking loop and swallows the mouse-up, so
    // Flutter would still think the button is down; send it a mouse-up.
    window.performDrag(with: event)
    let location = window.mouseLocationOutsideOfEventStream
    if let up = NSEvent.mouseEvent(
      with: .leftMouseUp, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
    {
      window.sendEvent(up)
    }
  }

  /// Honours System Settings > Desktop & Dock > "Double-click a window's
  /// title bar to".
  static func titleBarDoubleClick(window: NSWindow) {
    switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
    case "Minimize":
      window.performMiniaturize(nil)
    case "None":
      break
    default:
      window.performZoom(nil)
    }
  }

  #if DEBUG
    /// Integration-test hooks (debug builds only). Points are in Flutter
    /// logical coordinates: origin at the top left of the content view.
    private func handleDebug(_ call: FlutterMethodCall, window: NSWindow) -> Any? {
      if call.method == "debugCloseButtonFrame" {
        guard let button = window.standardWindowButton(.closeButton), let content = window.contentView else {
          return nil
        }
        let frame = button.convert(button.bounds, to: nil)
        return [
          "x": frame.minX, "y": content.frame.height - frame.maxY, "width": frame.width, "height": frame.height,
        ]
      }
      guard let args = call.arguments as? [String: Any],
        let x = (args["x"] as? NSNumber)?.doubleValue,
        let y = (args["y"] as? NSNumber)?.doubleValue,
        let content = window.contentView
      else { return nil }
      let inWindow = NSPoint(x: x, y: content.frame.height - y)
      switch call.method {
      case "debugHitTest":
        // The same hit-test AppKit uses to route a real click: from the
        // window's frame view, which also holds the title bar and toolbar.
        guard let frameView = content.superview else { return "none" }
        let hit = frameView.hitTest(frameView.convert(inWindow, from: nil))
        return hit.map { String(describing: type(of: $0)) } ?? "none"
      case "debugClick":
        // A real NSEvent delivered through NSWindow.sendEvent, i.e. through
        // AppKit's hit-testing and the title bar, as a user click would be.
        let now = ProcessInfo.processInfo.systemUptime
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
          guard
            let event = NSEvent.mouseEvent(
              with: type, location: inWindow, modifierFlags: [], timestamp: now, windowNumber: window.windowNumber,
              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
          else { return false }
          window.sendEvent(event)
        }
        return true
      default:
        return nil
      }
    }
  #endif
}
