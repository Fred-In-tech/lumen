import 'dart:convert';
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'lut_fixtures.dart';

/// A Lightroom preset with something Lumen skips (calibration, lens).
const String kAiryXmp = '''<x:xmpmeta xmlns:x="adobe:ns:meta/">
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
 crs:Exposure2012="+0.60" crs:Contrast2012="-15" crs:Shadows2012="+30"
 crs:Vibrance="+10" crs:RedHue="+8" crs:LensProfileEnable="1"
 crs:Temperature="6500" crs:WhiteBalance="Custom">
<crs:Name><rdf:Alt><rdf:li xml:lang="x-default">Airy Wedding</rdf:li></rdf:Alt></crs:Name>
</rdf:Description></rdf:RDF></x:xmpmeta>''';

const String kFilmLrTemplate = '''
s = { title = "Moody Film", type = "Develop", value = { settings = {
  Exposure2012 = -0.4, Highlights2012 = -50, Saturation = -15,
  ToneCurvePV2012 = { 0, 25, 255, 240 },
} } }
''';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

List<LookImportFile> sampleLookFiles() => [
  LookImportFile('Airy.xmp', bytesOf(kAiryXmp)),
  LookImportFile('Film.lrtemplate', bytesOf(kFilmLrTemplate)),
  LookImportFile('Teal.cube', bytesOf(tealOrangeLut(size: 9).toCubeText())),
  LookImportFile('notes.cube', bytesOf('LUT_3D_SIZE 2\n0 0 0\n')),
];

/// A black & white preset (settings as child elements, Lightroom cloud).
const String kBwXmp = '''<x:xmpmeta xmlns:x="adobe:ns:meta/">
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/">
<crs:Name><rdf:Alt><rdf:li xml:lang="x-default">Classic B&amp;W</rdf:li></rdf:Alt></crs:Name>
<crs:ConvertToGrayscale>True</crs:ConvertToGrayscale>
<crs:Contrast2012>+30</crs:Contrast2012>
<crs:Clarity2012>+10</crs:Clarity2012>
<crs:GrayMixerOrange>+20</crs:GrayMixerOrange>
<crs:GrayMixerBlue>-25</crs:GrayMixerBlue>
<crs:GrainAmount>20</crs:GrainAmount>
<crs:PostCropVignetteAmount>-15</crs:PostCropVignetteAmount>
<crs:CameraProfile>Adobe Monochrome</crs:CameraProfile>
</rdf:Description></rdf:RDF></x:xmpmeta>''';

/// A bright & airy wedding look, as a photographer would build it.
const String kBrightAiryXmp = '''<x:xmpmeta xmlns:x="adobe:ns:meta/">
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
 crs:Exposure2012="+0.55" crs:Contrast2012="-18" crs:Highlights2012="-40"
 crs:Shadows2012="+35" crs:Whites2012="+12" crs:Blacks2012="+15"
 crs:Vibrance="+8" crs:Saturation="-8" crs:IncrementalTemperature="+6"
 crs:LuminanceAdjustmentOrange="+12" crs:SaturationAdjustmentOrange="-8"
 crs:SaturationAdjustmentGreen="-30" crs:LuminanceAdjustmentBlue="+15"
 crs:ShadowTint="+4" crs:LensProfileEnable="1">
<crs:Name><rdf:Alt><rdf:li xml:lang="x-default">Bright &amp; Airy</rdf:li></rdf:Alt></crs:Name>
<crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 20</rdf:li><rdf:li>70, 74</rdf:li><rdf:li>190, 196</rdf:li><rdf:li>255, 250</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
</rdf:Description></rdf:RDF></x:xmpmeta>''';

/// A moody film look in the legacy format, with RAW white balance.
const String kMoodyFilmLrTemplate = '''
s = { title = "Moody Film", type = "Develop", value = { settings = {
  Exposure2012 = -0.35, Contrast2012 = 20, Highlights2012 = -55,
  Shadows2012 = 15, Blacks2012 = 20, Vibrance = -15, Saturation = -12,
  WhiteBalance = "Custom", Temperature = 5000, Tint = 8,
  ToneCurvePV2012 = { 0, 32, 64, 60, 192, 196, 255, 236 },
  ToneCurvePV2012Blue = { 0, 18, 255, 240 },
  SplitToningShadowHue = 205, SplitToningShadowSaturation = 14,
  SplitToningHighlightHue = 42, SplitToningHighlightSaturation = 10,
  GrainAmount = 25, GrainSize = 30, RedSaturation = -8,
} } }
''';

/// Every fixture look: three presets and the teal & orange LUT.
List<LookImportFile> fixtureLookFiles() => [
  LookImportFile('Bright & Airy.xmp', bytesOf(kBrightAiryXmp)),
  LookImportFile('Moody Film.lrtemplate', bytesOf(kMoodyFilmLrTemplate)),
  LookImportFile('Classic BW.xmp', bytesOf(kBwXmp)),
  LookImportFile('Teal Orange.cube', bytesOf(tealOrangeLut().toCubeText())),
];
