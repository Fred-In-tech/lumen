import CoreImage
import Flutter
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
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LumenBackupExclusion") {
      BackupExclusion.register(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LumenRawDeveloper") {
      RawDeveloper.register(messenger: registrar.messenger())
    }
  }
}

/// `lumen/backup` channel: marks local-only derived data (face geometry, AI
/// rasters, models) as excluded from iCloud / device backups.
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
