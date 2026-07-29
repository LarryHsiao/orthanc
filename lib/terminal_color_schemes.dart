import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

import 'settings.dart';

// Cursor/selection stay a neutral translucent grey and search-hit colors
// stay yellow/green/black across every scheme, matching xterm's own two
// built-in themes — neither varies those with the palette either.
const _cursor = Color(0xAAAEAFAD);
const _selection = Color(0xAAAEAFAD);
const _searchHitBackground = Color(0xFFFFFF2B);
const _searchHitBackgroundCurrent = Color(0xFF31FF26);
const _searchHitForeground = Color(0xFF000000);

const _dracula = TerminalTheme(
  cursor: _cursor,
  selection: _selection,
  foreground: Color(0xFFF8F8F2),
  background: Color(0xFF282A36),
  black: Color(0xFF21222C),
  red: Color(0xFFFF5555),
  green: Color(0xFF50FA7B),
  yellow: Color(0xFFF1FA8C),
  blue: Color(0xFFBD93F9),
  magenta: Color(0xFFFF79C6),
  cyan: Color(0xFF8BE9FD),
  white: Color(0xFFF8F8F2),
  brightBlack: Color(0xFF6272A4),
  brightRed: Color(0xFFFF6E6E),
  brightGreen: Color(0xFF69FF94),
  brightYellow: Color(0xFFFFFFA5),
  brightBlue: Color(0xFFD6ACFF),
  brightMagenta: Color(0xFFFF92DF),
  brightCyan: Color(0xFFA4FFFF),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

const _solarizedDark = TerminalTheme(
  cursor: _cursor,
  selection: _selection,
  foreground: Color(0xFF839496),
  background: Color(0xFF002B36),
  black: Color(0xFF073642),
  red: Color(0xFFDC322F),
  green: Color(0xFF859900),
  yellow: Color(0xFFB58900),
  blue: Color(0xFF268BD2),
  magenta: Color(0xFFD33682),
  cyan: Color(0xFF2AA198),
  white: Color(0xFFEEE8D5),
  brightBlack: Color(0xFF002B36),
  brightRed: Color(0xFFCB4B16),
  brightGreen: Color(0xFF586E75),
  brightYellow: Color(0xFF657B83),
  brightBlue: Color(0xFF839496),
  brightMagenta: Color(0xFF6C71C4),
  brightCyan: Color(0xFF93A1A1),
  brightWhite: Color(0xFFFDF6E3),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

const _monokai = TerminalTheme(
  cursor: _cursor,
  selection: _selection,
  foreground: Color(0xFFF8F8F2),
  background: Color(0xFF272822),
  black: Color(0xFF272822),
  red: Color(0xFFF92672),
  green: Color(0xFFA6E22E),
  yellow: Color(0xFFF4BF75),
  blue: Color(0xFF66D9EF),
  magenta: Color(0xFFAE81FF),
  cyan: Color(0xFFA1EFE4),
  white: Color(0xFFF8F8F2),
  brightBlack: Color(0xFF75715E),
  brightRed: Color(0xFFF92672),
  brightGreen: Color(0xFFA6E22E),
  brightYellow: Color(0xFFF4BF75),
  brightBlue: Color(0xFF66D9EF),
  brightMagenta: Color(0xFFAE81FF),
  brightCyan: Color(0xFFA1EFE4),
  brightWhite: Color(0xFFF9F8F5),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

const _solarizedLight = TerminalTheme(
  cursor: _cursor,
  selection: _selection,
  foreground: Color(0xFF657B83),
  background: Color(0xFFFDF6E3),
  black: Color(0xFF073642),
  red: Color(0xFFDC322F),
  green: Color(0xFF859900),
  yellow: Color(0xFFB58900),
  blue: Color(0xFF268BD2),
  magenta: Color(0xFFD33682),
  cyan: Color(0xFF2AA198),
  white: Color(0xFFEEE8D5),
  brightBlack: Color(0xFF002B36),
  brightRed: Color(0xFFCB4B16),
  brightGreen: Color(0xFF586E75),
  brightYellow: Color(0xFF657B83),
  brightBlue: Color(0xFF839496),
  brightMagenta: Color(0xFF6C71C4),
  brightCyan: Color(0xFF93A1A1),
  brightWhite: Color(0xFFFDF6E3),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

const _oneDark = TerminalTheme(
  cursor: _cursor,
  selection: _selection,
  foreground: Color(0xFFABB2BF),
  background: Color(0xFF282C34),
  black: Color(0xFF282C34),
  red: Color(0xFFE06C75),
  green: Color(0xFF98C379),
  yellow: Color(0xFFE5C07B),
  blue: Color(0xFF61AFEF),
  magenta: Color(0xFFC678DD),
  cyan: Color(0xFF56B6C2),
  white: Color(0xFFABB2BF),
  brightBlack: Color(0xFF5C6370),
  brightRed: Color(0xFFE06C75),
  brightGreen: Color(0xFF98C379),
  brightYellow: Color(0xFFE5C07B),
  brightBlue: Color(0xFF61AFEF),
  brightMagenta: Color(0xFFC678DD),
  brightCyan: Color(0xFF56B6C2),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

const _nord = TerminalTheme(
  cursor: _cursor,
  selection: _selection,
  foreground: Color(0xFFD8DEE9),
  background: Color(0xFF2E3440),
  black: Color(0xFF3B4252),
  red: Color(0xFFBF616A),
  green: Color(0xFFA3BE8C),
  yellow: Color(0xFFEBCB8B),
  blue: Color(0xFF81A1C1),
  magenta: Color(0xFFB48EAD),
  cyan: Color(0xFF88C0D0),
  white: Color(0xFFE5E9F0),
  brightBlack: Color(0xFF4C566A),
  brightRed: Color(0xFFBF616A),
  brightGreen: Color(0xFFA3BE8C),
  brightYellow: Color(0xFFEBCB8B),
  brightBlue: Color(0xFF81A1C1),
  brightMagenta: Color(0xFFB48EAD),
  brightCyan: Color(0xFF8FBCBB),
  brightWhite: Color(0xFFECEFF4),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

const _gruvboxDark = TerminalTheme(
  cursor: _cursor,
  selection: _selection,
  foreground: Color(0xFFEBDBB2),
  background: Color(0xFF282828),
  black: Color(0xFF282828),
  red: Color(0xFFCC241D),
  green: Color(0xFF98971A),
  yellow: Color(0xFFD79921),
  blue: Color(0xFF458588),
  magenta: Color(0xFFB16286),
  cyan: Color(0xFF689D6A),
  white: Color(0xFFA89984),
  brightBlack: Color(0xFF928374),
  brightRed: Color(0xFFFB4934),
  brightGreen: Color(0xFFB8BB26),
  brightYellow: Color(0xFFFABD2F),
  brightBlue: Color(0xFF83A598),
  brightMagenta: Color(0xFFD3869B),
  brightCyan: Color(0xFF8EC07C),
  brightWhite: Color(0xFFEBDBB2),
  searchHitBackground: _searchHitBackground,
  searchHitBackgroundCurrent: _searchHitBackgroundCurrent,
  searchHitForeground: _searchHitForeground,
);

/// The actual xterm [TerminalTheme] a persisted [TerminalColorScheme] maps
/// to.
TerminalTheme terminalThemeFor(TerminalColorScheme scheme) {
  return switch (scheme) {
    TerminalColorScheme.defaultScheme => TerminalThemes.defaultTheme,
    TerminalColorScheme.whiteOnBlack => TerminalThemes.whiteOnBlack,
    TerminalColorScheme.dracula => _dracula,
    TerminalColorScheme.solarizedDark => _solarizedDark,
    TerminalColorScheme.solarizedLight => _solarizedLight,
    TerminalColorScheme.monokai => _monokai,
    TerminalColorScheme.oneDark => _oneDark,
    TerminalColorScheme.nord => _nord,
    TerminalColorScheme.gruvboxDark => _gruvboxDark,
  };
}

/// The label a color scheme picker shows the user.
String terminalColorSchemeLabel(TerminalColorScheme scheme) {
  return switch (scheme) {
    TerminalColorScheme.defaultScheme => 'Default',
    TerminalColorScheme.whiteOnBlack => 'White on Black',
    TerminalColorScheme.dracula => 'Dracula',
    TerminalColorScheme.solarizedDark => 'Solarized Dark',
    TerminalColorScheme.solarizedLight => 'Solarized Light',
    TerminalColorScheme.monokai => 'Monokai',
    TerminalColorScheme.oneDark => 'One Dark',
    TerminalColorScheme.nord => 'Nord',
    TerminalColorScheme.gruvboxDark => 'Gruvbox Dark',
  };
}
