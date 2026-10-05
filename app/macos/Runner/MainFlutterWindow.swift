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
/// The float methods of the same channel are in `FloatDeveloper` below.
enum RawDeveloper {
  enum Failure: LocalizedError {
    case unreadable

    var errorDescription: String? { "The system could not decode this RAW file." }
  }

  private static let queue = DispatchQueue(label: "lumen.raw", qos: .userInitiated)

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lumen/raw", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      if FloatDeveloper.handles(call.method) {
        let args = call.arguments as? [String: Any] ?? [:]
        // Decodes take up to half a second: off the UI thread, one at a time.
        queue.async {
          // A user is waiting for this decode: no App Nap throttling while
          // the window is hidden or in the background.
          let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated, reason: "High-bit-depth decode")
          let reply = FloatDeveloper.reply(method: call.method, args: args)
          ProcessInfo.processInfo.endActivity(activity)
          DispatchQueue.main.async { result(reply) }
        }
        return
      }
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

/// Float (high-bit-depth) decode for the float editing path, on the
/// `lumen/raw` channel (docs/HIGH_BIT_DEPTH.md):
///
/// * `floatInfo {input}` → `{width, height, shoulderKnee, highlightGain}`:
///   the full upright size and how develop should render the source.
/// * `floatRender {input, fullWidth, fullHeight, x, y, width, height}` →
///   `{pixels}`: the window (top-left origin) of the photo scaled to
///   fullWidth x fullHeight, as little-endian float32 RGBA in extended
///   sRGB (encoded; above 1.0 = brighter than display white), alpha 1,
///   upright, rows top to bottom.
/// * `floatRelease {input}`: drops the cached decoder of that file.
///
/// Camera RAW gets Apple's default rendering (camera white balance,
/// default boost and tone curve: the look of the JPEG rendition) with the
/// extended dynamic range kept. 16-bit PNG, 10-bit HEIC and other files
/// CoreImage reads are converted to extended sRGB as they are. Nothing is
/// written to disk; the decoder of the open photo stays cached.
enum FloatDeveloper {
  enum Failure: LocalizedError {
    case unreadable
    case badWindow

    var errorDescription: String? {
      switch self {
      case .unreadable: return "The system could not decode this file in high bit depth."
      case .badWindow: return "The requested window is outside the image."
      }
    }
  }

  /// Apple's default (SDR) RAW rendering rolls highlights off from this
  /// encoded value and reaches white at `2 - knee`; the extended rendering
  /// is identical below it and has no roll-off. Develop applies the
  /// roll-off itself (measured on Canon CR3, see the doc).
  static let shoulderKnee = 0.86
  /// Extra Highlights range (EV per stop above white) for such sources.
  static let highlightGain = 0.5

  private static let rawTypes: Set<String> = [
    "cr2", "cr3", "dng", "nef", "nrw", "arw", "sr2", "raf", "orf", "rw2", "pef", "srw", "erf",
    "3fr",
  ]

  final class Source {
    let url: URL
    let isRaw: Bool
    /// The extended-range rendering keeps the look of the default one.
    private(set) var extended = false
    private(set) var fullSize = CGSize.zero
    private var scaled: [(scale: Float, image: CIImage)] = []
    private var plain: CIImage?

    init(url: URL) throws {
      self.url = url
      isRaw = FloatDeveloper.rawTypes.contains(url.pathExtension.lowercased())
      if isRaw {
        guard let filter = CIRAWFilter(imageURL: url), let image = filter.outputImage,
          !image.extent.isEmpty, !image.extent.isInfinite
        else { throw Failure.unreadable }
        fullSize = image.extent.size
        // Files with a local tone map (Apple ProRAW) lose it in the extended
        // rendering and look different: they keep the default rendering,
        // in float but without highlight headroom.
        extended = !filter.isLocalToneMapSupported
      } else {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
          !image.extent.isEmpty, !image.extent.isInfinite
        else { throw Failure.unreadable }
        plain = image.transformed(
          by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        fullSize = image.extent.size
      }
    }

    private func rawImage(scale: Float) -> CIImage? {
      guard let filter = CIRAWFilter(imageURL: url) else { return nil }
      filter.scaleFactor = scale
      if extended { filter.extendedDynamicRangeAmount = 2 }
      return filter.outputImage
    }

    /// The upright photo scaled to exactly `width` x `height`, origin 0, 0.
    func image(width: Int, height: Int) throws -> CIImage {
      let want = Float(
        min(1, max(CGFloat(width) / fullSize.width, CGFloat(height) / fullSize.height)))
      var base: CIImage
      if isRaw {
        if let hit = scaled.first(where: { $0.scale == want }) {
          base = hit.image
        } else {
          // The decoder scales while it demosaics; each scale is its own
          // decode (about half a second for 45 MP), cached while open.
          guard let fresh = rawImage(scale: want) else { throw Failure.unreadable }
          scaled.append((want, fresh))
          if scaled.count > 3 { scaled.removeFirst() }
          base = fresh
        }
      } else {
        guard let p = plain else { throw Failure.unreadable }
        base = p
        if want < 1 {
          base = base.clampedToExtent().applyingFilter(
            "CILanczosScaleTransform",
            parameters: [kCIInputScaleKey: want, kCIInputAspectRatioKey: 1.0]
          ).cropped(
            to: CGRect(
              x: 0, y: 0, width: (p.extent.width * CGFloat(want)).rounded(),
              height: (p.extent.height * CGFloat(want)).rounded()))
        }
      }
      let e = base.extent
      base = base.transformed(by: CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y))
      let sx = CGFloat(width) / e.width
      let sy = CGFloat(height) / e.height
      if abs(sx - 1) > 1e-6 || abs(sy - 1) > 1e-6 {
        // Rounding residue of the requested size (a fraction of a pixel).
        base = base.clampedToExtent().transformed(by: CGAffineTransform(scaleX: sx, y: sy))
          .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
      }
      return base
    }
  }

  private static var sources: [String: Source] = [:]
  private static var order: [String] = []
  private static let context = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) as Any,
    .workingFormat: CIFormat.RGBAf,
  ])

  static func handles(_ method: String) -> Bool {
    method == "floatInfo" || method == "floatRender" || method == "floatRelease"
  }

  /// Runs one channel call (on the RAW queue) and returns its reply.
  static func reply(method: String, args: [String: Any]) -> Any? {
    guard let path = args["input"] as? String else { return FlutterMethodNotImplemented }
    do {
      switch method {
      case "floatInfo":
        let s = try source(path)
        return [
          "width": Int(s.fullSize.width), "height": Int(s.fullSize.height),
          "shoulderKnee": s.extended ? shoulderKnee : 0.0,
          "highlightGain": s.extended ? highlightGain : 0.0,
        ]
      case "floatRender":
        guard let fullWidth = args["fullWidth"] as? Int, let fullHeight = args["fullHeight"] as? Int,
          let x = args["x"] as? Int, let y = args["y"] as? Int,
          let width = args["width"] as? Int, let height = args["height"] as? Int
        else { return FlutterMethodNotImplemented }
        let start = CFAbsoluteTimeGetCurrent()
        let data = try render(
          path, fullWidth: fullWidth, fullHeight: fullHeight, x: x, y: y, width: width,
          height: height)
        return [
          "pixels": FlutterStandardTypedData(float32: data),
          "ms": Int((CFAbsoluteTimeGetCurrent() - start) * 1000),
        ]
      default:
        release(path)
        return nil
      }
    } catch {
      return FlutterError(
        code: "float_failed", message: error.localizedDescription, details: nil)
    }
  }

  /// The cached decoder of `path`. Two photos stay cached at most: the one
  /// open in the editor and one being exported.
  private static func source(_ path: String) throws -> Source {
    if let hit = sources[path] { return hit }
    let fresh = try Source(url: URL(fileURLWithPath: path))
    sources[path] = fresh
    order.append(path)
    while order.count > 2 { sources.removeValue(forKey: order.removeFirst()) }
    return fresh
  }

  private static func release(_ path: String) {
    sources.removeValue(forKey: path)
    order.removeAll { $0 == path }
    if sources.isEmpty { context.clearCaches() }
  }

  private static func render(
    _ path: String, fullWidth: Int, fullHeight: Int, x: Int, y: Int, width: Int, height: Int
  ) throws -> Data {
    guard fullWidth > 0, fullHeight > 0, width > 0, height > 0, x >= 0, y >= 0,
      x + width <= fullWidth, y + height <= fullHeight,
      let space = CGColorSpace(name: CGColorSpace.extendedSRGB)
    else { throw Failure.badWindow }
    let image = try source(path).image(width: fullWidth, height: fullHeight)
    // CoreImage's origin is bottom-left; the bitmap comes out top to bottom.
    let rect = CGRect(x: x, y: fullHeight - y - height, width: width, height: height)
    var data = Data(count: width * height * 16)
    data.withUnsafeMutableBytes { p in
      guard let base = p.baseAddress else { return }
      context.render(
        image, toBitmap: base, rowBytes: width * 16, bounds: rect, format: .RGBAf,
        colorSpace: space)
      // Alpha is 1 by contract: premultiplication on upload is then a no-op.
      let f = p.bindMemory(to: Float.self)
      var i = 3
      while i < f.count {
        f[i] = 1
        i += 4
      }
    }
    return data
  }
}
