import '../auto/retouch_needs.dart';
import 'portrait.dart';

/// Built-in portrait retouch recipes (Evoto-style one-click retouch).
abstract final class PortraitPresets {
  /// Natural studio retouch for every face. Values sit in the range retouchers
  /// recommend for headshots (eyes 30–50 %, smoothing below the "plastic"
  /// zone), with gentler skin work on children and seniors.
  static const Map<String, double> natural = {
    PortraitIds.skinSoftening: 40,
    PortraitIds.skinEven: 30,
    PortraitIds.skinShine: 30,
    PortraitIds.acne: 80,
    PortraitIds.wrinkleForehead: 30,
    PortraitIds.wrinkleFrown: 30,
    PortraitIds.wrinkleCrowsFeet: 25,
    PortraitIds.wrinkleSmile: 20,
    PortraitIds.wrinkleMarionette: 20,
    PortraitIds.darkCircles: 40,
    PortraitIds.eyeBags: 35,
    PortraitIds.eyeWhites: 35,
    PortraitIds.iris: 30,
    PortraitIds.redVein: 50,
    PortraitIds.teethBrightness: 25,
    PortraitIds.teethDesaturate: 30,
  };

  /// Child skin keeps its texture; seniors keep character lines.
  static const Map<FaceGroup, Map<String, double>> groupOverrides = {
    FaceGroup.child: {
      PortraitIds.skinSoftening: 15,
      PortraitIds.acne: 40,
      PortraitIds.eyeBags: 0,
    },
    FaceGroup.senior: {
      PortraitIds.skinSoftening: 30,
      PortraitIds.eyeBags: 25,
      PortraitIds.wrinkleForehead: 15,
      PortraitIds.wrinkleCrowsFeet: 10,
      PortraitIds.wrinkleSmile: 10,
    },
  };

  /// Applies [natural] to the All group (plus group overrides), keeping any
  /// per-person values and image-scope settings from [current].
  static PortraitSettings autoRetouch(PortraitSettings current) {
    var next = PortraitSettings(
      individuals: current.individuals,
      image: current.image,
    );
    for (final e in natural.entries) {
      next = next.withGroupValue(FaceGroup.all, e.key, e.value);
    }
    for (final g in groupOverrides.entries) {
      for (final e in g.value.entries) {
        next = next.withGroupValue(g.key, e.key, e.value);
      }
    }
    return next;
  }

  // ---------------------------------------------------------------------
  // Need-scaled Auto Retouch (research 07 §7.1 step 10).

  /// `value = lo + (hi − lo) · need` per slider. Every `hi` stays below the
  /// "plastic" zone (smoothing past ~60 erases pores; eyes past ~50 glow),
  /// so even the strongest auto retouch looks photographic.
  static const Map<String, (double, double)> needRanges = {
    PortraitIds.skinSoftening: (15, 55),
    PortraitIds.skinEven: (10, 45),
    PortraitIds.skinShine: (10, 55),
    PortraitIds.acne: (30, 90),
    PortraitIds.wrinkleForehead: (5, 45),
    PortraitIds.wrinkleFrown: (5, 45),
    PortraitIds.wrinkleCrowsFeet: (5, 40),
    PortraitIds.wrinkleSmile: (5, 40),
    PortraitIds.wrinkleMarionette: (5, 40),
    PortraitIds.darkCircles: (10, 60),
    PortraitIds.eyeBags: (5, 50),
    PortraitIds.redVein: (20, 70),
    PortraitIds.teethBrightness: (10, 40),
    PortraitIds.teethDesaturate: (10, 50),
  };

  /// Eye polish that does not depend on a measured problem.
  static const Map<String, double> eyePolish = {
    PortraitIds.eyeWhites: 35,
    PortraitIds.iris: 30,
  };

  /// Upper limits per group: children keep their skin, seniors keep
  /// character lines (applied on top of the measured values).
  static const Map<FaceGroup, Map<String, double>> groupCaps = {
    FaceGroup.child: {
      PortraitIds.skinSoftening: 15,
      PortraitIds.skinEven: 20,
      PortraitIds.acne: 40,
      PortraitIds.eyeBags: 0,
      PortraitIds.darkCircles: 25,
      PortraitIds.wrinkleForehead: 0,
      PortraitIds.wrinkleFrown: 0,
      PortraitIds.wrinkleCrowsFeet: 0,
      PortraitIds.wrinkleSmile: 0,
      PortraitIds.wrinkleMarionette: 0,
    },
    FaceGroup.senior: {
      PortraitIds.skinSoftening: 30,
      PortraitIds.eyeBags: 25,
      PortraitIds.wrinkleForehead: 15,
      PortraitIds.wrinkleFrown: 15,
      PortraitIds.wrinkleCrowsFeet: 10,
      PortraitIds.wrinkleSmile: 10,
      PortraitIds.wrinkleMarionette: 15,
    },
  };

  /// Every slider the auto retouch writes.
  static final Set<String> autoIds = {
    ...natural.keys,
    ...needRanges.keys,
    ...eyePolish.keys,
  };

  /// A group's value differs from All by at least this much before it
  /// gets its own override ("faces differ a lot").
  static const double groupSplit = 12;

  /// Key of a hand-set value (see `manualPortraitLocks`).
  static String lockKey(FaceGroup group, String id) => '${group.name}/$id';

  /// Slider values for a face with [needs].
  static Map<String, double> valuesFor(FaceNeeds needs) {
    double scaled(String id, double need) {
      final (lo, hi) = needRanges[id]!;
      return (lo + (hi - lo) * need.clamp(0.0, 1.0)).roundToDouble();
    }

    final under = needs.underEye;
    return {
      PortraitIds.skinSoftening: scaled(
        PortraitIds.skinSoftening,
        0.75 * needs.roughness + 0.25 * needs.unevenness,
      ),
      PortraitIds.skinEven: scaled(PortraitIds.skinEven, needs.unevenness),
      PortraitIds.skinShine: scaled(PortraitIds.skinShine, needs.shine),
      PortraitIds.acne: scaled(PortraitIds.acne, needs.blemish),
      PortraitIds.wrinkleForehead: scaled(
        PortraitIds.wrinkleForehead,
        needs.wrinkle(WrinkleZone.forehead),
      ),
      PortraitIds.wrinkleFrown: scaled(
        PortraitIds.wrinkleFrown,
        needs.wrinkle(WrinkleZone.frown),
      ),
      PortraitIds.wrinkleCrowsFeet: scaled(
        PortraitIds.wrinkleCrowsFeet,
        needs.wrinkle(WrinkleZone.crowsFeet),
      ),
      PortraitIds.wrinkleSmile: scaled(
        PortraitIds.wrinkleSmile,
        needs.wrinkle(WrinkleZone.smile),
      ),
      PortraitIds.wrinkleMarionette: scaled(
        PortraitIds.wrinkleMarionette,
        needs.wrinkle(WrinkleZone.marionette),
      ),
      PortraitIds.darkCircles: scaled(PortraitIds.darkCircles, under),
      PortraitIds.eyeBags: scaled(PortraitIds.eyeBags, under),
      PortraitIds.redVein: scaled(PortraitIds.redVein, needs.scleraRed),
      PortraitIds.teethBrightness: scaled(
        PortraitIds.teethBrightness,
        needs.teethDark,
      ),
      PortraitIds.teethDesaturate: scaled(
        PortraitIds.teethDesaturate,
        needs.teethYellow,
      ),
      ...eyePolish,
    };
  }

  /// Need-scaled Auto Retouch: values for the All group from the typical
  /// face, a group override where that group's faces differ by at least
  /// [groupSplit], and the child/senior [groupCaps]. Without [needs] (no
  /// analysis) it falls back to the static [natural] recipe. Keys in
  /// [locked] (`lockKey`) are never written, nor are individuals, image
  /// scope values or spots: those stay exactly as in [current].
  static PortraitSettings autoRetouchFor(
    PortraitSettings current,
    RetouchNeeds? needs, {
    Set<String> locked = const {},
  }) {
    final Map<String, double> all;
    final groupValues = <FaceGroup, Map<String, double>>{};
    if (needs == null || needs.isEmpty) {
      all = {...natural, ...eyePolish};
      for (final e in groupOverrides.entries) {
        groupValues[e.key] = {...e.value};
      }
    } else {
      all = valuesFor(FaceNeeds.mean(needs.faces));
      final byGroup = <FaceGroup, List<FaceNeeds>>{};
      for (final f in needs.faces) {
        if (f.group != FaceGroup.all) {
          byGroup.putIfAbsent(f.group, () => []).add(f);
        }
      }
      for (final e in byGroup.entries) {
        final v = valuesFor(FaceNeeds.mean(e.value, group: e.key));
        groupValues[e.key] = {
          for (final id in v.keys)
            if ((v[id]! - all[id]!).abs() >= groupSplit) id: v[id]!,
        };
      }
    }
    for (final e in groupCaps.entries) {
      final g = groupValues.putIfAbsent(e.key, () => {});
      for (final cap in e.value.entries) {
        final v = g[cap.key] ?? all[cap.key] ?? 0;
        if (v > cap.value) g[cap.key] = cap.value;
      }
    }
    var next = current;
    for (final e in all.entries) {
      if (!locked.contains(lockKey(FaceGroup.all, e.key))) {
        next = next.withGroupValue(FaceGroup.all, e.key, e.value);
      }
    }
    for (final g in FaceGroup.values) {
      if (g == FaceGroup.all) continue;
      final values = groupValues[g] ?? const {};
      for (final id in autoIds) {
        if (locked.contains(lockKey(g, id))) continue;
        final v = values[id];
        next = v == null
            ? next.clearGroupOverride(g, id)
            : next.withGroupValue(g, id, v);
      }
    }
    return next;
  }

  /// Highest value auto retouch may give [id] (its range top, else 100).
  static double capOf(String id) =>
      needRanges[id]?.$2 ??
      (eyePolish.containsKey(id) ? 40 : PortraitRegistry.byId(id).max);

  /// [p] with suggested All-group [deltas] (e.g. from the vision engine)
  /// added, capped like the measured values; [locked] keys untouched.
  static PortraitSettings withDeltas(
    PortraitSettings p,
    Map<String, double> deltas, {
    Set<String> locked = const {},
  }) {
    var next = p;
    for (final e in deltas.entries) {
      final spec = PortraitRegistry.tryById(e.key);
      if (spec == null || spec.scope != PortraitScope.face) continue;
      if (!autoIds.contains(e.key)) continue;
      if (locked.contains(lockKey(FaceGroup.all, e.key))) continue;
      final v = (p.groupValue(FaceGroup.all, e.key) + e.value)
          .clamp(spec.min, capOf(e.key))
          .toDouble();
      next = next.withGroupValue(FaceGroup.all, e.key, v);
    }
    return next;
  }

  /// "Re-measure per photo" for synced retouch: [pasted] values (copied
  /// from a photo whose auto retouch was [fromAuto]) moved by what this
  /// photo needs instead ([toAuto]). The source's own adjustments survive
  /// as offsets on top of this photo's auto values. Only [autoIds] move;
  /// [locked] keys stay as pasted.
  static PortraitSettings rebase(
    PortraitSettings pasted, {
    required PortraitSettings fromAuto,
    required PortraitSettings toAuto,
    Set<String> locked = const {},
  }) {
    var next = pasted;
    for (final g in FaceGroup.values) {
      final explicit =
          g == FaceGroup.all ||
          [pasted, fromAuto, toAuto].any((p) => p.groups[g] != null);
      if (!explicit) continue;
      for (final id in autoIds) {
        if (locked.contains(lockKey(g, id))) continue;
        if (g != FaceGroup.all &&
            !pasted.groupOverrides(g, id) &&
            !toAuto.groupOverrides(g, id)) {
          continue;
        }
        final spec = PortraitRegistry.byId(id);
        final v =
            (pasted.groupValue(g, id) +
                    toAuto.groupValue(g, id) -
                    fromAuto.groupValue(g, id))
                .clamp(spec.min, spec.max)
                .toDouble();
        next = next.withGroupValue(g, id, v.roundToDouble());
      }
    }
    return next;
  }
}
