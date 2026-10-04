#version 460 core
// Lumen finish pass (engine lumen-1): luma unsharp mask -> grain -> dither.
// Layout: finish_uniforms.dart (18 floats). Skipped when sharpen = grain = 0.
#include <flutter/runtime_effect.glsl>
#include "lib/common.glsl"

precision highp float;

uniform vec2 uSize;      // 0-1   pass size (px)
uniform vec4 uVec0[4];
#define uTile uVec0[0]  // 2-5   offset xy in the full output, full wh
#define uSharpen uVec0[1]  // 6-9   amount 0-1.5, radius px, detail, masking
#define uGrain uVec0[2]  // 10-13 amount, size px (full res), roughness, seed
#define uDither uVec0[3]  // 14-17 enabled, previewScale, 0, 0

uniform sampler2D uImage;  // develop output (FilterQuality.none)

out vec4 fragColor;

float lumaTap(vec2 px, vec2 o) {
  return dot(texture(uImage, (px + o) / uSize).rgb, REC709);
}

float tanhApprox(float x) {
  float e = exp(2.0 * clamp(x, -10.0, 10.0));
  return (e - 1.0) / (e + 1.0);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash12(i);
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec3 c = texture(uImage, px / uSize).rgb;
  float scale = max(uDither.y, 1.0);
  vec2 gpx = px + uTile.xy;  // global pixel position, seamless across tiles
  if (uSharpen.x > 0.0) {
    float sig = max(uSharpen.y / scale, 0.5);
    float sum = 0.0;
    float wsum = 0.0;
    for (int j = -2; j <= 2; j++) {
      for (int i = -2; i <= 2; i++) {
        vec2 o = vec2(float(i), float(j));
        float w = exp(-dot(o, o) / (2.0 * sig * sig));
        sum += w * lumaTap(px, o);
        wsum += w;
      }
    }
    float y0 = dot(c, REC709);
    float hp = y0 - sum / wsum;
    float lim = mix(0.02, 0.25, uSharpen.z);
    hp = lim * tanhApprox(hp / lim);
    float edge = 1.0;
    if (uSharpen.w > 0.0) {
      vec2 g = vec2(lumaTap(px, vec2(1.0, 0.0)) - lumaTap(px, vec2(-1.0, 0.0)),
                    lumaTap(px, vec2(0.0, 1.0)) - lumaTap(px, vec2(0.0, -1.0)));
      float t = uSharpen.w * 0.08;
      edge = smoothstep(t, t + 0.02, length(g));
    }
    c += vec3(uSharpen.x * edge * hp);
  }
  if (uGrain.x > 0.0) {
    vec2 p = gpx * scale / max(uGrain.y, 0.5) + uGrain.w * 17.0;
    float n = vnoise(p) * (1.0 - 0.5 * uGrain.z) +
              vnoise(p * 2.03 + 7.1) * 0.5 * uGrain.z;
    float l = clamp(dot(c, REC709), 0.0, 1.0);
    float amp = uGrain.x * 0.4 * l * (1.0 - l) / sqrt(scale);
    c += vec3(n * amp);
  }
  if (uDither.x > 0.5) {
    float d = hash12(gpx) + hash12(gpx + 71.3) - 1.0;  // triangular, -1..1
    c += vec3(d * 0.5 / 255.0);
  }
  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
