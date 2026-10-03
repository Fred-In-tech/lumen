import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Editor-friendly default size, centered; never smaller than the desktop layout needs.
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let width = min(1440, screen.width * 0.92)
    let height = min(900, screen.height * 0.92)
    let frame = NSRect(
      x: screen.origin.x + (screen.width - width) / 2,
      y: screen.origin.y + (screen.height - height) / 2,
      width: width,
      height: height)
    self.setFrame(frame, display: true)
    self.minSize = NSSize(width: 960, height: 640)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.backgroundColor = NSColor(calibratedWhite: 0.067, alpha: 1)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
