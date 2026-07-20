String shellCommand({
  required bool isWindows,
  required Map<String, String> environment,
}) {
  if (isWindows) return 'cmd.exe';
  return environment['SHELL'] ?? 'bash';
}
