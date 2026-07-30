# Orthanc Terminal Font Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick a terminal font family (from a fixed picklist) and size (via a stepper), persisted in `Settings`, previewed live in the Settings dialog, and applied immediately to every open pane on Save.

**Architecture:** Two new `Settings` fields (`fontFamily`: closed enum, `fontSize`: nullable double) follow the exact precedent `colorScheme`/`executablePath` already set. A new `terminal_font_families.dart` resolves the enum to concrete rendering values; `settings_validation.dart` gains a pure clamp helper. The existing color-scheme preview widget is generalized to also preview font. `PaneView`/`SplitView` gain two more pure-passthrough fields (mirroring `theme`), resolved once in `workspace_view.dart` — the same point `colorScheme` is already resolved.

**Tech Stack:** Flutter (Dart), the pinned `xterm` fork (`TerminalStyle`, `TerminalView`) — no new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-30-orthanc-terminal-font-design.md`

## Global Constraints

- No new `pubspec.yaml` dependencies — everything is built from `flutter`/`xterm`, already present.
- The font family picklist is exactly the 9 `TerminalFontFamily` values named below — do not add, remove, or reorder without returning to the spec.
- The font size clamp range is fixed at 8.0–32.0pt (`minTerminalFontSize`/`maxTerminalFontSize` in `lib/settings_validation.dart`).
- `lib/pane_view.dart`'s `fontFamilyFallback` list is never touched by this plan — every task threads a new primary `fontFamily` in front of it, unchanged.
- Every new file's doc comments and code shape mirror its nearest existing sibling (`terminal_color_schemes.dart` for `terminal_font_families.dart`; `settings_validation.dart`'s existing `executableExists()` for its new `clampFontSize()`) — this is an established-codebase plan, not a green-field one.
- `TerminalStyle.fontFamily`/`.fontSize` (pinned xterm fork) are **non-nullable**. Never pass `null` for either — resolve to a concrete value first (see Task 2's `defaultTerminalFontFamily`/`defaultTerminalFontSize`).

---

### Task 1: Settings model — `TerminalFontFamily` enum and two new `Settings` fields

**Files:**
- Modify: `lib/settings.dart`
- Test: `test/settings_test.dart`

**Interfaces:**
- Produces: `enum TerminalFontFamily { defaultFamily, hackNerdFontMono, menlo, monaco, consolas, jetBrainsMono, firaCode, cascadiaCode, courierNew }`; `Settings.fontFamily` (`TerminalFontFamily`, default `TerminalFontFamily.defaultFamily`); `Settings.fontSize` (`double?`, default `null`). Both round-trip through `settingsToJson`/`settingsFromJson`.

- [ ] **Step 1: Write the failing tests**

Append to `test/settings_test.dart`, just before the closing `}`:

```dart
  test('round-trips fontFamily through json', () {
    const expected = TerminalFontFamily.jetBrainsMono;
    final settings = Settings(fontFamily: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.fontFamily, expected);
  });

  test('a missing fontFamily field decodes to defaultFamily', () {
    const expected = TerminalFontFamily.defaultFamily;

    final result = settingsFromJson(const {});

    expect(result.fontFamily, expected);
  });

  test('an unrecognized fontFamily name decodes to defaultFamily', () {
    const expected = TerminalFontFamily.defaultFamily;

    final result = settingsFromJson(const {'fontFamily': 'not-a-real-font'});

    expect(result.fontFamily, expected);
  });

  test('round-trips fontSize through json', () {
    const expected = 18.0;
    final settings = Settings(fontSize: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.fontSize, expected);
  });

  test('a missing fontSize field decodes to null', () {
    const expected = null;

    final result = settingsFromJson(const {});

    expect(result.fontSize, expected);
  });

  test('an integer fontSize in json decodes to a double', () {
    const expected = 16.0;

    final result = settingsFromJson(const {'fontSize': 16});

    expect(result.fontSize, expected);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/settings_test.dart`
Expected: FAIL — `TerminalFontFamily` is undefined (analyzer/compile error), since it doesn't exist yet.

- [ ] **Step 3: Implement the minimal change**

Replace the full content of `lib/settings.dart` with:

```dart
/// The named terminal color schemes a user may pick in Settings. The actual
/// xterm TerminalTheme each maps to lives in terminal_color_schemes.dart —
/// this file only needs the closed set of identifiers a preference can hold.
enum TerminalColorScheme {
  defaultScheme,
  whiteOnBlack,
  dracula,
  solarizedDark,
  solarizedLight,
  monokai,
  oneDark,
  nord,
  gruvboxDark,
}

/// The named terminal font families a user may pick in Settings. The actual
/// font-family string each maps to lives in terminal_font_families.dart —
/// this file only needs the closed set of identifiers a preference can hold.
enum TerminalFontFamily {
  defaultFamily,
  hackNerdFontMono,
  menlo,
  monaco,
  consolas,
  jetBrainsMono,
  firaCode,
  cascadiaCode,
  courierNew,
}

/// The user's persisted preferences.
class Settings {
  const Settings({
    this.executablePath,
    this.colorScheme = TerminalColorScheme.defaultScheme,
    this.fontFamily = TerminalFontFamily.defaultFamily,
    this.fontSize,
  });

  final String? executablePath;
  final TerminalColorScheme colorScheme;
  final TerminalFontFamily fontFamily;
  final double? fontSize;
}

/// A blank path means "use the default" — normalized to null wherever a
/// path is read from disk or from user input.
String? normalizeExecutablePath(String? path) {
  final trimmed = path?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

Map<String, dynamic> settingsToJson(Settings settings) {
  return {
    'executablePath': settings.executablePath,
    'colorScheme': settings.colorScheme.name,
    'fontFamily': settings.fontFamily.name,
    'fontSize': settings.fontSize,
  };
}

Settings settingsFromJson(Map<String, dynamic> json) {
  return Settings(
    executablePath: normalizeExecutablePath(json['executablePath'] as String?),
    colorScheme: _colorSchemeFromName(json['colorScheme'] as String?),
    fontFamily: _fontFamilyFromName(json['fontFamily'] as String?),
    fontSize: (json['fontSize'] as num?)?.toDouble(),
  );
}

TerminalColorScheme _colorSchemeFromName(String? name) {
  return TerminalColorScheme.values.firstWhere(
    (scheme) => scheme.name == name,
    orElse: () => TerminalColorScheme.defaultScheme,
  );
}

TerminalFontFamily _fontFamilyFromName(String? name) {
  return TerminalFontFamily.values.firstWhere(
    (family) => family.name == name,
    orElse: () => TerminalFontFamily.defaultFamily,
  );
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/settings_test.dart`
Expected: PASS, all tests including the pre-existing `executablePath`/`colorScheme` ones.

- [ ] **Step 5: Commit**

```bash
git add lib/settings.dart test/settings_test.dart
git commit -m "Add fontFamily and fontSize fields to Settings"
```

---

### Task 2: Font family resolution — `lib/terminal_font_families.dart`

**Files:**
- Create: `lib/terminal_font_families.dart`
- Test: `test/terminal_font_families_test.dart`

**Interfaces:**
- Consumes: `TerminalFontFamily` (Task 1, `lib/settings.dart`).
- Produces: `const defaultTerminalFontFamily = 'monospace'`; `const defaultTerminalFontSize = 13.0`; `String terminalFontFamilyName(TerminalFontFamily family)`; `String terminalFontFamilyLabel(TerminalFontFamily family)`.

- [ ] **Step 1: Write the failing test**

Create `test/terminal_font_families_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_font_families.dart';

void main() {
  test('defaultFamily resolves to the default font family constant', () {
    const expected = defaultTerminalFontFamily;

    final result = terminalFontFamilyName(TerminalFontFamily.defaultFamily);

    expect(result, expected);
  });

  test('every family resolves to a non-empty name', () {
    for (final family in TerminalFontFamily.values) {
      expect(terminalFontFamilyName(family), isNotEmpty);
    }
  });

  test('every family has a non-empty display label', () {
    for (final family in TerminalFontFamily.values) {
      expect(terminalFontFamilyLabel(family), isNotEmpty);
    }
  });

  test('labels name each family', () {
    const expected = {
      TerminalFontFamily.defaultFamily: 'Default',
      TerminalFontFamily.hackNerdFontMono: 'Hack Nerd Font Mono',
      TerminalFontFamily.menlo: 'Menlo',
      TerminalFontFamily.monaco: 'Monaco',
      TerminalFontFamily.consolas: 'Consolas',
      TerminalFontFamily.jetBrainsMono: 'JetBrains Mono',
      TerminalFontFamily.firaCode: 'Fira Code',
      TerminalFontFamily.cascadiaCode: 'Cascadia Code',
      TerminalFontFamily.courierNew: 'Courier New',
    };

    for (final entry in expected.entries) {
      expect(terminalFontFamilyLabel(entry.key), entry.value);
    }
  });

  test('names match the literal font-family string for every non-default family', () {
    const expected = {
      TerminalFontFamily.hackNerdFontMono: 'Hack Nerd Font Mono',
      TerminalFontFamily.menlo: 'Menlo',
      TerminalFontFamily.monaco: 'Monaco',
      TerminalFontFamily.consolas: 'Consolas',
      TerminalFontFamily.jetBrainsMono: 'JetBrains Mono',
      TerminalFontFamily.firaCode: 'Fira Code',
      TerminalFontFamily.cascadiaCode: 'Cascadia Code',
      TerminalFontFamily.courierNew: 'Courier New',
    };

    for (final entry in expected.entries) {
      expect(terminalFontFamilyName(entry.key), entry.value);
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/terminal_font_families_test.dart`
Expected: FAIL — `package:orthanc/terminal_font_families.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/terminal_font_families.dart`:

```dart
import 'settings.dart';

/// Matches xterm's own TerminalStyle defaults (`_kDefaultFontFamily` /
/// `_kDefaultFontSize` in the pinned fork, unexported so not importable) —
/// what every pane already renders with today, unconfigured. TerminalStyle's
/// fontFamily/fontSize fields are non-nullable, so these stand in for a null
/// argument, which would not compile.
const defaultTerminalFontFamily = 'monospace';
const defaultTerminalFontSize = 13.0;

/// The actual font-family string a persisted [TerminalFontFamily] maps to,
/// for use as [TerminalStyle.fontFamily].
String terminalFontFamilyName(TerminalFontFamily family) {
  return switch (family) {
    TerminalFontFamily.defaultFamily => defaultTerminalFontFamily,
    TerminalFontFamily.hackNerdFontMono => 'Hack Nerd Font Mono',
    TerminalFontFamily.menlo => 'Menlo',
    TerminalFontFamily.monaco => 'Monaco',
    TerminalFontFamily.consolas => 'Consolas',
    TerminalFontFamily.jetBrainsMono => 'JetBrains Mono',
    TerminalFontFamily.firaCode => 'Fira Code',
    TerminalFontFamily.cascadiaCode => 'Cascadia Code',
    TerminalFontFamily.courierNew => 'Courier New',
  };
}

/// The label a font family picker shows the user.
String terminalFontFamilyLabel(TerminalFontFamily family) {
  return switch (family) {
    TerminalFontFamily.defaultFamily => 'Default',
    TerminalFontFamily.hackNerdFontMono => 'Hack Nerd Font Mono',
    TerminalFontFamily.menlo => 'Menlo',
    TerminalFontFamily.monaco => 'Monaco',
    TerminalFontFamily.consolas => 'Consolas',
    TerminalFontFamily.jetBrainsMono => 'JetBrains Mono',
    TerminalFontFamily.firaCode => 'Fira Code',
    TerminalFontFamily.cascadiaCode => 'Cascadia Code',
    TerminalFontFamily.courierNew => 'Courier New',
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/terminal_font_families_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/terminal_font_families.dart test/terminal_font_families_test.dart
git commit -m "Add terminal_font_families.dart with name/label resolvers"
```

---

### Task 3: Font size clamp — `lib/settings_validation.dart`

**Files:**
- Modify: `lib/settings_validation.dart`
- Test: `test/settings_validation_test.dart`

**Interfaces:**
- Produces: `const minTerminalFontSize = 8.0`; `const maxTerminalFontSize = 32.0`; `double clampFontSize(double size)`.

- [ ] **Step 1: Write the failing tests**

Append to `test/settings_validation_test.dart`, just before the closing `}`:

```dart
  test('clampFontSize passes a value already in range through unchanged', () {
    const expected = 16.0;

    final result = clampFontSize(16);

    expect(result, expected);
  });

  test('clampFontSize raises a value below the minimum to the minimum', () {
    const expected = minTerminalFontSize;

    final result = clampFontSize(2);

    expect(result, expected);
  });

  test('clampFontSize lowers a value above the maximum to the maximum', () {
    const expected = maxTerminalFontSize;

    final result = clampFontSize(50);

    expect(result, expected);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/settings_validation_test.dart`
Expected: FAIL — `clampFontSize`/`minTerminalFontSize`/`maxTerminalFontSize` are undefined.

- [ ] **Step 3: Implement**

Append to `lib/settings_validation.dart` (after the existing `executableExists` function):

```dart

const minTerminalFontSize = 8.0;
const maxTerminalFontSize = 32.0;

double clampFontSize(double size) {
  if (size < minTerminalFontSize) return minTerminalFontSize;
  if (size > maxTerminalFontSize) return maxTerminalFontSize;
  return size;
}
```

(Note: `double.clamp()` returns `num`, not `double` — this is written as explicit
comparisons instead, so the return type stays `double` with no cast.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/settings_validation_test.dart`
Expected: PASS, all tests including the pre-existing `executableExists` ones.

- [ ] **Step 5: Commit**

```bash
git add lib/settings_validation.dart test/settings_validation_test.dart
git commit -m "Add clampFontSize to settings_validation.dart"
```

---

### Task 4: Generalize the preview — `ColorSchemePreview` → `TerminalPreview`

**Files:**
- Rename: `lib/color_scheme_preview.dart` → `lib/terminal_preview.dart`
- Rename: `test/color_scheme_preview_test.dart` → `test/terminal_preview_test.dart`
- Modify: `lib/settings_dialog.dart` (import + widget reference only — mechanical, no new UI yet)
- Modify: `test/settings_dialog_test.dart` (import + type references only)

**Interfaces:**
- Consumes: `defaultTerminalFontFamily`, `defaultTerminalFontSize` (Task 2, `lib/terminal_font_families.dart`).
- Produces: `class TerminalPreview extends StatelessWidget` with `scheme` (`TerminalColorScheme`, required), `fontFamily` (`String`, default `defaultTerminalFontFamily`), `fontSize` (`double`, default `defaultTerminalFontSize`). `Terminal buildPreviewTerminal()` is unchanged and still exported from the same (renamed) file.

- [ ] **Step 1: Rename the files**

```bash
git mv lib/color_scheme_preview.dart lib/terminal_preview.dart
git mv test/color_scheme_preview_test.dart test/terminal_preview_test.dart
```

- [ ] **Step 2: Write the failing tests**

Replace the full content of `test/terminal_preview_test.dart` with:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_color_schemes.dart';
import 'package:orthanc/terminal_font_families.dart';
import 'package:orthanc/terminal_preview.dart';
import 'package:xterm/xterm.dart';

void main() {
  test(
    'sample terminal shows a prompt, colored listing, and an error line',
    () {
      const expected = [
        'orthanc:~ \$ ls -la',
        'Documents  Downloads  Projects  notes.txt',
        'zsh: command not found: fzf',
        '‣ main ✗',
      ];

      final terminal = buildPreviewTerminal();

      final lines = List.generate(
        expected.length,
        (i) => terminal.buffer.lines[i].getText(),
      );
      expect(lines, expected);
    },
  );

  testWidgets('renders a read-only TerminalView themed for the given scheme', (
    tester,
  ) async {
    const scheme = TerminalColorScheme.nord;
    final expected = terminalThemeFor(scheme);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TerminalPreview(scheme: scheme),
      ),
    );

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.theme.background, expected.background);
    expect(view.readOnly, isTrue);
  });

  testWidgets('renders with the given font family and size', (tester) async {
    const scheme = TerminalColorScheme.defaultScheme;
    const expectedFamily = 'JetBrains Mono';
    const expectedSize = 18.0;

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TerminalPreview(
          scheme: scheme,
          fontFamily: expectedFamily,
          fontSize: expectedSize,
        ),
      ),
    );

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.textStyle.fontFamily, expectedFamily);
    expect(view.textStyle.fontSize, expectedSize);
  });

  testWidgets('defaults to the standard font family and size when unset', (
    tester,
  ) async {
    const scheme = TerminalColorScheme.defaultScheme;

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TerminalPreview(scheme: scheme),
      ),
    );

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.textStyle.fontFamily, defaultTerminalFontFamily);
    expect(view.textStyle.fontSize, defaultTerminalFontSize);
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/terminal_preview_test.dart`
Expected: FAIL — `TerminalPreview` is undefined (the renamed file still defines `ColorSchemePreview`).

- [ ] **Step 4: Implement**

Replace the full content of `lib/terminal_preview.dart` with:

```dart
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

import 'settings.dart';
import 'terminal_color_schemes.dart';
import 'terminal_font_families.dart';

/// Static sample lines written into every preview terminal — a prompt, a
/// colored directory listing exercising the palette's accents, an error
/// line, and a git-branch-style accent row.
const _sampleContent =
    'orthanc:~ \$ ls -la\r\n'
    '\x1B[34mDocuments\x1B[0m  \x1B[32mDownloads\x1B[0m  '
    '\x1B[33mProjects\x1B[0m  notes.txt\r\n'
    '\x1B[31mzsh: command not found: fzf\x1B[0m\r\n'
    '\x1B[36m‣ main\x1B[0m \x1B[35m✗\x1B[0m';

/// A [Terminal] pre-loaded with [_sampleContent], for a non-interactive
/// preview. No PTY is attached — nothing is spawned, nothing can be typed
/// into it.
Terminal buildPreviewTerminal() {
  final terminal = Terminal(maxLines: 100);
  terminal.write(_sampleContent);
  return terminal;
}

/// A small, read-only terminal viewport rendering [scheme]/[fontFamily]/
/// [fontSize] against [buildPreviewTerminal]'s sample content, so a pending
/// pick can be judged before it's saved.
class TerminalPreview extends StatelessWidget {
  const TerminalPreview({
    super.key,
    required this.scheme,
    this.fontFamily = defaultTerminalFontFamily,
    this.fontSize = defaultTerminalFontSize,
  });

  final TerminalColorScheme scheme;
  final String fontFamily;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: TerminalView(
        buildPreviewTerminal(),
        theme: terminalThemeFor(scheme),
        readOnly: true,
        textStyle: TerminalStyle(fontFamily: fontFamily, fontSize: fontSize),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/terminal_preview_test.dart`
Expected: PASS.

- [ ] **Step 6: Update the two consumers so the whole suite still builds**

In `lib/settings_dialog.dart`, change the import:

```dart
import 'color_scheme_preview.dart';
```
to:
```dart
import 'terminal_preview.dart';
```

And change the widget reference:
```dart
            ColorSchemePreview(scheme: _colorScheme),
```
to:
```dart
            TerminalPreview(scheme: _colorScheme),
```

In `test/settings_dialog_test.dart`, change the import:
```dart
import 'package:orthanc/color_scheme_preview.dart';
```
to:
```dart
import 'package:orthanc/terminal_preview.dart';
```

And change both occurrences of `ColorSchemePreview` (in the `'preview reflects the pending selection before Save'` test) to `TerminalPreview`:
```dart
    final before = tester.widget<ColorSchemePreview>(
      find.byType(ColorSchemePreview),
    );
```
becomes:
```dart
    final before = tester.widget<TerminalPreview>(
      find.byType(TerminalPreview),
    );
```
and:
```dart
    final after = tester.widget<ColorSchemePreview>(
      find.byType(ColorSchemePreview),
    );
```
becomes:
```dart
    final after = tester.widget<TerminalPreview>(
      find.byType(TerminalPreview),
    );
```

- [ ] **Step 7: Run the full test suite to verify nothing broke**

Run: `flutter test`
Expected: PASS — every test, including `settings_dialog_test.dart`'s pre-existing color-scheme tests, which now reference `TerminalPreview` but exercise identical behavior.

- [ ] **Step 8: Commit**

```bash
git add lib/terminal_preview.dart test/terminal_preview_test.dart lib/color_scheme_preview.dart test/color_scheme_preview_test.dart lib/settings_dialog.dart test/settings_dialog_test.dart
git commit -m "Rename ColorSchemePreview to TerminalPreview, add font params"
```

---

### Task 5: Settings dialog UI — font family dropdown, size stepper, Reset font

**Files:**
- Modify: `lib/settings_dialog.dart`
- Test: `test/settings_dialog_test.dart`

**Interfaces:**
- Consumes: `TerminalFontFamily` (Task 1); `terminalFontFamilyName`, `terminalFontFamilyLabel`, `defaultTerminalFontSize` (Task 2); `clampFontSize`, `minTerminalFontSize`, `maxTerminalFontSize` (Task 3); `TerminalPreview` (Task 4).
- Produces: no new public API — this is the final leaf of the feature (the dialog itself).

- [ ] **Step 1: Write the failing tests**

Append to `test/settings_dialog_test.dart`, just before the closing `}`. This also needs `import 'package:orthanc/settings_validation.dart';` and `import 'package:orthanc/terminal_font_families.dart';` added at the top of the file, alongside the existing imports:

```dart
  testWidgets('font family dropdown is prefilled with the current selection', (
    tester,
  ) async {
    const expected = TerminalFontFamily.jetBrainsMono;

    await pumpDialog(tester, initial: const Settings(fontFamily: expected));

    final dropdown = tester.widget<DropdownButton<TerminalFontFamily>>(
      find.byType(DropdownButton<TerminalFontFamily>),
    );
    expect(dropdown.value, expected);
  });

  testWidgets('font size shows the default when unset', (tester) async {
    const expected = '13';

    await pumpDialog(tester);

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('font size shows the persisted value when set', (tester) async {
    const expected = '18';

    await pumpDialog(tester, initial: const Settings(fontSize: 18));

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('the + button increments font size', (tester) async {
    const expected = '14';
    await pumpDialog(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('the - button decrements font size', (tester) async {
    const expected = '12';
    await pumpDialog(tester);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('the + button disables at the maximum font size', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      initial: const Settings(fontSize: maxTerminalFontSize),
    );

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the - button disables at the minimum font size', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      initial: const Settings(fontSize: minTerminalFontSize),
    );

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.remove),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'Reset font is disabled when family and size are both already default',
    (tester) async {
      await pumpDialog(tester);

      final reset = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Reset font'),
      );
      expect(reset.onPressed, isNull);
    },
  );

  testWidgets('Reset font reverts family and size to default', (
    tester,
  ) async {
    const expectedFamily = TerminalFontFamily.defaultFamily;
    const expectedSize = '13';
    await pumpDialog(
      tester,
      initial: const Settings(
        fontFamily: TerminalFontFamily.jetBrainsMono,
        fontSize: 20,
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Reset font'));
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<TerminalFontFamily>>(
      find.byType(DropdownButton<TerminalFontFamily>),
    );
    expect(dropdown.value, expectedFamily);
    expect(find.text(expectedSize), findsOneWidget);
    final reset = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Reset font'),
    );
    expect(reset.onPressed, isNull);
  });

  testWidgets(
    'preview reflects the pending font family and size before Save',
    (tester) async {
      const expectedFamily = TerminalFontFamily.jetBrainsMono;
      const expectedSize = 14.0;
      await pumpDialog(tester);

      await tester.tap(find.byType(DropdownButton<TerminalFontFamily>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JetBrains Mono').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final preview = tester.widget<TerminalPreview>(
        find.byType(TerminalPreview),
      );
      expect(preview.fontFamily, terminalFontFamilyName(expectedFamily));
      expect(preview.fontSize, expectedSize);
    },
  );

  testWidgets('Save persists the picked font family and size', (
    tester,
  ) async {
    const expectedFamily = TerminalFontFamily.jetBrainsMono;
    const expectedSize = 14.0;
    final settings = await pumpDialog(tester);

    await tester.tap(find.byType(DropdownButton<TerminalFontFamily>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JetBrains Mono').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(settings.value.fontFamily, expectedFamily);
    expect(settings.value.fontSize, expectedSize);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/settings_dialog_test.dart`
Expected: FAIL — no `DropdownButton<TerminalFontFamily>`, no `Icons.add`/`Icons.remove` `IconButton`s, no `'Reset font'` button exist in the dialog yet.

- [ ] **Step 3: Implement**

Replace the full content of `lib/settings_dialog.dart` with:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import 'settings.dart';
import 'settings_store.dart';
import 'settings_validation.dart';
import 'terminal_color_schemes.dart';
import 'terminal_font_families.dart';
import 'terminal_preview.dart';

/// Opens the Settings dialog, letting the user override the executable each
/// new pane spawns.
Future<void> showSettingsDialog(
  BuildContext context, {
  required ValueNotifier<Settings> settings,
  required File file,
  required bool Function(String) exists,
  required String detectedDefault,
  required String version,
}) {
  return showDialog(
    context: context,
    builder: (_) => _SettingsDialog(
      settings: settings,
      file: file,
      exists: exists,
      detectedDefault: detectedDefault,
      version: version,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settings,
    required this.file,
    required this.exists,
    required this.detectedDefault,
    required this.version,
  });

  final ValueNotifier<Settings> settings;
  final File file;
  final bool Function(String) exists;
  final String detectedDefault;
  final String version;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _controller = TextEditingController(
    text: widget.settings.value.executablePath ?? '',
  );
  late var _colorScheme = widget.settings.value.colorScheme;
  late var _fontFamily = widget.settings.value.fontFamily;
  late var _fontSize = widget.settings.value.fontSize;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => executableExists(_controller.text, exists: widget.exists);

  double get _displayedFontSize => _fontSize ?? defaultTerminalFontSize;

  bool get _fontIsDefault =>
      _fontFamily == TerminalFontFamily.defaultFamily && _fontSize == null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Startup executable path'),
              const SizedBox(height: 4),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'default: ${widget.detectedDefault} (detected)',
                  errorText: _valid
                      ? null
                      : 'No file exists at this path — the old value is kept.',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Terminal color scheme'),
              const SizedBox(height: 4),
              DropdownButton<TerminalColorScheme>(
                value: _colorScheme,
                isExpanded: true,
                onChanged: (scheme) =>
                    setState(() => _colorScheme = scheme ?? _colorScheme),
                items: [
                  for (final scheme in TerminalColorScheme.values)
                    DropdownMenuItem(
                      value: scheme,
                      child: Text(terminalColorSchemeLabel(scheme)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Terminal font family'),
              const SizedBox(height: 4),
              DropdownButton<TerminalFontFamily>(
                value: _fontFamily,
                isExpanded: true,
                onChanged: (family) =>
                    setState(() => _fontFamily = family ?? _fontFamily),
                items: [
                  for (final family in TerminalFontFamily.values)
                    DropdownMenuItem(
                      value: family,
                      child: Text(terminalFontFamilyLabel(family)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Terminal font size'),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: _displayedFontSize <= minTerminalFontSize
                            ? null
                            : _decrementFontSize,
                      ),
                      Text('${_displayedFontSize.round()}'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _displayedFontSize >= maxTerminalFontSize
                            ? null
                            : _incrementFontSize,
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _fontIsDefault ? null : _resetFont,
                    child: const Text('Reset font'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TerminalPreview(
                scheme: _colorScheme,
                fontFamily: terminalFontFamilyName(_fontFamily),
                fontSize: _displayedFontSize,
              ),
              const SizedBox(height: 16),
              Text(
                'v${widget.version}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _controller.text.isEmpty ? null : _reset,
          child: const Text('Reset to default'),
        ),
        TextButton(
          onPressed: _colorScheme == TerminalColorScheme.defaultScheme
              ? null
              : _resetColorScheme,
          child: const Text('Reset scheme'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _valid ? _save : null, child: const Text('Save')),
      ],
    );
  }

  void _reset() => _controller.clear();

  void _resetColorScheme() =>
      setState(() => _colorScheme = TerminalColorScheme.defaultScheme);

  void _incrementFontSize() =>
      setState(() => _fontSize = clampFontSize(_displayedFontSize + 1));

  void _decrementFontSize() =>
      setState(() => _fontSize = clampFontSize(_displayedFontSize - 1));

  void _resetFont() => setState(() {
    _fontFamily = TerminalFontFamily.defaultFamily;
    _fontSize = null;
  });

  void _save() {
    final updated = Settings(
      executablePath: normalizeExecutablePath(_controller.text),
      colorScheme: _colorScheme,
      fontFamily: _fontFamily,
      fontSize: _fontSize,
    );
    widget.settings.value = updated;
    writeSettings(updated, file: widget.file);
    Navigator.pop(context);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/settings_dialog_test.dart`
Expected: PASS, all tests — the pre-existing path/color-scheme tests and every new font test.

- [ ] **Step 5: Run the full test suite and static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: PASS, every test in the project.

- [ ] **Step 6: Commit**

```bash
git add lib/settings_dialog.dart test/settings_dialog_test.dart
git commit -m "Add font family/size controls to the Settings dialog"
```

---

### Task 6: Live-apply wiring — `PaneView`, `SplitView`, `WorkspaceView`

**Files:**
- Modify: `lib/pane_view.dart`
- Modify: `lib/split_view.dart`
- Modify: `lib/workspace_view.dart`

**Interfaces:**
- Consumes: `terminalFontFamilyName`, `defaultTerminalFontSize` (Task 2).
- Produces: `PaneView.fontFamily` (`String`, required), `PaneView.fontSize` (`double`, required); `SplitView.fontFamily` (`String`, required), `SplitView.fontSize` (`double`, required) — both pure passthrough, mirroring the existing `theme` field exactly.

No test file is added in this task: neither `PaneView` nor `SplitView` has an existing widget test (both are pure passthrough around a real PTY-backed `TerminalView`/`Session`, exercised by hand rather than `flutter_test`, same as `theme` threading already is). `flutter analyze` plus the full `flutter test` run are this task's verification, same posture the spec names for live-apply.

- [ ] **Step 1: Thread `fontFamily`/`fontSize` through `PaneView`**

In `lib/pane_view.dart`, change the constructor and fields:

```dart
class PaneView extends StatefulWidget {
  const PaneView({
    super.key,
    required this.session,
    required this.focused,
    required this.onFocus,
    required this.onKeyEvent,
    required this.canCollapse,
    required this.collapsed,
    required this.theme,
    required this.fontFamily,
    required this.fontSize,
    required this.onToggleCollapse,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;
  final FocusOnKeyEventCallback onKeyEvent;
  final bool canCollapse;
  final bool collapsed;
  final TerminalTheme theme;
  final String fontFamily;
  final double fontSize;
  final VoidCallback onToggleCollapse;
```

And change the `TerminalStyle` construction inside `TerminalView` (still the same fallback list, comments unchanged above it) from:

```dart
                    textStyle: const TerminalStyle(
                      fontFamilyFallback: [
```

to:

```dart
                    textStyle: TerminalStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize,
                      fontFamilyFallback: const [
```

(the rest of the list and the closing `),` are unchanged — only the opening of the `TerminalStyle(...)` call and the list's own `const` position move).

- [ ] **Step 2: Thread `fontFamily`/`fontSize` through `SplitView`**

In `lib/split_view.dart`, change the constructor and fields:

```dart
  const SplitView({
    super.key,
    required this.node,
    required this.sessions,
    required this.focusedId,
    required this.collapsedIds,
    required this.collapsibleIds,
    required this.theme,
    required this.fontFamily,
    required this.fontSize,
    required this.onFocus,
    required this.onResize,
    required this.onToggleCollapse,
    required this.onKeyEvent,
  });

  static const dividerThickness = 4.0;

  final LayoutNode node;
  final Sessions sessions;
  final String focusedId;
  final Set<String> collapsedIds;
  final Set<String> collapsibleIds;
  final TerminalTheme theme;
  final String fontFamily;
  final double fontSize;
  final void Function(String id) onFocus;
  final void Function(LayoutNode split, int dividerIndex, double delta)
  onResize;
  final void Function(String id) onToggleCollapse;
  final FocusOnKeyEventCallback onKeyEvent;
```

Change `_shrinkablePane`'s `PaneView(...)` call from:

```dart
    return PaneView(
      session: session,
      focused: sessionId == focusedId,
      onFocus: () => onFocus(sessionId),
      onKeyEvent: onKeyEvent,
      canCollapse: collapsibleIds.contains(sessionId),
      collapsed: collapsedIds.contains(sessionId),
      theme: theme,
      onToggleCollapse: () => onToggleCollapse(sessionId),
    );
```

to:

```dart
    return PaneView(
      session: session,
      focused: sessionId == focusedId,
      onFocus: () => onFocus(sessionId),
      onKeyEvent: onKeyEvent,
      canCollapse: collapsibleIds.contains(sessionId),
      collapsed: collapsedIds.contains(sessionId),
      theme: theme,
      fontFamily: fontFamily,
      fontSize: fontSize,
      onToggleCollapse: () => onToggleCollapse(sessionId),
    );
```

Change `_childSplitView`'s recursive `SplitView(...)` call from:

```dart
  Widget _childSplitView(LayoutNode child) {
    return SplitView(
      node: child,
      sessions: sessions,
      focusedId: focusedId,
      collapsedIds: collapsedIds,
      collapsibleIds: collapsibleIds,
      theme: theme,
      onFocus: onFocus,
      onResize: onResize,
      onToggleCollapse: onToggleCollapse,
      onKeyEvent: onKeyEvent,
    );
  }
```

to:

```dart
  Widget _childSplitView(LayoutNode child) {
    return SplitView(
      node: child,
      sessions: sessions,
      focusedId: focusedId,
      collapsedIds: collapsedIds,
      collapsibleIds: collapsibleIds,
      theme: theme,
      fontFamily: fontFamily,
      fontSize: fontSize,
      onFocus: onFocus,
      onResize: onResize,
      onToggleCollapse: onToggleCollapse,
      onKeyEvent: onKeyEvent,
    );
  }
```

- [ ] **Step 3: Resolve `Settings` into `SplitView`'s new fields in `WorkspaceView`**

In `lib/workspace_view.dart`, add the import, alongside the existing ones:

```dart
import 'terminal_font_families.dart';
```

And change the `SplitView(...)` call inside `build()` from:

```dart
          child: SplitView(
            node: workspace.root,
            sessions: sessions,
            focusedId: workspace.focusedId,
            collapsedIds: workspace.collapsedIds,
            collapsibleIds: workspace.collapsibleIds,
            theme: terminalThemeFor(settings.colorScheme),
            onFocus: _onPaneFocus,
            onKeyEvent: _onKey,
            onToggleCollapse: _toggleCollapse,
```

to:

```dart
          child: SplitView(
            node: workspace.root,
            sessions: sessions,
            focusedId: workspace.focusedId,
            collapsedIds: workspace.collapsedIds,
            collapsibleIds: workspace.collapsibleIds,
            theme: terminalThemeFor(settings.colorScheme),
            fontFamily: terminalFontFamilyName(settings.fontFamily),
            fontSize: settings.fontSize ?? defaultTerminalFontSize,
            onFocus: _onPaneFocus,
            onKeyEvent: _onKey,
            onToggleCollapse: _toggleCollapse,
```

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: PASS, every test in the project — this task adds no new automated tests, so this run is a regression check, not a new-behavior check.

- [ ] **Step 6: Manual verification**

Run the app (`flutter run -d macos` or the platform at hand), open Settings, pick a non-default font family and a larger size, hit Save with at least one pane already open. Confirm: the open pane's text visibly changes font/size immediately (no reopen needed), and a freshly split pane after Save also uses the new font. This is the one check `flutter test` cannot perform — no real PTY/session exists in a widget test — same posture the spec names for live-apply and the executable-path setting's native-menu entry points before it.

- [ ] **Step 7: Commit**

```bash
git add lib/pane_view.dart lib/split_view.dart lib/workspace_view.dart
git commit -m "Wire fontFamily/fontSize from Settings into every pane"
```

---

## Self-Review

**Spec coverage:**
- Two new `Settings` fields, closed-enum + nullable-double shape → Task 1. ✓
- Font-family picklist resolution + shared defaults → Task 2. ✓
- 8–32pt clamp as a pure, testable function → Task 3. ✓
- Merged live preview (`TerminalPreview`) → Task 4. ✓
- Dialog UI: family dropdown, size stepper, "Reset font" at the block's bottom-right, `SingleChildScrollView` safety → Task 5. ✓
- Live-apply to every open pane via the same `ValueListenableBuilder` `colorScheme` already rides → Task 6. ✓
- Out-of-scope items (per-pane overrides, live font-install detection, font bundling, `fontFamilyFallback` changes) — none of the six tasks touch any of them. ✓

**Placeholder scan:** No "TBD"/"TODO"/"add appropriate handling" language anywhere above — every step carries the literal code to write or the literal command to run.

**Type consistency check:**
- `TerminalFontFamily` (Task 1) is consumed by the exact same name in Tasks 2, 4, 5.
- `terminalFontFamilyName`/`terminalFontFamilyLabel`/`defaultTerminalFontFamily`/`defaultTerminalFontSize` (Task 2) are consumed by those exact names in Tasks 4, 5, 6 — no renaming drift.
- `clampFontSize`/`minTerminalFontSize`/`maxTerminalFontSize` (Task 3) are consumed by those exact names in Task 5.
- `TerminalPreview`'s `fontFamily`/`fontSize` are `String`/`double` (Task 4) and Task 5's dialog always passes `terminalFontFamilyName(_fontFamily)`/`_displayedFontSize` — never the raw enum or a nullable double — matching that signature.
- `PaneView`/`SplitView`'s new `fontFamily`/`fontSize` fields are `String`/`double` (Task 6), matching what `workspace_view.dart` resolves via `terminalFontFamilyName(...)`/`?? defaultTerminalFontSize` before passing them in — no nullable value ever reaches either widget or `TerminalStyle`.
