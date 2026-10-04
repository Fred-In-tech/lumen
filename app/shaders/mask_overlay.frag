#version 460 core
// Lumen mask overlay: one mask's coverage as a premultiplied color tint in
// OUTPUT space (same geometry mapping as develop.frag), for the UI's
// "show overlay". CPU twin: mask_overlay.dart. 26 floats, 1 sampler.
#include <flutter/runtime_effect.glsl>
#include "lib/common.glsl"

precision highp float;

uniform vec2 uOutSize;   // 0-1   pass size (px)
uniform vec4 uTile;      // 2-5   tile offset xy, full output wh
uniform vec4 uCrop;      // 6-9   l, t, r, b
uniform vec4 uGeom;      // 10-13 angle rad, rotate90, flipH, flipV
uniform vec4 uSrc;       // 14-17 source wh, mask grid wh
uniform vec4 uSlot;      // 18-21 one-hot channel of the mask in its atlas
uniform vec4 uTint;      // 22-25 r, g, b, max alpha (straight)

uniform sampler2D uMasks;  // the atlas holding the mask (FilterQuality.none)

out vec4 fragColor;

vec4 tap(vec2 t) {
  vec2 size = vec2(2.0 * uSrc.z, uSrc.w);
  return vec4(texture(uMasks, (t + 0.5) / size).rgb,
              texture(uMasks, (t + vec2(uSrc.z + 0.5, 0.5)) / size).r);
}

void main() {
  vec2 px = min(FlutterFragCoord().xy, uOutSize);
  vec2 uv = (px + uTile.xy) / uTile.zw;
  vec2 suv = sourceUvFrom(uv, uCrop, uGeom, uSrc.xy);
  if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec2 lo;
  vec2 hi;
  vec2 f;
  maskTaps(suv, uSrc.zw, lo, hi, f);
  vec4 c = bilerp(tap(lo), tap(vec2(hi.x, lo.y)), tap(vec2(lo.x, hi.y)),
                  tap(hi), f);
  float a = clamp(dot(c, uSlot), 0.0, 1.0) * uTint.a;
  fragColor = vec4(uTint.rgb * a, a);
}
