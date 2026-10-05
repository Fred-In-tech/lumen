import Cocoa
import CoreImage
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
    BackupExclusion.register(messenger: flutterViewController.engine.binaryMessenger)
    RawDeveloper.register(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// `lumen/backup` channel: marks local-only derived data (face geometry, AI
/// rasters, models) as excluded from Time Machine.
enum BackupExclusion {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lumen/backup", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "exclude",
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        result(true)
      } catch {
        result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}

/// `lumen/raw` channel: develops camera RAW (CR2, CR3, DNG, ...) once with the
/// system decoder into an sRGB JPEG the 8-bit pipeline can decode. Default
/// rendering, camera white balance, orientation applied, camera EXIF kept.
enum RawDeveloper {
  enum Failure: LocalizedError {
    case unreadable

    var errorDescription: String? { "The system could not decode this RAW file." }
  }

  private static let queue = DispatchQueue(label: "lumen.raw", qos: .userInitiated)

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lumen/raw", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "develop",
        let args = call.arguments as? [String: Any],
        let input = args["input"] as? String,
        let output = args["output"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let quality = args["quality"] as? Double ?? 0.98
      // Developing a 45 MP file takes a second or two: keep it off the UI thread.
      queue.async {
        do {
          try develop(
            input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output),
            quality: quality)
          DispatchQueue.main.async { result(nil) }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(code: "develop_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  static func develop(input: URL, output: URL, quality: Double) throws {
    guard let filter = CIRAWFilter(imageURL: input),
      let image = filter.outputImage,
      !image.extent.isEmpty, !image.extent.isInfinite,
      let srgb = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw Failure.unreadable }
    try CIContext().writeJPEGRepresentation(
      of: image.settingProperties(metadata(of: input, developed: image.extent.size)),
      to: output,
      colorSpace: srgb,
      options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
  }

  /// The camera's EXIF for the rendition: pixels are already upright, so the
  /// orientation is reset; GPS, maker notes and serial numbers stay behind.
  private static func metadata(of input: URL, developed size: CGSize) -> [String: Any] {
    let source = CGImageSourceCreateWithURL(input as CFURL, nil)
    let all = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }
    var exif = all?[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
    var tiff = all?[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
    exif[kCGImagePropertyExifPixelXDimension as String] = Int(size.width)
    exif[kCGImagePropertyExifPixelYDimension as String] = Int(size.height)
    exif.removeValue(forKey: kCGImagePropertyExifBodySerialNumber as String)
    exif.removeValue(forKey: kCGImagePropertyExifLensSerialNumber as String)
    // Newer cameras report ISO only as ISOSpeed, which most readers ignore.
    if exif[kCGImagePropertyExifISOSpeedRatings as String] == nil,
      let iso = exif[kCGImagePropertyExifISOSpeed as String]
        ?? exif[kCGImagePropertyExifRecommendedExposureIndex as String]
    {
      exif[kCGImagePropertyExifISOSpeedRatings as String] = [iso]
    }
    tiff[kCGImagePropertyTIFFOrientation as String] = 1
    return [
      kCGImagePropertyExifDictionary as String: exif,
      kCGImagePropertyTIFFDictionary as String: tiff,
      kCGImagePropertyOrientation as String: 1,
    ]
  }
}
