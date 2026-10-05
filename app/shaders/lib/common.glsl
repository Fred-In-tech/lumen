// Lumen engine lumen-1: helpers shared by every shader.
// Mirrors packages/lumen_core/lib/src/{color,render}/*.dart. Constants named
// k* here are the same values as engine_constants.dart.

const vec3 REC709 = vec3(0.2126, 0.7152, 0.0722);

// IEC 61966-2-1 sRGB encode, clamped to 0..1 (srgb.dart linearToSrgb).
float srgbEncode1(float x) {
  float c = clamp(x, 0.0, 1.0);
  return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

vec3 srgbEncode(vec3 c) {
  return vec3(srgbEncode1(c.r), srgbEncode1(c.g), srgbEncode1(c.b));
}

// Extended sRGB encode: srgbEncode1 without the upper clamp, so values
// above display white keep their range in a float target (srgb.dart
// linearToSrgbExtended). Equal to srgbEncode1 inside 0..1; an 8-bit target
// clamps the rest itself.
float srgbEncodeExt1(float x) {
  float c = max(x, 0.0);
  return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

vec3 srgbEncodeExt(vec3 c) {
  return vec3(srgbEncodeExt1(c.r), srgbEncodeExt1(c.g), srgbEncodeExt1(c.b));
}

// Base highlight shoulder of a float source (float_buffer.dart
// highlightShoulder): identity up to the knee, quadratic roll-off reaching
// 1.0 at 2 - knee, 1.0 beyond. e >= 0, 0 < knee < 1.
float shoulder(float e, float knee) {
  if (e <= knee) return e;
  float t = (e - knee) / (2.0 * (1.0 - knee));
  return t >= 1.0 ? 1.0 : knee + (1.0 - knee) * (2.0 * t - t * t);
}

// sRGB decode of an encoded value (srgb.dart srgbToLinear). Values above
// 1.0 (float sources) continue on the same curve; negatives give 0.
float srgbDecode1(float e) {
  float c = max(e, 0.0);
  return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

vec3 srgbDecode(vec3 e) {
  return vec3(srgbDecode1(e.r), srgbDecode1(e.g), srgbDecode1(e.b));
}

// 16-bit value packed as R = high byte, G = low byte (lut_packing.dart).
float unpack16(vec2 rg) {
  return dot(rg, vec2(65280.0, 255.0)) / 65535.0;
}

// (log2(max(Y, 2^-14)) + kLogLumaOffset) / kLogLumaRange (aux_maps.dart).
float normLogLuma(float y) {
  return clamp((log2(max(y, 1.0 / 16384.0)) + 14.0) / 16.0, 0.0, 1.0);
}

// Björn Ottosson's OkLab (oklab.dart).
vec3 linSrgbToOklab(vec3 c) {
  vec3 lms = vec3(
    dot(vec3(0.4122214708, 0.5363325363, 0.0514459929), c),
    dot(vec3(0.2119034982, 0.6806995451, 0.1073969566), c),
    dot(vec3(0.0883024619, 0.2817188376, 0.6299787005), c));
  lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
  return vec3(
    dot(vec3(0.2104542553, 0.7936177850, -0.0040720468), lms),
    dot(vec3(1.9779984951, -2.4285922050, 0.4505937099), lms),
    dot(vec3(0.0259040371, 0.7827717662, -0.8086757660), lms));
}

vec3 oklabToLinSrgb(vec3 o) {
  vec3 lms = vec3(
    o.x + 0.3963377774 * o.y + 0.2158037573 * o.z,
    o.x - 0.1055613458 * o.y - 0.0638541728 * o.z,
    o.x - 0.0894841775 * o.y - 1.2914855480 * o.z);
  lms = lms * lms * lms;
  return vec3(
    dot(vec3(4.0767416621, -3.3077115913, 0.2309699292), lms),
    dot(vec3(-1.2684380046, 2.6097574011, -0.3413193965), lms),
    dot(vec3(-0.0041960863, -0.7034186147, 1.7076147010), lms));
}

// OkLab hue in degrees 0..360 (color_ops.dart okHue). atan(0, 0) is
// undefined in GLSL, so neutrals get hue 0.
float okHue(vec2 ab) {
  if (dot(ab, ab) < 1e-14) return 0.0;
  float h = degrees(atan(ab.y, ab.x));
  return h < 0.0 ? h + 360.0 : h;
}

// Float hash without sine (Dave Hoskins, MIT): no uint needed.
float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ---- Geometry (geometry_mapping.dart sourceUvFor) --------------------------
// crop = l, t, r, b; geom = angle rad, rotate90, flipH, flipV; src = wh.
vec2 sourceUvFrom(vec2 outUv, vec4 crop, vec4 geom, vec2 src) {
  vec2 c = mix(crop.xy, crop.zw, outUv);
  float k = mod(floor(geom.y + 0.5), 4.0);
  bool odd = k == 1.0 || k == 3.0;
  vec2 dims = odd ? src.yx : src.xy;
  if (geom.x != 0.0) {
    vec2 p = (c - 0.5) * dims;
    float ca = cos(geom.x);
    float sa = sin(geom.x);
    c = vec2(p.x * ca + p.y * sa, -p.x * sa + p.y * ca) / dims + 0.5;
  }
  if (geom.z > 0.5) c.x = 1.0 - c.x;
  if (geom.w > 0.5) c.y = 1.0 - c.y;
  if (k == 1.0) return vec2(c.y, 1.0 - c.x);
  if (k == 2.0) return vec2(1.0 - c.x, 1.0 - c.y);
  if (k == 3.0) return vec2(1.0 - c.y, c.x);
  return c;
}

// ---- Mask atlases (mask_rasterizer.dart MaskAtlases) -----------------------
// Bilinear taps over texel centers of a grid-sized tile: lo/hi texel coords
// (clamped) and the fractional weights.
void maskTaps(vec2 uv, vec2 grid, out vec2 lo, out vec2 hi, out vec2 f) {
  vec2 p = uv * grid - 0.5;
  vec2 i0 = floor(p);
  f = p - i0;
  lo = clamp(i0, vec2(0.0), grid - 1.0);
  hi = clamp(i0 + 1.0, vec2(0.0), grid - 1.0);
}

vec4 bilerp(vec4 a, vec4 b, vec4 c, vec4 d, vec2 f) {
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ---- Local tone (local_adjust.dart localTone, tone_lut.dart curves) --------
float contrastCurveN(float x, float c) {
  float g = exp2(clamp(c, -1.0, 1.0));
  const float p = 0.46;
  return x < p ? p * pow(x / p, g)
               : 1.0 - (1.0 - p) * pow((1.0 - x) / (1.0 - p), g);
}

float levelsN(float x, float w, float b) {
  float wIn = w > 0.0 ? 1.0 - 0.25 * w : 1.0;
  float wOut = w < 0.0 ? 1.0 + 0.25 * w : 1.0;
  float bIn = b < 0.0 ? -0.25 * b : 0.0;
  float bOut = b > 0.0 ? 0.25 * b : 0.0;
  return bOut + (wOut - bOut) * clamp((x - bIn) / (wIn - bIn), 0.0, 1.0);
}

// cwb = local contrast, whites, blacks (normalized, clamped to -1..1).
float localTone(float x, vec3 cwb) {
  float y = clamp(x, 0.0, 1.0);
  if (cwb.x != 0.0) y = contrastCurveN(y, cwb.x);
  if (cwb.y != 0.0 || cwb.z != 0.0) y = levelsN(y, cwb.y, cwb.z);
  return y;
}

// RGBTone: max -> tmx, min -> tmn, middle channel by relative position.
vec3 hueTone(vec3 c, float mx, float mn, float tmx, float tmn) {
  if (mx - mn < 1e-6) return vec3(tmx);
  return tmn + (c - mn) * ((tmx - tmn) / (mx - mn));
}

// ---- Warp field (warp/warp_field.dart) --------------------------------------
// 16-bit code of a packed (hi, lo) texel, rounded so 32767 (= no move) is
// exact; displacement = (code - 32767) / 32767 * range.
float warpCode(vec2 rg) {
  return floor(dot(rg, vec2(65280.0, 255.0)) + 0.5);
}
