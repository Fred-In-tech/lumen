/// Lightroom (`crs:`) settings Lumen does not apply, by plain-language
/// label, and the metadata keys that are not settings at all.
library;

/// Keys that describe the preset rather than change the photo, or that
/// the converter reads itself: never reported.
const Set<String> kLightroomSilentKeys = {
  'Name', 'ShortName', 'SortName', 'Group', 'Description', 'Copyright', //
  'ContactInfo', 'UUID', 'Cluster', 'PresetType', 'SupportsAmount',
  'SupportsAmount2', 'SupportsColor', 'SupportsMonochrome',
  'SupportsHighDynamicRange', 'SupportsNormalDynamicRange',
  'SupportsSceneReferred', 'SupportsOutputReferred', 'RequiresRGBTables',
  'CameraModelRestriction', 'ProcessVersion', 'Version', 'HasSettings',
  'AlreadyApplied', 'ToneCurveName', 'ToneCurveName2012', 'GrainSeed',
  'WhiteBalance', 'ConvertToGrayscale', 'OverrideLookVignette',
  'RawFileName', 'HasCrop', 'PostCropVignetteStyle', 'CompatibleVersion',
  'ToneCurve', 'ToneCurvePV2012', 'ToneCurvePV2012Red',
  'ToneCurvePV2012Green', 'ToneCurvePV2012Blue', 'Temperature', 'Tint',
  'IncrementalTemperature', 'IncrementalTint', 'Exposure', 'Contrast',
  'Clarity', 'FillLight', 'HighlightRecovery', 'Shadows',
};

/// Prefix or exact key → the label shown under "no Lumen equivalent".
/// First match wins; keys ending in `*` match as prefixes.
const List<(String, String)> kLightroomSkippedLabels = [
  ('GradientBasedCorrections', 'Local masks'),
  ('CircularGradientBasedCorrections', 'Local masks'),
  ('PaintBasedCorrections', 'Local masks'),
  ('MaskGroupBasedCorrections', 'Local masks'),
  ('RangeMask*', 'Local masks'),
  ('LensProfile*', 'Lens profile'),
  ('LensManual*', 'Lens corrections'),
  ('AutoLateralCA', 'Lens corrections'),
  ('ChromaticAberration*', 'Lens corrections'),
  ('Defringe*', 'Lens corrections'),
  ('VignetteAmount', 'Lens corrections'),
  ('VignetteMidpoint', 'Lens corrections'),
  ('Perspective*', 'Transform'),
  ('Upright*', 'Transform'),
  ('ShadowTint', 'Calibration'),
  ('RedHue', 'Calibration'),
  ('RedSaturation', 'Calibration'),
  ('GreenHue', 'Calibration'),
  ('GreenSaturation', 'Calibration'),
  ('BlueHue', 'Calibration'),
  ('BlueSaturation', 'Calibration'),
  ('CameraProfile*', 'Camera profile'),
  ('Look', 'Camera profile'),
  ('LookName', 'Camera profile'),
  ('Crop*', 'Crop'),
  ('RetouchInfo', 'Spot removal'),
  ('RetouchAreas', 'Spot removal'),
  ('RedEyeInfo', 'Red eye'),
  ('HDR*', 'HDR editing'),
  ('SDR*', 'HDR editing'),
  ('Auto*', 'Auto settings'),
  ('Enhance*', 'Enhance'),
  ('Denoise*', 'Enhance'),
  ('PointColors', 'Point color'),
  ('CurveRefineSaturation', 'Tone curve saturation'),
  ('LensBlur', 'Lens blur'),
  ('LuminanceNoiseReduction*', 'Noise reduction detail'),
  ('ColorNoiseReductionDetail', 'Noise reduction detail'),
  ('ColorNoiseReductionSmoothness', 'Noise reduction detail'),
  ('Brightness', 'Brightness (process 2010)'),
  ('Enable*', ''), // group switches: nothing to apply or report
  ('Mask*', 'Local masks'),
];

/// The skipped label for [key], '' for keys that are silently ignored, or
/// null when the key is unknown.
String? lightroomSkippedLabel(String key) {
  if (kLightroomSilentKeys.contains(key)) return '';
  for (final (pattern, label) in kLightroomSkippedLabels) {
    final hit = pattern.endsWith('*')
        ? key.startsWith(pattern.substring(0, pattern.length - 1))
        : key == pattern;
    if (hit) return label;
  }
  return null;
}
