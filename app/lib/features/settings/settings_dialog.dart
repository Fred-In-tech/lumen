import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/app_settings.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/buttons.dart';

/// Gateway URL/token, auto-edit on import and default style.
Future<void> showSettingsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SettingsDialog());

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog();

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _name;
  bool _auto = true;
  bool _retouch = true;
  bool _remeasure = true;
  String _style = 'natural';

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider).value;
    _url = TextEditingController(
      text: s?.gatewayUrl ?? ref.read(platformInfoProvider).defaultGatewayUrl,
    );
    _token = TextEditingController(text: s?.gatewayToken ?? '');
    _name = TextEditingController(text: s?.displayName ?? '');
    _auto = s?.autoEditOnImport ?? true;
    _retouch = s?.retouchFacesAutomatically ?? true;
    _remeasure = s?.remeasureRetouchOnSync ?? true;
    _style = s?.defaultStyle ?? 'natural';
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(settingsProvider.notifier)
        .change(
          (s) => s.copyWith(
            gatewayUrl: _url.text.trim(),
            gatewayToken: _token.text.trim(),
            autoEditOnImport: _auto,
            retouchFacesAutomatically: _retouch,
            remeasureRetouchOnSync: _remeasure,
            defaultStyle: _style,
            displayName: _name.text,
            clearDisplayName: AppSettings.cleanDisplayName(_name.text) == null,
          ),
        );
    ref.invalidate(gatewayStatusProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = ref.watch(gatewayStatusProvider);
    InputDecoration deco(String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      filled: true,
      fillColor: t.surface1,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rad.sm),
        borderSide: BorderSide(color: t.lineStrong),
      ),
    );
    final statusText = status.when(
      data: (s) => !s.reachable
          ? 'Gateway not reachable. Edits run on this device.'
          : s.visionAvailable
          ? 'Connected. AI vision on (${s.model}).'
          : 'Connected, but the gateway has no AI key. Edits run on this device.',
      loading: () => 'Checking…',
      error: (e, _) => 'Error: $e',
    );
    return Dialog(
      backgroundColor: t.surface2,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Sp.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Settings',
                style: LumenType.title().copyWith(color: t.textPrimary),
              ),
              const SizedBox(height: Sp.s5),
              Text(
                'Your name (optional)',
                style: LumenType.label().copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: Sp.s1),
              TextField(
                key: const ValueKey('settings-display-name'),
                controller: _name,
                style: LumenType.body().copyWith(color: t.textPrimary),
                decoration: deco('Home says “Welcome back, …”'),
              ),
              const SizedBox(height: Sp.s3),
              Text(
                'AI gateway URL',
                style: LumenType.label().copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: Sp.s1),
              TextField(
                controller: _url,
                style: LumenType.body().copyWith(color: t.textPrimary),
                decoration: deco('http://localhost:8080'),
              ),
              const SizedBox(height: Sp.s3),
              Text(
                'Gateway token (optional)',
                style: LumenType.label().copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: Sp.s1),
              TextField(
                controller: _token,
                obscureText: true,
                style: LumenType.body().copyWith(color: t.textPrimary),
                decoration: deco('Only if the gateway requires one'),
              ),
              const SizedBox(height: Sp.s2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      statusText,
                      style: LumenType.caption().copyWith(
                        color: t.textTertiary,
                      ),
                    ),
                  ),
                  LumenButton(
                    label: 'Test',
                    kind: ButtonKind.ghost,
                    onPressed: () => ref.invalidate(gatewayStatusProvider),
                  ),
                ],
              ),
              const SizedBox(height: Sp.s4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _auto,
                activeThumbColor: t.accent,
                title: Text(
                  'Auto-edit photos when I import them',
                  style: LumenType.body().copyWith(color: t.textPrimary),
                ),
                onChanged: (v) => setState(() => _auto = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _retouch,
                activeThumbColor: t.accent,
                title: Text(
                  'Retouch faces automatically',
                  style: LumenType.body().copyWith(color: t.textPrimary),
                ),
                subtitle: Text(
                  'Auto-edit also cleans skin, eyes and teeth, scaled to '
                  'what each face needs.',
                  style: LumenType.caption().copyWith(color: t.textTertiary),
                ),
                onChanged: (v) => setState(() => _retouch = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _remeasure,
                activeThumbColor: t.accent,
                title: Text(
                  'Re-measure retouch per photo when syncing',
                  style: LumenType.body().copyWith(color: t.textPrimary),
                ),
                onChanged: (v) => setState(() => _remeasure = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Default AI style',
                      style: LumenType.body().copyWith(color: t.textPrimary),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _style,
                    dropdownColor: t.surface3,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final s in AiStyle.values)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            s.label,
                            style: LumenType.body().copyWith(
                              color: t.textPrimary,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _style = v ?? 'natural'),
                  ),
                ],
              ),
              const SizedBox(height: Sp.s5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  LumenButton(
                    label: 'Cancel',
                    kind: ButtonKind.ghost,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: Sp.s2),
                  LumenButton(
                    label: 'Save',
                    kind: ButtonKind.primary,
                    onPressed: _save,
                  ),
                ],
              ),
              const SizedBox(height: Sp.s3),
              Text(
                '${kBrand.name} keeps your photos on this device. Only a small preview is sent to the AI gateway, without location data.',
                style: LumenType.caption().copyWith(color: t.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
