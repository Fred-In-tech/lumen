import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/desktop_editor.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/phone_editor.dart';
import 'package:lumen/features/editor/renderer/renderer_factory.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/sync/settings_clipboard.dart';

/// Editor route. Owns the [EditorSession] for the current photo and swaps it
/// when the user moves through the filmstrip.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.assetIds, required this.initialAssetId});

  final List<String> assetIds;
  final String initialAssetId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> with WidgetsBindingObserver {
  late String _assetId = widget.initialAssetId;
  EditorSession? _session;
  Object? _openError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
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
      session.render(_renderSettings(s));
    } on Exception catch (e) {
      if (mounted) setState(() => _openError = e);
    }
  }

  DevelopSettings _renderSettings(EditorState s) {
    if (s.showingBefore) return DevelopSettings.defaults.copyWith(geometry: s.settings.geometry);
    if (s.cropMode) return s.settings.copyWith(geometry: s.settings.geometry.copyWith(crop: CropRect.full));
    return s.settings;
  }

  Future<void> _goTo(String id) async {
    if (id == _assetId) return;
    await ref.read(editorProvider(_assetId).notifier).flush();
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
    _session?.dispose();
    super.dispose();
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(bool apple) {
    final ctl = ref.read(editorProvider(_assetId).notifier);
    SingleActivator cmd(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, meta: apple, control: !apple, shift: shift);
    final session = _session;
    return {
      cmd(LogicalKeyboardKey.keyZ): ctl.undo,
      cmd(LogicalKeyboardKey.keyZ, shift: true): ctl.redo,
      cmd(LogicalKeyboardKey.keyY): ctl.redo,
      cmd(LogicalKeyboardKey.keyC, shift: true): () => copySettings(context, ref, _assetId),
      cmd(LogicalKeyboardKey.keyV, shift: true): () => pasteSettingsInto(context, ref, _assetId),
      cmd(LogicalKeyboardKey.keyE): () => showExportDialog(context, ref, [_assetId]),
      const SingleActivator(LogicalKeyboardKey.keyY): () {
        final s = ref.read(editorProvider(_assetId)).value;
        ctl.setCompare(s?.compare == CompareMode.split ? CompareMode.off : CompareMode.split);
      },
      const SingleActivator(LogicalKeyboardKey.keyR): () => ctl.setCropMode(true),
      const SingleActivator(LogicalKeyboardKey.keyA): () {
        if (session != null) runAutoEdit(ref, session);
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => _step(1),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => _step(-1),
      const SingleActivator(LogicalKeyboardKey.escape): () {
        final s = ref.read(editorProvider(_assetId)).value;
        if (s?.cropMode ?? false) {
          ctl.setCropMode(false);
        } else {
          _close();
        }
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final session = _session;
    final platform = ref.watch(platformInfoProvider);
    ref.listen<AsyncValue<EditorState>>(editorProvider(_assetId), (prev, next) {
      final p = prev?.value, n = next.value;
      if (n == null || session == null) return;
      final renderChanged = p == null ||
          p.settings != n.settings ||
          p.showingBefore != n.showingBefore ||
          p.cropMode != n.cropMode;
      if (renderChanged) {
        final committed = p == null || p.history != n.history;
        session.render(_renderSettings(n), interactive: !committed);
        if (committed) session.scheduleThumbnail(n.settings);
      }
    });
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < Layout.phoneBreakpoint;
    Widget body;
    if (_openError != null) {
      body = Center(
        child: Text('Can’t open this photo.\n$_openError', textAlign: TextAlign.center, style: LumenType.body().copyWith(color: t.textSecondary)),
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
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e.logicalKey == LogicalKeyboardKey.backslash) {
            final down = e is KeyDownEvent || e is KeyRepeatEvent;
            ref.read(editorProvider(_assetId).notifier).setShowingBefore(down);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(backgroundColor: t.surface0, body: body),
      ),
    );
  }
}
