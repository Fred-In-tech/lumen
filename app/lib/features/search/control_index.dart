import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/masks/mask_kinds.dart';
import 'package:lumen/features/portrait/portrait_panel.dart';
import 'package:lumen/features/remove/remove_ui_state.dart';

/// What a search result opens.
enum ControlKind { developParam, portraitParam, mask, removeTool, action }

/// One searchable control: a slider, a mask kind, a Remove tool or an action.
class ControlEntry {
  const ControlEntry({
    required this.id,
    required this.title,
    required this.module,
    required this.section,
    required this.kind,
    this.keywords = const [],
  });

  /// Param id, `MaskKind.name`, `RemoveTool.name` or an action id.
  final String id;
  final String title;
  final EditorModule module;

  /// Section title in the panel ("Light", "Skin", …) or the module label.
  final String section;
  final ControlKind kind;
  final List<String> keywords;

  String get path => '${module.label} · $section';
}

/// Panel section of a develop param group.
String developSection(ParamGroup g) => switch (g) {
  ParamGroup.light => 'Light',
  ParamGroup.color || ParamGroup.hsl || ParamGroup.bw => 'Color',
  ParamGroup.curve => 'Curve',
  ParamGroup.grading => 'Color grading',
  ParamGroup.presence || ParamGroup.effects => 'Effects',
  ParamGroup.detail => 'Detail',
};

/// Everyday words photographers type for a control.
const Map<String, List<String>> kControlSynonyms = {
  P.exposure: ['brightness', 'brighter', 'darker', 'lighten', 'darken'],
  P.temp: ['white balance', 'warm', 'warmer', 'cool', 'cooler', 'yellow'],
  P.tint: ['white balance', 'green', 'magenta'],
  P.highlights: ['bright areas', 'sky', 'blown'],
  P.shadows: ['dark areas', 'lift', 'fill light'],
  P.clarity: ['punch', 'midtone contrast'],
  P.dehaze: ['haze', 'fog', 'mist'],
  P.vibrance: ['colour', 'color', 'pop'],
  P.saturation: ['colour', 'color', 'intensity'],
  P.sharpenAmount: ['sharp', 'sharpness', 'crisp', 'blur'],
  P.noiseLuminance: ['noise', 'grain', 'iso'],
  P.vignetteAmount: ['vignette', 'dark corners'],
  P.grainAmount: ['film', 'grain'],
  PortraitIds.skinSoftening: ['smooth', 'smoothing', 'soften', 'airbrush'],
  PortraitIds.skinEven: ['redness', 'blotchy', 'uneven', 'tone'],
  PortraitIds.skinTexture: ['pores', 'detail'],
  PortraitIds.skinShine: ['oily', 'shiny', 'sweat', 'hotspot'],
  PortraitIds.acne: ['pimple', 'pimples', 'spot', 'zit', 'blemish'],
  PortraitIds.freckle: ['freckles', 'spots'],
  PortraitIds.mole: ['moles', 'beauty mark'],
  PortraitIds.wrinkleForehead: ['wrinkles', 'lines', 'age'],
  PortraitIds.wrinkleFrown: ['wrinkles', 'eleven lines', 'glabella'],
  PortraitIds.wrinkleCrowsFeet: ['wrinkles', 'eye wrinkles', 'crow'],
  PortraitIds.wrinkleSmile: ['wrinkles', 'nasolabial', 'laugh lines'],
  PortraitIds.wrinkleMarionette: ['wrinkles', 'mouth lines'],
  PortraitIds.darkCircles: ['tired', 'under eye', 'raccoon'],
  PortraitIds.eyeBags: ['puffy', 'under eye', 'bags'],
  PortraitIds.eyeWhites: ['sclera', 'bright eyes'],
  PortraitIds.iris: ['eye colour', 'eye color', 'sparkle'],
  PortraitIds.redVein: ['bloodshot', 'red eyes'],
  PortraitIds.redEye: ['red eye', 'flash'],
  PortraitIds.teethBrightness: ['whiten', 'smile', 'teeth'],
  PortraitIds.teethDesaturate: ['whiten', 'yellow teeth', 'stains'],
  PortraitIds.lips: ['lipstick', 'mouth'],
  PortraitIds.blush: ['cheeks', 'rosy'],
  PortraitIds.faceWidth: ['slim', 'thin face', 'reshape', 'face shape'],
  PortraitIds.vShape: ['jawline', 'v line', 'slim', 'contour'],
  PortraitIds.chin: ['jaw', 'chin length'],
  PortraitIds.eyeSize: ['bigger eyes', 'enlarge eyes'],
  PortraitIds.noseWidth: ['nose', 'slim nose'],
  PortraitIds.mouthSize: ['mouth', 'lips size'],
  PortraitIds.bgClean: ['backdrop', 'background', 'dust', 'seamless'],
  PortraitIds.bgUnify: ['backdrop', 'background', 'falloff', 'even light'],
  PortraitIds.bgUnifyLuminance: ['backdrop', 'brighter background'],
  PortraitIds.strayHairs: ['flyaway', 'flyaways', 'frizz', 'hair'],
};

/// Every control the editor can reveal, in panel order.
List<ControlEntry> buildControlIndex() {
  final portraitIds = {for (final s in kPortraitSections) ...s.ids};
  return [
    const ControlEntry(
      id: 'auto',
      title: 'Auto edit',
      module: EditorModule.adjust,
      section: 'AI',
      kind: ControlKind.action,
      keywords: ['ai', 'automatic', 'one click', 'fix'],
    ),
    const ControlEntry(
      id: 'autoRetouch',
      title: 'Auto Retouch',
      module: EditorModule.portrait,
      section: 'Portrait',
      kind: ControlKind.action,
      keywords: ['ai', 'retouch', 'beauty', 'face', 'skin'],
    ),
    const ControlEntry(
      id: 'editSpots',
      title: 'Edit spots',
      module: EditorModule.portrait,
      section: 'Blemishes',
      kind: ControlKind.action,
      keywords: ['keep', 'remove', 'spot', 'mole', 'freckle'],
    ),
    for (final spec in ParamRegistry.all)
      ControlEntry(
        id: spec.id,
        title: spec.label,
        module: EditorModule.adjust,
        section: developSection(spec.group),
        kind: ControlKind.developParam,
        keywords: kControlSynonyms[spec.id] ?? const [],
      ),
    for (final section in kPortraitSections)
      for (final id in section.ids)
        if (portraitIds.contains(id))
          ControlEntry(
            id: id,
            title: PortraitRegistry.byId(id).label,
            module: EditorModule.portrait,
            section: section.title,
            kind: ControlKind.portraitParam,
            keywords: kControlSynonyms[id] ?? const [],
          ),
    for (final k in [...kManualMaskKinds, ...kAiMaskKinds])
      ControlEntry(
        id: k.name,
        title: '${k.menuLabel} mask',
        module: EditorModule.masks,
        section: 'Masks',
        kind: ControlKind.mask,
        keywords: const ['mask', 'local', 'select', 'selection'],
      ),
    for (final t in RemoveTool.values)
      ControlEntry(
        id: t.name,
        title: t.label,
        module: EditorModule.remove,
        section: 'Remove',
        kind: ControlKind.removeTool,
        keywords: switch (t) {
          RemoveTool.remove => const ['erase', 'object', 'distraction', 'wire'],
          RemoveTool.heal => const ['spot', 'dust', 'blemish', 'fix'],
          RemoveTool.clone => const ['stamp', 'copy', 'duplicate'],
        },
      ),
  ];
}

/// Ranks [index] for [query]: whole-title prefix, word prefix, synonym, then
/// substring matches. Every query word must match somewhere.
List<ControlEntry> searchControls(
  List<ControlEntry> index,
  String query, {
  int limit = 12,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  final scored = <(ControlEntry, double)>[];
  for (var i = 0; i < index.length; i++) {
    final e = index[i];
    final title = e.title.toLowerCase();
    final titleWords = title.split(RegExp(r'[^a-z0-9]+'));
    final keys = e.keywords.map((k) => k.toLowerCase()).toList();
    final section = e.section.toLowerCase();
    var score = 0.0;
    var all = true;
    for (final w in words) {
      double best = 0;
      if (title.startsWith(w)) best = 4;
      if (best < 3 && titleWords.any((t) => t.startsWith(w))) best = 3;
      if (best < 2.5 && keys.any((k) => k == w || k.startsWith(w))) best = 2.5;
      if (best < 2 && keys.any((k) => k.contains(w))) best = 2;
      if (best < 1.5 && title.contains(w)) best = 1.5;
      if (best < 1 && section.startsWith(w)) best = 1;
      if (best == 0) {
        all = false;
        break;
      }
      score += best;
    }
    // Earlier panel order breaks ties.
    if (all) scored.add((e, score - i * 1e-4));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored.take(limit)) s.$1];
}
