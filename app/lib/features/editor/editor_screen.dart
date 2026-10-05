import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/ai_auto_run.dart';
import 'package:lumen/features/editor/compare_suppress.dart';
import 'package:lumen/features/editor/desktop_editor.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/phone_editor.dart';
import 'package:lumen/features/search/control_search_dialog.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/editor/renderer/renderer_factory.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/info/photo_info_dialog.dart';
import 'package:lumen/features/masks/ai_mask_rasters.dart';
import 'package:lumen/features/masks/mask_shortcuts.dart';
import 'package:lumen/features/portrait/backdrop_inputs.dart';
import 'package:lumen/features/portrait/retouch_inputs.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/features/remove/remove_service.dart';
import 'package:lumen/features/remove/remove_shortcuts.dart';
import 'package:lumen/features/sync/settings_clipboard.dart';

final _log = Logger('EditorScreen');

/// Editor route. Owns the [EditorSession] for the current photo and swaps it
/// when the user moves through the filmstrip.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    super.key,
    required this.assetIds,
    required this.initialAssetId,
  });

  final List<String> assetIds;
  final String initialAssetId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with WidgetsBindingObserver {
  late String _assetId = widget.initialAssetId;
  EditorSession? _session;
  Object? _openError;
  ProviderContainer? _container;

  /// Photos opened here that may own heal patches (their documents had
  /// patch refs, or the store was opened): cleaned up when they close.
  final Set<String> _healed = {};

  /// Holds keyboard focus for the editor shortcuts (\, A, M, Q, /, …).
  final FocusNode _keys = FocusNode(debugLabel: 'editor keys');

  /// When a text field (prompt bar, rename, slider value) lets go of focus,
  /// nothing would hold it and the shortcuts would go dead: take it back.
  void _reclaimKeys() {
    final focus = FocusManager.instance.primaryFocus;
    if (!mounted || _keys.hasFocus) return;
    final idle = focus == null || focus is FocusScopeNode;
    if (!idle) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return; // a dialog is on top
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_keys.hasFocus) _keys.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_reclaimKeys);
    _openSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(editorProvider(_assetId).notifier).flush();
    }
  }

  Future<void> _openSession() async {
    final old = _session;
    final session = EditorSession(
      assetId: _assetId,
      renderer: ref.read(photoRendererFactoryProvider)(_assetId),
      repo: ref.read(catalogRepositoryProvider),
    );
    setState(() {
      _session = session;
      _openError = null;
    });
    old?.dispose();
    try {
      await session.open();
      final s = await ref.read(editorProvider(_assetId).future);
      if (referencedPatchRefs(s.doc).isNotEmpty) _healed.add(_assetId);
      _pushHealer(session, ref.read(healedSourceProvider(_assetId)));
      _pushMaskRasters(
        session,
        ref.read(aiMaskRastersProvider(_assetId)).value,
      );
      _pushRetouch(session, ref.read(retouchInputsProvider(_assetId)).value);
      session.render(_renderSettings(s));
    } on Exception catch (e) {
      if (mounted) setState(() => _openError = e);
    }
  }

  /// Hands the photo's heal compositor to the renderer.
  static void _pushHealer(EditorSession? session, HealedSourceCache healer) {
    if (session?.renderer case final HealSink sink) sink.setHealer(healer);
  }

  /// Deletes unreferenced heal patches of [assetId] and frees its healed
  /// previews. Only for photos that may have patches, so the patch store is
  /// never opened for the others.
  void _closeHeals(String assetId) {
    final c = _container;
    if (c == null) return;
    if (_healed.remove(assetId) || c.exists(patchStoreProvider)) {
      unawaited(
        c
            .read(removeServiceProvider)
            .collectGarbage(assetId)
            .then<void>(
              (_) {},
              onError: (Object e) => _log.fine('patch cleanup skipped: $e'),
            ),
      );
    }
    c.invalidate(healedSourceProvider(assetId));
  }

  /// Hands AI mask rasters to the renderer (it re-renders with them).
  static void _pushMaskRasters(
    EditorSession? session,
    Map<String, MaskRaster>? rasters,
  ) {
    if (session?.renderer case final MaskRasterSink sink) {
      sink.setMaskRasters(rasters ?? const {});
    }
  }

  /// Hands portrait retouch maps + faces to the renderer (null clears).
  static void _pushRetouch(EditorSession? session, RetouchInputs? inputs) {
    if (session?.renderer case final RetouchSink sink) {
      sink.setRetouch(inputs?.maps, inputs?.faces);
    }
  }

  DevelopSettings _renderSettings(EditorState s) {
    if (s.showingBefore) {
      return DevelopSettings.defaults.copyWith(geometry: s.settings.geometry);
    }
    if (s.cropMode) {
      return s.settings.copyWith(
        geometry: s.settings.geometry.copyWith(crop: CropRect.full),
      );
    }
    return withSuppressed(
      s.settings,
      ref.read(compareSuppressProvider(_assetId)),
    );
  }

  Future<void> _goTo(String id) async {
    if (id == _assetId) return;
    await ref.read(editorProvider(_assetId).notifier).flush();
    _closeHeals(_assetId);
    setState(() => _assetId = id);
    await _openSession();
  }

  void _step(int delta) {
    final i = widget.assetIds.indexOf(_assetId);
    final j = i + delta;
    if (j >= 0 && j < widget.assetIds.length) _goTo(widget.assetIds[j]);
  }

  Future<void> _close() async {
    await ref.read(editorProvider(_assetId).notifier).flush();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_reclaimKeys);
    _keys.dispose();
    _session?.dispose();
    _closeHeals(_assetId);
    super.dispose();
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(bool apple) {
    final ctl = ref.read(editorProvider(_assetId).notifier);
    SingleActivator cmd(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, meta: apple, control: !apple, shift: shift);
    return {
      cmd(LogicalKeyboardKey.keyZ): ctl.undo,
      cmd(LogicalKeyboardKey.keyZ, shift: true): ctl.redo,
      cmd(LogicalKeyboardKey.keyY): ctl.redo,
      cmd(LogicalKeyboardKey.keyC, shift: true): () =>
          copySettings(context, ref, _assetId),
      cmd(LogicalKeyboardKey.keyV, shift: true): () =>
          pasteSettingsInto(context, ref, _assetId),
      cmd(LogicalKeyboardKey.keyE): () =>
          showExportDialog(context, ref, [_assetId]),
    };
  }

  /// True while a text field has focus: single-key shortcuts must not fire.
  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  /// Unmodified single-key shortcuts (DESIGN.md §6.3). Ignored while typing.
  KeyEventResult _onKey(KeyEvent e) {
    if (_typing()) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed) {
      return KeyEventResult.ignored;
    }
    final ctl = ref.read(editorProvider(_assetId).notifier);
    final s = ref.read(editorProvider(_assetId)).value;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.backslash) {
      ctl.setShowingBefore(e is KeyDownEvent || e is KeyRepeatEvent);
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.keyY) {
      ctl.setCompare(
        s?.compare == CompareMode.split ? CompareMode.off : CompareMode.split,
      );
    } else if (k == LogicalKeyboardKey.keyR) {
      ctl.setCropMode(true);
    } else if (k == LogicalKeyboardKey.slash) {
      showControlSearch(context, ref, _assetId, session: _session);
    } else if (k == LogicalKeyboardKey.keyI) {
      final entry = _session?.entry;
      if (entry != null) showPhotoInfo(context, entry);
    } else if (k == LogicalKeyboardKey.keyA) {
      final session = _session;
      if (session != null) runAiAuto(ref, session);
    } else if (k == LogicalKeyboardKey.arrowRight && keys.isAltPressed) {
      _step(1);
    } else if (k == LogicalKeyboardKey.arrowLeft && keys.isAltPressed) {
      _step(-1);
    } else if (k == LogicalKeyboardKey.escape) {
      if (s?.cropMode ?? false) {
        ctl.setCropMode(false);
      } else {
        _close();
      }
    } else {
      // Module keys: Q (Remove), [ ] (brush size); M (Masks), O (overlay),
      // Delete (selected mask).
      final remove = handleRemoveShortcut(ref.read, _assetId, k);
      if (remove == KeyEventResult.handled) return remove;
      return handleMaskShortcut(ref.read, _assetId, k, context: context);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final session = _session;
    final platform = ref.watch(platformInfoProvider);
    ref.listen<AsyncValue<EditorState>>(editorProvider(_assetId), (prev, next) {
      final p = prev?.value, n = next.value;
      if (n == null || session == null) return;
      final renderChanged =
          p == null ||
          p.settings != n.settings ||
          p.showingBefore != n.showingBefore ||
          p.cropMode != n.cropMode;
      if (renderChanged) {
        final committed = p == null || p.history != n.history;
        session.render(_renderSettings(n), interactive: !committed);
        if (committed) session.scheduleThumbnail(n.settings);
      }
    });
    // Hold-to-compare: re-render without the held section's params.
    ref.listen<Set<String>>(compareSuppressProvider(_assetId), (_, _) {
      final st = ref.read(editorProvider(_assetId)).value;
      if (st != null && session != null) session.render(_renderSettings(st));
    });
    // AI masks read decoded rasters; push them whenever their refs change.
    ref.listen<AsyncValue<Map<String, MaskRaster>>>(
      aiMaskRastersProvider(_assetId),
      (_, next) => _pushMaskRasters(session, next.value),
    );
    // Background swap: rasters + image while a swap is on.
    ref.listen<AsyncValue<BackdropInputs>>(backdropInputsProvider(_assetId), (
      _,
      next,
    ) {
      final v = next.value;
      if (v == null) return;
      if (session?.renderer case final BackdropSink sink) {
        sink.setBackdropInputs(people: v.people, hair: v.hair, image: v.image);
      }
    });
    // Face shape sliders warp as soon as faces are known.
    ref.listen<FaceAnalysis?>(warpFacesProvider(_assetId), (_, faces) {
      if (session?.renderer case final WarpSink sink) sink.setWarpFaces(faces);
    });
    // Portrait retouch maps are built once per face analysis.
    ref.listen<AsyncValue<RetouchInputs?>>(
      retouchInputsProvider(_assetId),
      (_, next) => _pushRetouch(session, next.value),
    );
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < Layout.phoneBreakpoint;
    Widget body;
    if (_openError != null) {
      body = Center(
        child: Text(
          'Can’t open this photo.\n$_openError',
          textAlign: TextAlign.center,
          style: LumenType.body().copyWith(color: t.textSecondary),
        ),
      );
    } else if (session == null) {
      body = const SizedBox.shrink();
    } else if (phone) {
      body = PhoneEditor(session: session, onClose: _close, onStep: _step);
    } else {
      body = DesktopEditor(
        session: session,
        assetIds: widget.assetIds,
        onClose: _close,
        onOpen: _goTo,
      );
    }
    return CallbackShortcuts(
      bindings: _shortcuts(platform.isApple),
      child: Focus(
        focusNode: _keys,
        autofocus: true,
        onKeyEvent: (node, e) => _onKey(e),
        child: Scaffold(backgroundColor: t.surface0, body: body),
      ),
    );
  }
}
