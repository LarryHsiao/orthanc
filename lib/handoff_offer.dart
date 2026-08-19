import 'dart:convert';

/// What a receiving instance needs to build a fresh session for a pane
/// arriving from another window and land it in the right place — the body
/// of a pane handoff offer, sent ahead of the pty itself ever crossing.
class PaneOffer {
  const PaneOffer({
    required this.manualName,
    required this.name,
    required this.activity,
    required this.executable,
    required this.pid,
    required this.rows,
    required this.columns,
  });

  /// Bumped whenever a field is added, removed, or reinterpreted —
  /// [decodePaneOffer] rejects anything but the version it was built
  /// against, rather than guess at a shape it has never seen. A sender and
  /// receiver on different app versions simply decline the offer instead
  /// of misreading it.
  static const currentVersion = 1;

  /// `Session.manualName` — the user-set name, if any.
  final String manualName;

  /// `Session.name` — set via OSC 1, if the running program ever has.
  final String name;

  /// `Session.activity` — the running program's current OSC 2 title, or
  /// its executable if that never fired.
  final String activity;

  final String executable;

  /// The pty's child process id, so a later `Pty.kill` can target the
  /// right process once the pty itself has crossed over.
  final int pid;

  final int rows;
  final int columns;

  Map<String, Object?> toJson() => {
    'v': currentVersion,
    'manualName': manualName,
    'name': name,
    'activity': activity,
    'executable': executable,
    'pid': pid,
    'rows': rows,
    'columns': columns,
  };
}

/// Encodes [offer] as an offer's wire body.
String encodePaneOffer(PaneOffer offer) => jsonEncode(offer.toJson());

/// Decodes an offer's wire body, or null on anything that isn't exactly
/// the shape [PaneOffer.currentVersion] promises — malformed JSON, a
/// missing or wrong-typed field, or a version this build has never seen.
/// Mirrors `readSettings`'s own degrade-rather-than-throw convention
/// (`settings_store.dart`): a stale or foreign offer is quietly refused,
/// never a crash in the receiver.
PaneOffer? decodePaneOffer(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['v'] != PaneOffer.currentVersion) return null;

    return PaneOffer(
      manualName: decoded['manualName'] as String,
      name: decoded['name'] as String,
      activity: decoded['activity'] as String,
      executable: decoded['executable'] as String,
      pid: decoded['pid'] as int,
      rows: decoded['rows'] as int,
      columns: decoded['columns'] as int,
    );
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}
