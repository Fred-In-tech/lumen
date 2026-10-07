import 'package:lumen_core/lumen_core.dart';

/// User preferences persisted in `settings.json`.
class AppSettings {
  const AppSettings({
    this.gatewayUrl,
    this.gatewayToken,
    this.autoEditOnImport = true,
    this.retouchFacesAutomatically = true,
    this.remeasureRetouchOnSync = true,
    this.defaultStyle = 'natural',
    this.exportFormat = 'jpeg',
    this.exportQuality = 90,
    this.exportLongEdge,
    this.exportKeepMetadata = true,
    this.onboardingDone = false,
    this.canvasSurround = 'graphite',
    this.exportPresets = const [],
    this.exportPresetId,
    this.exportLast,
    this.displayName,
  });

  factory AppSettings.fromJson(Object? json) {
    if (json is! Map) return const AppSettings();
    return AppSettings(
      gatewayUrl: json['gatewayUrl'] as String?,
      gatewayToken: json['gatewayToken'] as String?,
      autoEditOnImport: json['autoEditOnImport'] != false,
      retouchFacesAutomatically: json['retouchFacesAutomatically'] != false,
      remeasureRetouchOnSync: json['remeasureRetouchOnSync'] != false,
      defaultStyle: json['defaultStyle'] as String? ?? 'natural',
      exportFormat: json['exportFormat'] == 'png' ? 'png' : 'jpeg',
      exportQuality: ((json['exportQuality'] as num?) ?? 90).toInt().clamp(
        1,
        100,
      ),
      exportLongEdge: (json['exportLongEdge'] as num?)?.toInt(),
      exportKeepMetadata: json['exportKeepMetadata'] != false,
      onboardingDone: json['onboardingDone'] == true,
      canvasSurround: json['canvasSurround'] as String? ?? 'graphite',
      exportPresets: _presets(json['exportPresets']),
      exportPresetId: json['exportPresetId'] as String?,
      exportLast: json['exportLast'] is Map
          ? ExportPreset.fromJson((json['exportLast'] as Map).cast())
          : null,
      displayName: cleanDisplayName(json['displayName']),
    );
  }

  static List<ExportPreset> _presets(Object? json) {
    if (json is! List) return const [];
    return List.unmodifiable([
      for (final p in json)
        if (p is Map && p['id'] is String && (p['id'] as String).isNotEmpty)
          ExportPreset.fromJson(p.cast()),
    ]);
  }

  /// Null means "use the platform default" (localhost / 10.0.2.2 on Android).
  final String? gatewayUrl;
  final String? gatewayToken;
  final bool autoEditOnImport;

  /// AI auto-edit (single, batch, on import) also retouches faces with
  /// need-scaled Auto Retouch.
  final bool retouchFacesAutomatically;

  /// Syncing portrait retouch re-measures each photo's needs instead of
  /// copying fixed numbers.
  final bool remeasureRetouchOnSync;
  final String defaultStyle;
  final String exportFormat;
  final int exportQuality;

  /// Null means original size.
  final int? exportLongEdge;
  final bool exportKeepMetadata;
  final bool onboardingDone;
  final String canvasSurround;

  /// The user's own export presets (built-ins: `kBuiltinExportPresets`).
  final List<ExportPreset> exportPresets;

  /// The preset picked last (null: custom settings, [exportLast]).
  final String? exportPresetId;

  /// The export settings used last (what "Custom" starts from).
  final ExportPreset? exportLast;

  /// How Home greets the user ("Welcome back, Sam"); null: no name.
  final String? displayName;

  /// A trimmed name of at most 40 characters, or null when blank.
  static String? cleanDisplayName(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    if (s.isEmpty) return null;
    return s.length > 40 ? s.substring(0, 40) : s;
  }

  AppSettings copyWith({
    String? gatewayUrl,
    String? gatewayToken,
    bool? autoEditOnImport,
    bool? retouchFacesAutomatically,
    bool? remeasureRetouchOnSync,
    String? defaultStyle,
    String? exportFormat,
    int? exportQuality,
    int? exportLongEdge,
    bool clearExportLongEdge = false,
    bool? exportKeepMetadata,
    bool? onboardingDone,
    String? canvasSurround,
    List<ExportPreset>? exportPresets,
    String? exportPresetId,
    bool clearExportPresetId = false,
    ExportPreset? exportLast,
    String? displayName,
    bool clearDisplayName = false,
  }) => AppSettings(
    gatewayUrl: gatewayUrl ?? this.gatewayUrl,
    gatewayToken: gatewayToken ?? this.gatewayToken,
    autoEditOnImport: autoEditOnImport ?? this.autoEditOnImport,
    retouchFacesAutomatically:
        retouchFacesAutomatically ?? this.retouchFacesAutomatically,
    remeasureRetouchOnSync:
        remeasureRetouchOnSync ?? this.remeasureRetouchOnSync,
    defaultStyle: defaultStyle ?? this.defaultStyle,
    exportFormat: exportFormat ?? this.exportFormat,
    exportQuality: exportQuality ?? this.exportQuality,
    exportLongEdge: clearExportLongEdge
        ? null
        : (exportLongEdge ?? this.exportLongEdge),
    exportKeepMetadata: exportKeepMetadata ?? this.exportKeepMetadata,
    onboardingDone: onboardingDone ?? this.onboardingDone,
    canvasSurround: canvasSurround ?? this.canvasSurround,
    exportPresets: exportPresets ?? this.exportPresets,
    exportPresetId: clearExportPresetId
        ? null
        : (exportPresetId ?? this.exportPresetId),
    exportLast: exportLast ?? this.exportLast,
    displayName: clearDisplayName
        ? null
        : cleanDisplayName(displayName) ?? this.displayName,
  );

  Map<String, Object?> toJson() => {
    'gatewayUrl': gatewayUrl,
    'gatewayToken': gatewayToken,
    'autoEditOnImport': autoEditOnImport,
    'retouchFacesAutomatically': retouchFacesAutomatically,
    'remeasureRetouchOnSync': remeasureRetouchOnSync,
    'defaultStyle': defaultStyle,
    'exportFormat': exportFormat,
    'exportQuality': exportQuality,
    'exportLongEdge': exportLongEdge,
    'exportKeepMetadata': exportKeepMetadata,
    'onboardingDone': onboardingDone,
    'canvasSurround': canvasSurround,
    'exportPresets': [for (final p in exportPresets) p.toJson()],
    'exportPresetId': exportPresetId,
    'exportLast': exportLast?.toJson(),
    'displayName': displayName,
  };
}
