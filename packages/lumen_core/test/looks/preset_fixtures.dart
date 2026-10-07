/// Preset files written for the tests (replicas of common looks in the
/// formats Lightroom writes; nothing downloaded).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// Lightroom Classic style: settings as attributes, curves and the name as
/// child elements, plus things Lumen skips (profile look with its own
/// parameters, calibration, lens profile, a mask, crop).
const String kBrightAiryXmp = '''<?xml version="1.0" encoding="UTF-8"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
   crs:PresetType="Normal"
   crs:Cluster=""
   crs:UUID="6C1B3D27D1B94B04A8B6E2A2B6C1D9E1"
   crs:SupportsAmount="True"
   crs:SupportsColor="True"
   crs:SupportsMonochrome="True"
   crs:Version="15.4"
   crs:ProcessVersion="11.0"
   crs:WhiteBalance="Custom"
   crs:IncrementalTemperature="+8"
   crs:IncrementalTint="+4"
   crs:Exposure2012="+0.70"
   crs:Contrast2012="-20"
   crs:Highlights2012="-45"
   crs:Shadows2012="+35"
   crs:Whites2012="+15"
   crs:Blacks2012="+10"
   crs:Texture="-10"
   crs:Clarity2012="-8"
   crs:Dehaze="-5"
   crs:Vibrance="+12"
   crs:Saturation="-6"
   crs:HueAdjustmentOrange="-4"
   crs:SaturationAdjustmentOrange="-10"
   crs:LuminanceAdjustmentOrange="+12"
   crs:LuminanceAdjustmentBlue="+20"
   crs:SaturationAdjustmentGreen="-30"
   crs:ColorGradeHighlightLum="0"
   crs:SplitToningHighlightHue="45"
   crs:SplitToningHighlightSaturation="8"
   crs:ColorGradeBlending="60"
   crs:ConvertToGrayscale="False"
   crs:ShadowTint="+5"
   crs:RedHue="+10"
   crs:LensProfileEnable="1"
   crs:HasCrop="True"
   crs:CropTop="0.05"
   crs:PostCropVignetteAmount="-8"
   crs:PostCropVignetteStyle="1"
   crs:Sharpness="40"
   crs:ColorNoiseReduction="25">
   <crs:Name>
    <rdf:Alt>
     <rdf:li xml:lang="x-default">Bright &amp; Airy Wedding</rdf:li>
    </rdf:Alt>
   </crs:Name>
   <crs:Group>
    <rdf:Alt>
     <rdf:li xml:lang="x-default">Weddings</rdf:li>
    </rdf:Alt>
   </crs:Group>
   <crs:ToneCurvePV2012>
    <rdf:Seq>
     <rdf:li>0, 18</rdf:li>
     <rdf:li>64, 70</rdf:li>
     <rdf:li>192, 196</rdf:li>
     <rdf:li>255, 250</rdf:li>
    </rdf:Seq>
   </crs:ToneCurvePV2012>
   <crs:Look>
    <rdf:Description crs:Name="Adobe Portrait" crs:Amount="1">
     <crs:Parameters>
      <rdf:Description crs:Version="15.4" crs:Exposure2012="+3.00"/>
     </crs:Parameters>
    </rdf:Description>
   </crs:Look>
   <crs:MaskGroupBasedCorrections>
    <rdf:Seq>
     <rdf:li>
      <rdf:Description crs:What="Correction" crs:LocalExposure2012="0.5"/>
     </rdf:li>
    </rdf:Seq>
   </crs:MaskGroupBasedCorrections>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
''';

/// Lightroom (cloud) / ACR style: every setting as a child element, B&W.
const String kBwXmp = '''<x:xmpmeta xmlns:x="adobe:ns:meta/">
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description xmlns:c="http://ns.adobe.com/camera-raw-settings/1.0/">
<c:Name><rdf:Alt><rdf:li xml:lang="en-US">Classic B&amp;W</rdf:li></rdf:Alt></c:Name>
<c:ConvertToGrayscale>True</c:ConvertToGrayscale>
<c:Contrast2012>+35</c:Contrast2012>
<c:Clarity2012>+15</c:Clarity2012>
<c:GrayMixerRed>+20</c:GrayMixerRed>
<c:GrayMixerOrange>+15</c:GrayMixerOrange>
<c:GrayMixerBlue>-30</c:GrayMixerBlue>
<c:GrainAmount>25</c:GrainAmount>
<c:GrainSize>30</c:GrainSize>
<c:GrainFrequency>60</c:GrainFrequency>
<c:PostCropVignetteAmount>-20</c:PostCropVignetteAmount>
<c:PostCropVignetteStyle>3</c:PostCropVignetteStyle>
<c:CameraProfile>Adobe Monochrome</c:CameraProfile>
</rdf:Description>
</rdf:RDF>
</x:xmpmeta>''';

/// A legacy Lightroom 6 `.lrtemplate`: moody film, RAW white balance in
/// Kelvin, parametric + RGB curves, split toning, comments and ZSTR.
const String kMoodyFilmLrTemplate = r'''
-- Moody Film, written by hand for the tests
s = {
	id = "8D4C2E6A-1C1F-4F43-9D86-3B6E2A0F9C11",
	internalName = "Moody Film",
	title = ZSTR "$$$/Presets/Moody=Moody Film",
	type = "Develop",
	value = {
		settings = {
			Exposure2012 = -0.35,
			Contrast2012 = 25,
			Highlights2012 = -60,
			Shadows2012 = 20,
			Blacks2012 = 18,
			Clarity2012 = 10,
			Vibrance = -15,
			Saturation = -10,
			WhiteBalance = "Custom",
			Temperature = 4900,
			Tint = 6,
			ParametricShadows = 10,
			ParametricDarks = 5,
			ParametricLights = -5,
			ParametricHighlights = -15,
			ParametricShadowSplit = 25,
			ParametricMidtoneSplit = 50,
			ParametricHighlightSplit = 75,
			ToneCurvePV2012 = { 0, 30, 70, 62, 190, 196, 255, 238, },
			ToneCurvePV2012Blue = { 0, 20, 255, 240, },
			SplitToningShadowHue = 200,
			SplitToningShadowSaturation = 15,
			SplitToningHighlightHue = 40,
			SplitToningHighlightSaturation = 12,
			SplitToningBalance = -20,
			GrainAmount = 30,
			GrainSize = 25,
			GrainFrequency = 50,
			LuminanceSmoothing = 10,
			SharpenRadius = 1.2,
			SharpenDetail = 30,
			SharpenEdgeMasking = 20,
			RedSaturation = -10,
			GradientBasedCorrections = {
				{ What = "Correction", LocalExposure = -0.5 },
			},
			LensProfileEnable = 1,
			ProcessVersion = "10.0",
		},
		uuid = "AF1E4C11-2D2A-4C77-8F8B-29E1C2A2B3C4",
	},
	version = 0,
}
''';

/// Process 2010 basics only (Lightroom 3 era).
const String kLegacyLrTemplate = '''
s = {
  title = "Old Punchy",
  value = { settings = {
    Exposure = 0.5, Contrast = 50, Clarity = 20, FillLight = 30,
    HighlightRecovery = 40, Shadows = 15, Brightness = 60,
  } },
}
''';

/// A sidecar-style XMP that is not a preset at all.
const String kNotAPresetXmp = '''<x:xmpmeta xmlns:x="adobe:ns:meta/">
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/" dc:format="image/jpeg"/>
</rdf:RDF></x:xmpmeta>''';

/// Classic XXE: must be rejected before any entity is looked at.
const String kXxeXmp = '''<?xml version="1.0"?>
<!DOCTYPE x [ <!ENTITY e SYSTEM "file:///etc/passwd"> ]>
<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:Name="&e;"/>
</rdf:RDF></x:xmpmeta>''';

/// "Billion laughs" (entity expansion).
const String kLaughsXmp = '''<?xml version="1.0"?>
<!DOCTYPE lolz [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;&lol;&lol;">]>
<lolz>&lol2;</lolz>''';

/// Lua that is code, not data.
const String kEvilLrTemplate = '''
s = { title = "x", value = { settings = { Exposure2012 = os.execute("rm -rf ~") } } }
''';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

/// A warm-highlights / teal-shadows look (orange skin, teal shadows).
CubeLut tealOrangeLut({int size = 17}) => CubeLut.fromFunction(size, (r, g, b) {
  final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final w = l; // highlights weight
  final s = 1 - l; // shadows weight
  return (
    r + 0.06 * w - 0.05 * s,
    g + 0.01 * w + 0.02 * s,
    b - 0.06 * w + 0.06 * s,
  );
}, title: 'Teal & Orange');

/// Inflate for tests (the app uses the same dart:io codec).
Uint8List inflateRaw(Uint8List deflated, int maxBytes) {
  final out = ZLibDecoder(raw: true).convert(deflated);
  if (out.length > maxBytes) throw const FormatException('too large');
  return Uint8List.fromList(out);
}

/// Builds a zip archive in memory.
Uint8List buildZip(
  Map<String, Uint8List> files, {
  bool deflate = true,
  bool encryptFlag = false,
  bool badCrc = false,
}) {
  final body = BytesBuilder();
  final cd = BytesBuilder();
  var count = 0;
  void u16(BytesBuilder b, int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  files.forEach((name, data) {
    final nameBytes = utf8.encode(name);
    final comp = deflate
        ? Uint8List.fromList(ZLibEncoder(raw: true).convert(data))
        : data;
    final crc = badCrc ? crc32(data) ^ 1 : crc32(data);
    final offset = body.length;
    final flags = (encryptFlag ? 1 : 0) | 0x800;
    final method = deflate ? 8 : 0;
    // Local header.
    u32(body, 0x04034b50);
    u16(body, 20);
    u16(body, flags);
    u16(body, method);
    u16(body, 0);
    u16(body, 0);
    u32(body, crc);
    u32(body, comp.length);
    u32(body, data.length);
    u16(body, nameBytes.length);
    u16(body, 0);
    body
      ..add(nameBytes)
      ..add(comp);
    // Central directory entry.
    u32(cd, 0x02014b50);
    u16(cd, 20);
    u16(cd, 20);
    u16(cd, flags);
    u16(cd, method);
    u16(cd, 0);
    u16(cd, 0);
    u32(cd, crc);
    u32(cd, comp.length);
    u32(cd, data.length);
    u16(cd, nameBytes.length);
    u16(cd, 0);
    u16(cd, 0);
    u16(cd, 0);
    u16(cd, 0);
    u32(cd, 0);
    u32(cd, offset);
    cd.add(nameBytes);
    count++;
  });
  final cdOffset = body.length;
  final cdBytes = cd.takeBytes();
  body.add(cdBytes);
  u32(body, 0x06054b50);
  u16(body, 0);
  u16(body, 0);
  u16(body, count);
  u16(body, count);
  u32(body, cdBytes.length);
  u32(body, cdOffset);
  u16(body, 0);
  return body.takeBytes();
}
