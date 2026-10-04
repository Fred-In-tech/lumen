#version 460 core
// Lumen mask overlay: one mask's coverage as a premultiplied color tint in
// OUTPUT space (same geometry mapping as develop.frag), for the UI's
// "show overlay". CPU twin: mask_overlay.dart. 30 floats, 2 samplers.
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
uniform vec4 uWarpInfo;  // 26-29 warp grid wh, range, enabled (as develop)

uniform sampler2D uMasks;  // the atlas holding the mask (FilterQuality.none)
uniform sampler2D uWarp;   // warp field atlas (FilterQuality.none)

out vec4 fragColor;

vec4 tap(vec2 t) {
  vec2 size = vec2(2.0 * uSrc.z, uSrc.w);
  return vec4(texture(uMasks, (t + 0.5) / size).rgb,
              texture(uMasks, (t + vec2(uSrc.z + 0.5, 0.5)) / size).r);
}

// Same as develop.frag warpUv() (kept in sync; samplers cannot be passed).
vec2 warpTap(vec2 t) {
  vec2 size = vec2(2.0 * uWarpInfo.x, uWarpInfo.y);
  return vec2(warpCode(texture(uWarp, (t + 0.5) / size).rg),
              warpCode(texture(uWarp, (t + vec2(uWarpInfo.x + 0.5, 0.5)) / size).rg)) -
         32767.0;
}

vec2 warpUv(vec2 suv) {
  if (uWarpInfo.w < 0.5) return suv;
  vec2 lo;
  vec2 hi;
  vec2 f;
  maskTaps(suv, uWarpInfo.xy, lo, hi, f);
  vec2 top = mix(warpTap(lo), warpTap(vec2(hi.x, lo.y)), f.x);
  vec2 bot = mix(warpTap(vec2(lo.x, hi.y)), warpTap(hi), f.x);
  return suv + mix(top, bot, f.y) / 32767.0 * uWarpInfo.z;
}

void main() {
  vec2 px = min(FlutterFragCoord().xy, uOutSize);
  vec2 uv = (px + uTile.xy) / uTile.zw;
  vec2 suv = warpUv(sourceUvFrom(uv, uCrop, uGeom, uSrc.xy));
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
