String shellCommand({
  required bool isWindows,
  required Map<String, String> environment,
  String? configured,
}) {
  final trimmed = configured?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  if (isWindows) return 'cmd.exe';
  return environment['SHELL'] ?? 'bash';
}
