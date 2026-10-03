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

// sRGB decode of an encoded value in 0..1 (srgb.dart srgbToLinear).
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
