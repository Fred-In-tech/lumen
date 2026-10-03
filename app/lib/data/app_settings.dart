/// User preferences persisted in `settings.json`.
class AppSettings {
  const AppSettings({
    this.gatewayUrl,
    this.gatewayToken,
    this.autoEditOnImport = true,
    this.defaultStyle = 'natural',
    this.exportFormat = 'jpeg',
    this.exportQuality = 90,
    this.exportLongEdge,
    this.exportKeepMetadata = true,
    this.onboardingDone = false,
    this.canvasSurround = 'graphite',
  });

  factory AppSettings.fromJson(Object? json) {
    if (json is! Map) return const AppSettings();
    return AppSettings(
      gatewayUrl: json['gatewayUrl'] as String?,
      gatewayToken: json['gatewayToken'] as String?,
      autoEditOnImport: json['autoEditOnImport'] != false,
      defaultStyle: json['defaultStyle'] as String? ?? 'natural',
      exportFormat: json['exportFormat'] == 'png' ? 'png' : 'jpeg',
      exportQuality: ((json['exportQuality'] as num?) ?? 90).toInt().clamp(1, 100),
      exportLongEdge: (json['exportLongEdge'] as num?)?.toInt(),
      exportKeepMetadata: json['exportKeepMetadata'] != false,
      onboardingDone: json['onboardingDone'] == true,
      canvasSurround: json['canvasSurround'] as String? ?? 'graphite',
    );
  }

  /// Null means "use the platform default" (localhost / 10.0.2.2 on Android).
  final String? gatewayUrl;
  final String? gatewayToken;
  final bool autoEditOnImport;
  final String defaultStyle;
  final String exportFormat;
  final int exportQuality;

  /// Null means original size.
  final int? exportLongEdge;
  final bool exportKeepMetadata;
  final bool onboardingDone;
  final String canvasSurround;

  AppSettings copyWith({
    String? gatewayUrl,
    String? gatewayToken,
    bool? autoEditOnImport,
    String? defaultStyle,
    String? exportFormat,
    int? exportQuality,
    int? exportLongEdge,
    bool clearExportLongEdge = false,
    bool? exportKeepMetadata,
    bool? onboardingDone,
    String? canvasSurround,
  }) =>
      AppSettings(
        gatewayUrl: gatewayUrl ?? this.gatewayUrl,
        gatewayToken: gatewayToken ?? this.gatewayToken,
        autoEditOnImport: autoEditOnImport ?? this.autoEditOnImport,
        defaultStyle: defaultStyle ?? this.defaultStyle,
        exportFormat: exportFormat ?? this.exportFormat,
        exportQuality: exportQuality ?? this.exportQuality,
        exportLongEdge: clearExportLongEdge ? null : (exportLongEdge ?? this.exportLongEdge),
        exportKeepMetadata: exportKeepMetadata ?? this.exportKeepMetadata,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        canvasSurround: canvasSurround ?? this.canvasSurround,
      );

  Map<String, Object?> toJson() => {
        'gatewayUrl': gatewayUrl,
        'gatewayToken': gatewayToken,
        'autoEditOnImport': autoEditOnImport,
        'defaultStyle': defaultStyle,
        'exportFormat': exportFormat,
        'exportQuality': exportQuality,
        'exportLongEdge': exportLongEdge,
        'exportKeepMetadata': exportKeepMetadata,
        'onboardingDone': onboardingDone,
        'canvasSurround': canvasSurround,
      };
}
