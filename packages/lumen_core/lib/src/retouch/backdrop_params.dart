/// Image-scope backdrop and stray-hair parameters (research 06 §1.4–1.5):
/// Clean backdrop, Unify backdrop light (Amount + Luminance ±) and Stray
/// hairs beyond the figure. Slider drags change only these uniforms.
library;

import '../model/portrait.dart';
import 'slider_mapping.dart';

/// OkLab L shift of the backdrop at Luminance ±100.
const double kBackdropLumMax = 0.12;

/// Internal backdrop parameters (already mapped from the UI values).
class BackdropParams {
  const BackdropParams({
    this.clean = 0,
    this.unify = 0,
    this.luminance = 0,
    this.strays = 0,
  });

  factory BackdropParams.fromSettings(PortraitSettings s) => BackdropParams(
    clean: mapLinear(s.imageValue(PortraitIds.bgClean)),
    unify: mapLinear(s.imageValue(PortraitIds.bgUnify)),
    luminance:
        kBackdropLumMax *
        (s.imageValue(PortraitIds.bgUnifyLuminance) / 100).clamp(-1.0, 1.0),
    strays: mapLinear(s.imageValue(PortraitIds.strayHairs)),
  );

  static const identity = BackdropParams();

  /// Clean backdrop blend (0..1).
  final double clean;

  /// Unify lighting amount (0..1).
  final double unify;

  /// Backdrop L shift (OkLab, ±[kBackdropLumMax]).
  final double luminance;

  /// Stray hairs beyond the figure (0..1).
  final double strays;

  bool get isIdentity =>
      clean == 0 && unify == 0 && luminance == 0 && strays == 0;

  /// `uBackdropParams` = (clean, unify, luminance, strays).
  List<double> toList() => [clean, unify, luminance, strays];

  @override
  bool operator ==(Object other) =>
      other is BackdropParams &&
      other.clean == clean &&
      other.unify == unify &&
      other.luminance == luminance &&
      other.strays == strays;

  @override
  int get hashCode => Object.hash(clean, unify, luminance, strays);
}

/// True when [s] sets a backdrop or stray-hair value: the retouch maps then
/// need the person (and hair) rasters.
bool needsBackdropMaps(PortraitSettings s) =>
    !BackdropParams.fromSettings(s).isIdentity;

/// True when [s] retouches anything: face edits, forced spot removals or
/// image-scope backdrop edits. Gate retouch work on this, not on
/// `hasFaceEdits` alone.
bool portraitNeedsRetouch(PortraitSettings s) =>
    s.hasFaceEdits || needsBackdropMaps(s);
