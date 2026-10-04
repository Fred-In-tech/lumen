# Licenses

Everything shipped in the app, the core package and the gateway must be commercial-safe
(MIT / BSD / Apache-2.0 / ISC / zlib; MPL-2.0 only when used unmodified). GPL, AGPL, LGPL
and non-commercial licenses are banned from the binaries.

**Automated check:** `dart run tool/check_licenses.dart` (exit 1 on any banned or unknown
license). Regenerate the table below with `dart run tool/check_licenses.dart --markdown`.

## Notes
- `flutter_litert` (Apache-2.0) bundles prebuilt TensorFlow Lite / LiteRT native libraries
  (Apache-2.0) for every platform. On-device model weights are tracked separately in
  `docs/MODEL_LICENSES.md`.
- `dbus` (MPL-2.0) is pulled in only for Linux builds by `desktop_drop` / `file_picker_linux`
  and is used unmodified, which MPL permits in a proprietary product.
- **Icons:** `lucide_icons_flutter` (MIT wrapper) around Lucide icons (ISC).
- **Fonts:** the UI asks for Geist / Instrument Serif (SIL OFL 1.1) and falls back to the
  platform UI fonts when the font files are not bundled. If bundled, ship `OFL.txt` with them.
- **AI models:** no ML model weights ship in v1. Phase-2 models (MODNet, MI-GAN,
  Real-ESRGAN…) need a per-model entry in `docs/MODEL_LICENSES.md` before release; see
  `docs/research/03-browser-ai-tools.md` for the commercial-license review (BRIA RMBG is
  non-commercial and must not be used).
- **Claude API:** accessed through Anthropic's commercial API terms via the gateway; user
  photos are sent as a downscaled preview without metadata.

## Resolved Dart/Flutter packages
| Package | License |
|---|---|
| _fe_analyzer_shared | BSD-3-Clause |
| analyzer | BSD-3-Clause |
| android_file_picker | MIT |
| archive | MIT |
| args | BSD-3-Clause |
| async | BSD-3-Clause |
| boolean_selector | BSD-3-Clause |
| characters | BSD-3-Clause |
| cli_config | BSD-3-Clause |
| clock | Apache-2.0 |
| code_assets | BSD-3-Clause |
| collection | BSD-3-Clause |
| convert | BSD-3-Clause |
| coverage | BSD-3-Clause |
| cross_file | BSD-3-Clause |
| crypto | BSD-3-Clause |
| dbus | MPL-2.0 (unmodified use OK) |
| desktop_drop | Apache-2.0 |
| exif | MIT |
| fake_async | Apache-2.0 |
| ffi | BSD-3-Clause |
| ffi_leak_tracker | BSD-3-Clause |
| file | BSD-3-Clause |
| file_picker | MIT |
| file_picker_darwin | MIT |
| file_picker_linux | MIT |
| file_picker_platform_interface | MIT |
| file_picker_web | MIT |
| fixnum | BSD-3-Clause |
| flutter | BSD-3-Clause |
| flutter_driver | BSD-3-Clause (Flutter SDK) |
| flutter_lints | BSD-3-Clause |
| flutter_litert | Apache-2.0 |
| flutter_riverpod | MIT |
| flutter_test | BSD-3-Clause (Flutter SDK) |
| flutter_web_plugins | BSD-3-Clause (Flutter SDK) |
| frontend_server_client | BSD-3-Clause |
| fuchsia_remote_debug_protocol | BSD-3-Clause (Flutter SDK) |
| glob | BSD-3-Clause |
| hooks | BSD-3-Clause |
| http | BSD-3-Clause |
| http_methods | Apache-2.0 |
| http_multi_server | BSD-3-Clause |
| http_parser | BSD-3-Clause |
| image | MIT |
| integration_test | BSD-3-Clause (Flutter SDK) |
| io | BSD-3-Clause |
| jni | BSD-3-Clause |
| jni_flutter | BSD-3-Clause |
| jni_util | BSD-3-Clause |
| json_annotation | BSD-3-Clause |
| leak_tracker | BSD-3-Clause |
| leak_tracker_flutter_testing | BSD-3-Clause |
| leak_tracker_testing | BSD-3-Clause |
| lints | BSD-3-Clause |
| listen | BSD-3-Clause |
| logging | BSD-3-Clause |
| lucide_icons_flutter | MIT |
| matcher | BSD-3-Clause |
| material_color_utilities | Apache-2.0 |
| meta | BSD-3-Clause |
| mime | BSD-3-Clause |
| mocktail | MIT |
| node_preamble | MIT |
| objective_c | BSD-3-Clause |
| package_config | BSD-3-Clause |
| path | BSD-3-Clause |
| path_provider | BSD-3-Clause |
| path_provider_android | BSD-3-Clause |
| path_provider_foundation | BSD-3-Clause |
| path_provider_linux | BSD-3-Clause |
| path_provider_platform_interface | BSD-3-Clause |
| path_provider_windows | BSD-3-Clause |
| petitparser | MIT |
| platform | BSD-3-Clause |
| plugin_platform_interface | BSD-3-Clause |
| pool | BSD-3-Clause |
| posix | MIT |
| process | BSD-3-Clause |
| pub_semver | BSD-3-Clause |
| quiver | Apache-2.0 |
| record_use | BSD-3-Clause |
| riverpod | MIT |
| share_plus | BSD-3-Clause |
| share_plus_platform_interface | BSD-3-Clause |
| shelf | BSD-3-Clause |
| shelf_packages_handler | BSD-3-Clause |
| shelf_router | Apache-2.0 |
| shelf_static | BSD-3-Clause |
| shelf_web_socket | BSD-3-Clause |
| sky_engine | Apache-2.0 |
| source_map_stack_trace | BSD-3-Clause |
| source_maps | BSD-3-Clause |
| source_span | BSD-3-Clause |
| sprintf | BSD-2-Clause |
| stack_trace | BSD-3-Clause |
| state_notifier | MIT |
| stream_channel | BSD-3-Clause |
| string_scanner | BSD-3-Clause |
| sync_http | BSD-3-Clause |
| term_glyph | BSD-3-Clause |
| test | BSD-3-Clause |
| test_api | BSD-3-Clause |
| test_core | BSD-3-Clause |
| typed_data | BSD-3-Clause |
| universal_platform | MIT |
| url_launcher_linux | BSD-3-Clause |
| url_launcher_platform_interface | BSD-3-Clause |
| url_launcher_web | BSD-3-Clause |
| url_launcher_windows | BSD-3-Clause |
| uuid | MIT |
| vector_math | BSD-3-Clause |
| vm_service | BSD-3-Clause |
| watcher | BSD-3-Clause |
| web | BSD-3-Clause |
| web_socket | BSD-3-Clause |
| web_socket_channel | BSD-3-Clause |
| webdriver | Apache-2.0 |
| webkit_inspection_protocol | BSD-3-Clause |
| win32 | BSD-3-Clause |
| windows_file_picker | MIT |
| xdg_directories | BSD-3-Clause |
| xml | MIT |
| yaml | MIT |

