#version 460 core
// Lumen NR-lite pre-pass (engine lumen-1): 5x5 bilateral on luma (range
// weight from the luminance strength) + spatial chroma blur (color strength).
// Layout: finish_uniforms.dart DenoiseUniforms (6 floats). Skipped at 0/0.
#include <flutter/runtime_effect.glsl>
#include "lib/common.glsl"

precision highp float;

uniform vec2 uSize;  // 0-1 image size (px)
uniform vec4 uNr;    // 2-5 luminance 0-1, color 0-1, 0, 0

uniform sampler2D uImage;  // sRGB source (FilterQuality.none)

out vec4 fragColor;

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec3 c0 = texture(uImage, px / uSize).rgb;
  float y0 = dot(c0, REC709);
  float sr = mix(0.01, 0.15, uNr.x);
  float ySum = 0.0;
  float yW = 0.0;
  vec3 cSum = vec3(0.0);
  float cW = 0.0;
  for (int j = -2; j <= 2; j++) {
    for (int i = -2; i <= 2; i++) {
      vec2 o = vec2(float(i), float(j));
      vec3 ci = texture(uImage, (px + o) / uSize).rgb;
      float yi = dot(ci, REC709);
      float ws = exp(-dot(o, o) / (2.0 * 1.5 * 1.5));
      float wr = exp(-(yi - y0) * (yi - y0) / (2.0 * sr * sr));
      ySum += ws * wr * yi;
      yW += ws * wr;
      cSum += ws * (ci - yi);
      cW += ws;
    }
  }
  float y = uNr.x > 0.0 ? mix(y0, ySum / yW, min(1.0, uNr.x * 2.0)) : y0;
  vec3 chroma = mix(c0 - y0, cSum / cW, uNr.y);
  fragColor = vec4(clamp(vec3(y) + chroma, 0.0, 1.0), 1.0);
}
