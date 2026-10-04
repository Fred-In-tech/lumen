/// Loads every Lumen `FragmentProgram` once.
///
/// Public API:
/// * `ShaderLibrary.load()` → `Future<ShaderLibrary>`; throws
///   [ShaderLoadException] naming the asset if a shader fails to load
///   (fails loudly, never falls back silently).
/// * `develop`, `finish`, `denoise`, `maskOverlay`, `retouch`: the programs; create a fresh
///   `FragmentShader` per pass with `program.fragmentShader()`.
library;

import 'dart:ui' as ui;

/// A shader asset could not be loaded or compiled for this backend.
class ShaderLoadException implements Exception {
  const ShaderLoadException(this.asset, this.cause);

  final String asset;
  final Object cause;

  @override
  String toString() => 'ShaderLoadException($asset): $cause';
}

class ShaderLibrary {
  const ShaderLibrary._(
    this.develop,
    this.finish,
    this.denoise,
    this.maskOverlay,
    this.retouch,
  );

  static const developAsset = 'shaders/develop.frag';
  static const finishAsset = 'shaders/finish.frag';
  static const denoiseAsset = 'shaders/denoise.frag';
  static const maskOverlayAsset = 'shaders/mask_overlay.frag';
  static const retouchAsset = 'shaders/retouch.frag';

  static Future<ShaderLibrary>? _shared;

  /// Loads (once per process) and caches the programs.
  static Future<ShaderLibrary> load() => _shared ??= _load();

  static Future<ShaderLibrary> _load() async {
    try {
      final programs = await Future.wait([
        _program(developAsset),
        _program(finishAsset),
        _program(denoiseAsset),
        _program(maskOverlayAsset),
        _program(retouchAsset),
      ]);
      return ShaderLibrary._(
        programs[0],
        programs[1],
        programs[2],
        programs[3],
        programs[4],
      );
    } on Object {
      _shared = null;
      rethrow;
    }
  }

  static Future<ui.FragmentProgram> _program(String asset) async {
    try {
      return await ui.FragmentProgram.fromAsset(asset);
    } on Exception catch (e) {
      throw ShaderLoadException(asset, e);
    }
  }

  /// Uber develop pass (198 floats, 7 samplers).
  final ui.FragmentProgram develop;

  /// Sharpen → grain → dither (18 floats, 1 sampler).
  final ui.FragmentProgram finish;

  /// NR-lite bilateral pre-pass (6 floats, 1 sampler).
  final ui.FragmentProgram denoise;

  /// One mask's coverage as a tint in output space (30 floats, 2 samplers).
  final ui.FragmentProgram maskOverlay;

  /// Portrait retouch pass R (206 floats, 7 samplers).
  final ui.FragmentProgram retouch;
}
