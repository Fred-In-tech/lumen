/// The version testers see (Settings, Home "Check for updates"). Matches
/// `version:` in pubspec.yaml; `test/app_info_test.dart` keeps them equal.
const kAppVersion = '1.3.0';

/// Where the tester guide lives (Quick start).
const kInstallGuideUrl =
    'https://github.com/Fred-In-tech/lumen/blob/main/INSTALL.md';

/// The one-line installer that also updates on demand.
const kInstallCommand =
    'curl -fsSL https://raw.githubusercontent.com/Fred-In-tech/lumen/main/install.sh | bash';
