/// Image-scope parameters (research 06 §1.4–1.5): Clean backdrop, Unify
/// backdrop light (Amount + Luminance ±), Stray hairs beyond the figure,
/// Clothing wrinkles and Lint & specks. Slider drags change only these
/// uniforms.
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
    this.clothesWrinkles = 0,
    this.clothesLint = 0,
  });

  factory BackdropParams.fromSettings(PortraitSettings s) => BackdropParams(
    clean: mapLinear(s.imageValue(PortraitIds.bgClean)),
    unify: mapLinear(s.imageValue(PortraitIds.bgUnify)),
    luminance:
        kBackdropLumMax *
        (s.imageValue(PortraitIds.bgUnifyLuminance) / 100).clamp(-1.0, 1.0),
    strays: mapLinear(s.imageValue(PortraitIds.strayHairs)),
    clothesWrinkles: mapLinear(s.imageValue(PortraitIds.clothesWrinkles)),
    clothesLint: mapLinear(s.imageValue(PortraitIds.clothesLint)),
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

  /// Clothing wrinkles and lint removal (0..1).
  final double clothesWrinkles;
  final double clothesLint;

  /// No backdrop or stray-hair value set.
  bool get backdropIdentity =>
      clean == 0 && unify == 0 && luminance == 0 && strays == 0;

  /// No clothes value set.
  bool get clothesIdentity => clothesWrinkles == 0 && clothesLint == 0;

  bool get isIdentity => backdropIdentity && clothesIdentity;

  /// `uBackdropParams` = (clean, unify, luminance, strays).
  List<double> toList() => [clean, unify, luminance, strays];

  /// `uClothesParams` = (wrinkles, lint, active (set by the pass), 0).
  List<double> clothesList() => [clothesWrinkles, clothesLint, 0, 0];

  @override
  bool operator ==(Object other) =>
      other is BackdropParams &&
      other.clean == clean &&
      other.unify == unify &&
      other.luminance == luminance &&
      other.strays == strays &&
      other.clothesWrinkles == clothesWrinkles &&
      other.clothesLint == clothesLint;

  @override
  int get hashCode => Object.hash(
    clean,
    unify,
    luminance,
    strays,
    clothesWrinkles,
    clothesLint,
  );
}

/// True when [s] sets a backdrop or stray-hair value: the retouch maps then
/// need the person (and hair) rasters.
bool needsBackdropMaps(PortraitSettings s) =>
    !BackdropParams.fromSettings(s).backdropIdentity;

/// True when [s] sets a clothes value: the retouch maps then need the
/// clothes raster.
bool needsClothesMaps(PortraitSettings s) =>
    !BackdropParams.fromSettings(s).clothesIdentity;

/// True when [s] retouches anything: face edits, forced spot removals or
/// image-scope backdrop / clothes edits. Gate retouch work on this, not on
/// `hasFaceEdits` alone.
bool portraitNeedsRetouch(PortraitSettings s) =>
    s.hasFaceEdits || needsBackdropMaps(s) || needsClothesMaps(s);
