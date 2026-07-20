List<String> knownClaudePaths({required String home, required bool isWindows}) {
  if (isWindows) {
    return [
      '$home\\.local\\bin\\claude.exe',
      '$home\\AppData\\Roaming\\npm\\claude.cmd',
    ];
  }
  return [
    '$home/.local/bin/claude',
    '/opt/homebrew/bin/claude',
    '/usr/local/bin/claude',
  ];
}

String resolveClaudeCommand({
  required String home,
  required bool isWindows,
  required bool Function(String path) exists,
}) {
  for (final path in knownClaudePaths(home: home, isWindows: isWindows)) {
    if (exists(path)) return path;
  }
  return 'claude';
}
