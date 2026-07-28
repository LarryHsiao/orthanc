/// Whether a newer version landed since the user last saw this app running,
/// derived by comparing the running version against the last one recorded
/// in local prefs. `shouldShow` is false on the very first launch, when
/// there is nothing to compare against.
class UpdateNoteState {
  const UpdateNoteState({required this.shouldShow, required this.version});

  final bool shouldShow;
  final String version;
}

UpdateNoteState checkForUpdateNote({
  required String? lastSeenVersion,
  required String currentVersion,
}) {
  final shouldShow =
      lastSeenVersion != null && lastSeenVersion != currentVersion;
  return UpdateNoteState(shouldShow: shouldShow, version: currentVersion);
}

/// Reads the last-seen version, computes [checkForUpdateNote] against it,
/// then unconditionally persists the running version — so a launch that
/// shows no note still leaves the next launch something to compare against.
Future<UpdateNoteState> updateNoteOnLaunch({
  required Future<String?> Function() readLastSeenVersion,
  required Future<void> Function(String version) writeLastSeenVersion,
  required String currentVersion,
}) async {
  final lastSeen = await readLastSeenVersion();
  final state = checkForUpdateNote(
    lastSeenVersion: lastSeen,
    currentVersion: currentVersion,
  );
  await writeLastSeenVersion(currentVersion);
  return state;
}
