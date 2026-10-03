/// Web twin of `platform_info_io.dart`.
class PlatformInfo {
  const PlatformInfo({
    required this.isMacOS,
    required this.isWindows,
    required this.isLinux,
    required this.isIOS,
    required this.isAndroid,
    this.isWeb = false,
  });

  factory PlatformInfo.current() => const PlatformInfo(
    isMacOS: false,
    isWindows: false,
    isLinux: false,
    isIOS: false,
    isAndroid: false,
    isWeb: true,
  );

  final bool isMacOS;
  final bool isWindows;
  final bool isLinux;
  final bool isIOS;
  final bool isAndroid;
  final bool isWeb;

  bool get isDesktop => isMacOS || isWindows || isLinux;
  bool get isMobile => isIOS || isAndroid;
  bool get isApple => isMacOS || isIOS;
  bool get supportsDragAndDrop => isDesktop || isWeb;
  String get name => isMacOS
      ? 'macos'
      : isWindows
      ? 'windows'
      : isLinux
      ? 'linux'
      : isIOS
      ? 'ios'
      : isAndroid
      ? 'android'
      : 'web';

  /// Default gateway URL: the Android emulator reaches the host via 10.0.2.2.
  String get defaultGatewayUrl =>
      isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080';
}
