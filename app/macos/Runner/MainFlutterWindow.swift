import Cocoa
import Accelerate
import Compression
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

  // One autorelease pool per call: CoreImage / RawCamera objects of a
  // decode are freed when it ends, not when the worker thread idles.
  private static let queue = DispatchQueue(
    label: "lumen.raw", qos: .userInitiated, autoreleaseFrequency: .workItem)

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lumen/raw", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      if FloatDeveloper.handles(call.method) {
        let args = call.arguments as? [String: Any] ?? [:]
        // Decodes take up to half a second: off the UI thread, one at a time.
        // Preview cache reads and background builds have their own queues
        // so they never wait behind (or delay) the decode a user waits for.
        (FloatDeveloper.queue(for: call.method) ?? queue).async {
          // A user is waiting for this decode: no App Nap throttling while
          // the window is hidden or in the background.
          let activity = ProcessInfo.processInfo.beginActivity(
            options: FloatDeveloper.isBackground(call.method) ? .background : .userInitiated,
            reason: "High-bit-depth decode")
          let reply = autoreleasepool { FloatDeveloper.reply(method: call.method, args: args) }
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
/// CoreImage reads are converted to extended sRGB as they are. The decoder
/// of the open photo stays cached. The only files written are preview
/// cache entries (`floatRender` with `cachePath`, `floatPreviewBuild`; read
/// back with `floatPreviewRead`, see `FloatPreviewFile`).
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
      || method == "floatPreviewRead" || method == "floatPreviewBuild"
  }

  /// Cache reads run concurrently on their own queue (a few ms each);
  /// background builds one at a time at utility priority. Everything else
  /// (the decoder cache below) stays on the caller's serial RAW queue.
  private static let readQueue = DispatchQueue(
    label: "lumen.raw.preview", qos: .userInitiated, attributes: .concurrent,
    autoreleaseFrequency: .workItem)
  private static let buildQueue = DispatchQueue(
    label: "lumen.raw.build", qos: .utility, autoreleaseFrequency: .workItem)
  private static let writeQueue = DispatchQueue(
    label: "lumen.raw.write", qos: .utility, autoreleaseFrequency: .workItem)

  static func queue(for method: String) -> DispatchQueue? {
    switch method {
    case "floatPreviewRead": return readQueue
    case "floatPreviewBuild": return buildQueue
    default: return nil
    }
  }

  static func isBackground(_ method: String) -> Bool { method == "floatPreviewBuild" }

  /// Runs one channel call (on the RAW queue) and returns its reply.
  static func reply(method: String, args: [String: Any]) -> Any? {
    if method == "floatPreviewRead" { return readPreview(args) }
    guard let path = args["input"] as? String else { return FlutterMethodNotImplemented }
    do {
      switch method {
      case "floatPreviewBuild":
        return try buildPreview(path, args)
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
        if let cachePath = args["cachePath"] as? String, x == 0, y == 0, width == fullWidth,
          height == fullHeight, let s = sources[path]
        {
          let meta = FloatPreviewFile.Meta(
            fullWidth: Int(s.fullSize.width), fullHeight: Int(s.fullSize.height),
            knee: s.extended ? shoulderKnee : 0, gain: s.extended ? highlightGain : 0)
          // The reply does not wait for the cache file.
          writeQueue.async {
            guard let bytes = FloatPreviewFile.encode(data, width: width, height: height, meta: meta)
            else { return }
            try? FloatPreviewFile.write(bytes, to: cachePath)
          }
        }
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
    return try render(
      source(path), fullWidth: fullWidth, fullHeight: fullHeight, x: x, y: y, width: width,
      height: height, space: space)
  }

  private static func render(
    _ source: Source, fullWidth: Int, fullHeight: Int, x: Int, y: Int, width: Int, height: Int,
    space: CGColorSpace
  ) throws -> Data {
    let image = try source.image(width: fullWidth, height: fullHeight)
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
      var one: Float = 1
      vDSP_vfill(&one, f.baseAddress! + 3, 4, vDSP_Length(width * height))
    }
    return data
  }

  /// `floatPreviewRead {cachePath, width, height}` → `{pixels, ms,
  /// fullWidth, fullHeight, shoulderKnee, highlightGain}`, or nil when there
  /// is no valid entry of that size. No RAW decode.
  private static func readPreview(_ args: [String: Any]) -> Any? {
    guard let cachePath = args["cachePath"] as? String, let width = args["width"] as? Int,
      let height = args["height"] as? Int
    else { return FlutterMethodNotImplemented }
    let start = CFAbsoluteTimeGetCurrent()
    guard let (data, meta) = FloatPreviewFile.decode(path: cachePath, width: width, height: height)
    else { return nil }
    return [
      "pixels": FlutterStandardTypedData(float32: data),
      "ms": Int((CFAbsoluteTimeGetCurrent() - start) * 1000),
      "fullWidth": meta.fullWidth, "fullHeight": meta.fullHeight,
      "shoulderKnee": meta.knee, "highlightGain": meta.gain,
    ]
  }

  /// `floatPreviewBuild {input, cachePath, fullWidth, fullHeight}` →
  /// `{bytes, ms}`: decodes the preview and writes its cache entry without
  /// sending pixels back (import, idle time, filmstrip neighbours). Its own
  /// decoder, dropped at the end; an existing valid entry is kept.
  private static func buildPreview(_ path: String, _ args: [String: Any]) throws -> Any? {
    guard let cachePath = args["cachePath"] as? String, let fullWidth = args["fullWidth"] as? Int,
      let fullHeight = args["fullHeight"] as? Int, fullWidth > 0, fullHeight > 0,
      let space = CGColorSpace(name: CGColorSpace.extendedSRGB)
    else { return FlutterMethodNotImplemented }
    let start = CFAbsoluteTimeGetCurrent()
    if let size = (try? FileManager.default.attributesOfItem(atPath: cachePath))?[.size] as? Int,
      FloatPreviewFile.isValid(path: cachePath, width: fullWidth, height: fullHeight)
    {
      return ["bytes": size, "ms": 0]
    }
    let s = try Source(url: URL(fileURLWithPath: path))
    let data = try render(
      s, fullWidth: fullWidth, fullHeight: fullHeight, x: 0, y: 0, width: fullWidth,
      height: fullHeight, space: space)
    let meta = FloatPreviewFile.Meta(
      fullWidth: Int(s.fullSize.width), fullHeight: Int(s.fullSize.height),
      knee: s.extended ? shoulderKnee : 0, gain: s.extended ? highlightGain : 0)
    guard let bytes = FloatPreviewFile.encode(data, width: fullWidth, height: fullHeight, meta: meta)
    else { throw Failure.unreadable }
    try FloatPreviewFile.write(bytes, to: cachePath)
    return ["bytes": bytes.count, "ms": Int((CFAbsoluteTimeGetCurrent() - start) * 1000)]
  }
}

// MARK: - Float preview cache (docs/HIGH_BIT_DEPTH.md, "Preview cache")

/// One cached float preview on disk, so reopening a RAW does not decode it
/// again. Layout (little endian), 64-byte header then the payload:
///
///     0 magic "LFP1"   4 format version   8 width   12 height
///    16 full width    20 full height     24 shoulder knee (f64)
///    32 highlight gain (f64)             40 OS build stamp (u64)
///    48 payload bytes (u64)              56 codec (u32: 1 = LZ4, 0 = raw)
///
/// Payload: the preview's RGB as half floats (alpha is always 1 and is not
/// stored), bytes split into a plane of low bytes then a plane of high
/// bytes (compresses about 30 % better), LZ4-compressed. Measured on a
/// 1708 x 2560 preview of a 45 MP CR3: 17 MB (35 MB raw half RGBA), encode
/// 30 ms, decode 6 ms. Half floats keep 11 significant bits (relative
/// error below 0.05 %) and the full extended range.
///
/// The Dart side (`float_preview_cache_io.dart`) owns names, the size cap
/// and eviction; it reads only the header. Files are written to a
/// temporary name and renamed, so a reader never sees half a file.
enum FloatPreviewFile {
  static let magic: UInt32 = 0x3150_464C  // "LFP1"
  static let headerSize = 64
  /// Bumped when the decoder settings or the layout change.
  static let formatVersion: UInt32 = 1
  /// A system update can change Apple's RAW rendering: entries written by
  /// another OS build are misses.
  static let osStamp: UInt64 = {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in ProcessInfo.processInfo.operatingSystemVersionString.utf8 {
      h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3
    }
    return h
  }()

  struct Meta {
    var fullWidth: Int
    var fullHeight: Int
    var knee: Double
    var gain: Double
  }

  /// Float32 RGBA (alpha 1) of `width` x `height` → file bytes. Every
  /// step is an Accelerate call (fast in debug builds too).
  static func encode(_ rgba: Data, width: Int, height: Int, meta: Meta) -> Data? {
    let px = width * height
    guard px > 0, rgba.count == px * 16 else { return nil }
    let n = px * 3
    let h = vImagePixelCount(height), w = vImagePixelCount(width)
    var rgb = [Float](repeating: 0, count: n)
    var half = [UInt16](repeating: 0, count: n)
    var split = [UInt8](repeating: 0, count: n * 2)
    rgba.withUnsafeBytes { s in
      rgb.withUnsafeMutableBytes { r in
        half.withUnsafeMutableBytes { hb in
          split.withUnsafeMutableBytes { sp in
            var src = vImage_Buffer(
              data: UnsafeMutableRawPointer(mutating: s.baseAddress!), height: h, width: w,
              rowBytes: width * 16)
            var rgbBuf = vImage_Buffer(data: r.baseAddress!, height: h, width: w, rowBytes: width * 12)
            _ = vImageConvert_RGBAFFFFtoRGBFFF(&src, &rgbBuf, 0)
            var planarF = vImage_Buffer(
              data: r.baseAddress!, height: h, width: w * 3, rowBytes: width * 12)
            var planar16 = vImage_Buffer(
              data: hb.baseAddress!, height: h, width: w * 3, rowBytes: width * 6)
            _ = vImageConvert_PlanarFtoPlanar16F(&planarF, &planar16, 0)
            var lo = vImage_Buffer(data: sp.baseAddress!, height: h, width: w * 3, rowBytes: width * 3)
            var hi = vImage_Buffer(
              data: sp.baseAddress! + n, height: h, width: w * 3, rowBytes: width * 3)
            withUnsafePointer(to: &lo) { loP in
              withUnsafePointer(to: &hi) { hiP in
                var chans: [UnsafeRawPointer?] = [
                  UnsafeRawPointer(hb.baseAddress!), UnsafeRawPointer(hb.baseAddress! + 1),
                ]
                var dests: [UnsafePointer<vImage_Buffer>?] = [loP, hiP]
                _ = vImageConvert_ChunkyToPlanar8(
                  &chans, &dests, 2, 2, w * 3, h, width * 6, 0)
              }
            }
          }
        }
      }
    }
    let capacity = n * 2 + n / 64 + 1024
    var packed = [UInt8](repeating: 0, count: capacity)
    let size = compression_encode_buffer(
      &packed, capacity, split, split.count, nil, COMPRESSION_LZ4)
    let codec: UInt32 = size > 0 && size < split.count ? 1 : 0
    var out = Data(capacity: headerSize + (codec == 1 ? size : split.count))
    func put<T>(_ v: T) { withUnsafeBytes(of: v) { out.append(contentsOf: $0) } }
    put(magic.littleEndian)
    put(formatVersion.littleEndian)
    put(UInt32(width).littleEndian)
    put(UInt32(height).littleEndian)
    put(UInt32(meta.fullWidth).littleEndian)
    put(UInt32(meta.fullHeight).littleEndian)
    put(meta.knee.bitPattern.littleEndian)
    put(meta.gain.bitPattern.littleEndian)
    put(osStamp.littleEndian)
    put(UInt64(codec == 1 ? size : split.count).littleEndian)
    put(codec.littleEndian)
    put(UInt32(0))
    if codec == 1 { out.append(contentsOf: packed[0..<size]) } else { out.append(contentsOf: split) }
    return out
  }

  /// The preview stored at `path` when it is a valid entry of exactly
  /// `width` x `height`, as float32 RGBA (alpha 1); nil on any mismatch.
  static func decode(path: String, width: Int, height: Int) -> (Data, Meta)? {
    guard let file = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
      file.count >= headerSize
    else { return nil }
    func u32(_ o: Int) -> UInt32 {
      file.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
    }
    func u64(_ o: Int) -> UInt64 {
      file.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt64.self)) }
    }
    guard u32(0) == magic, u32(4) == formatVersion, Int(u32(8)) == width,
      Int(u32(12)) == height, u64(40) == osStamp
    else { return nil }
    let meta = Meta(
      fullWidth: Int(u32(16)), fullHeight: Int(u32(20)),
      knee: Double(bitPattern: u64(24)), gain: Double(bitPattern: u64(32)))
    let payload = Int(u64(48)), codec = u32(56)
    let px = width * height, n = px * 3
    guard px > 0, file.count == headerSize + payload else { return nil }
    var split = [UInt8](repeating: 0, count: n * 2)
    if codec == 1 {
      let got = file.withUnsafeBytes { s -> Int in
        let src = s.bindMemory(to: UInt8.self).baseAddress!.advanced(by: headerSize)
        return compression_decode_buffer(&split, split.count, src, payload, nil, COMPRESSION_LZ4)
      }
      guard got == split.count else { return nil }
    } else {
      guard payload == split.count else { return nil }
      split = [UInt8](file[headerSize..<(headerSize + payload)])
    }
    let h = vImagePixelCount(height), w = vImagePixelCount(width)
    var half = [UInt16](repeating: 0, count: n)
    var rgb = [Float](repeating: 0, count: n)
    var out = Data(count: px * 16)
    split.withUnsafeMutableBytes { sp in
      half.withUnsafeMutableBytes { hb in
        rgb.withUnsafeMutableBytes { r in
          out.withUnsafeMutableBytes { d in
            var lo = vImage_Buffer(data: sp.baseAddress!, height: h, width: w * 3, rowBytes: width * 3)
            var hi = vImage_Buffer(
              data: sp.baseAddress! + n, height: h, width: w * 3, rowBytes: width * 3)
            withUnsafePointer(to: &lo) { loP in
              withUnsafePointer(to: &hi) { hiP in
                var srcs: [UnsafePointer<vImage_Buffer>?] = [loP, hiP]
                var chans: [UnsafeMutableRawPointer?] = [hb.baseAddress!, hb.baseAddress! + 1]
                _ = vImageConvert_PlanarToChunky8(&srcs, &chans, 2, 2, w * 3, h, width * 6, 0)
              }
            }
            var planar16 = vImage_Buffer(
              data: hb.baseAddress!, height: h, width: w * 3, rowBytes: width * 6)
            var planarF = vImage_Buffer(
              data: r.baseAddress!, height: h, width: w * 3, rowBytes: width * 12)
            _ = vImageConvert_Planar16FtoPlanarF(&planar16, &planarF, 0)
            var rgbBuf = vImage_Buffer(data: r.baseAddress!, height: h, width: w, rowBytes: width * 12)
            var dst = vImage_Buffer(data: d.baseAddress!, height: h, width: w, rowBytes: width * 16)
            _ = vImageConvert_RGBFFFtoRGBAFFFF(&rgbBuf, nil, 1, &dst, false, 0)
          }
        }
      }
    }
    return (out, meta)
  }

  /// True when `path` holds an entry of this format, OS build and size
  /// (header only; the payload is checked when it is read).
  static func isValid(path: String, width: Int, height: Int) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? handle.close() }
    guard let head = try? handle.read(upToCount: headerSize), head.count == headerSize else {
      return false
    }
    func u32(_ o: Int) -> UInt32 {
      head.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
    }
    let stamp = head.withUnsafeBytes {
      UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: 40, as: UInt64.self))
    }
    return u32(0) == magic && u32(4) == formatVersion && Int(u32(8)) == width
      && Int(u32(12)) == height && stamp == osStamp
  }

  /// Writes atomically (temporary file, then rename).
  static func write(_ bytes: Data, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString)")
    try bytes.write(to: tmp)
    if rename(tmp.path, url.path) != 0 {
      try? FileManager.default.removeItem(at: tmp)
      throw CocoaError(.fileWriteUnknown)
    }
  }
}
