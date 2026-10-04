import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/features/search/control_index.dart';

/// A control the user jumped to from search; [serial] re-triggers the reveal
/// when the same control is picked twice.
typedef RevealRequest = ({ControlEntry entry, int serial});

class RevealNotifier extends Notifier<RevealRequest?> {
  RevealNotifier(this.assetId);

  final String assetId;
  var _serial = 0;

  @override
  RevealRequest? build() => null;

  void reveal(ControlEntry entry) => state = (entry: entry, serial: ++_serial);
}

/// The last control revealed in one photo's editor.
final revealControlProvider =
    NotifierProvider.family<RevealNotifier, RevealRequest?, String>(
      RevealNotifier.new,
    );
