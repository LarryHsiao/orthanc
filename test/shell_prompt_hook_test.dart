import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/shell_prompt_hook.dart';

void main() {
  group('shellKind', () {
    test('recognizes bash', () {
      const expected = ShellKind.bash;

      final result = shellKind('/bin/bash');

      expect(result, expected);
    });

    test('recognizes zsh', () {
      const expected = ShellKind.zsh;

      final result = shellKind('/bin/zsh');

      expect(result, expected);
    });

    test('returns null for a shell it does not know how to hook', () {
      const expected = null;

      final result = shellKind('/usr/bin/fish');

      expect(result, expected);
    });
  });

  group('bashPromptHookScript', () {
    test('sources the user rc file when one is given', () {
      final expected =
          '[ -f "/home/larry/.bashrc" ] && source "/home/larry/.bashrc"';

      final result = bashPromptHookScript(userBashrc: '/home/larry/.bashrc');

      expect(result.contains(expected), isTrue);
    });

    test('omits the source line when there is no user rc file', () {
      final result = bashPromptHookScript(userBashrc: null);

      expect(result.contains('source'), isFalse);
    });

    test('sets an OSC 2 title, never OSC 0, in the printf line', () {
      final result = bashPromptHookScript(userBashrc: null);

      expect(result.contains(']2;%s'), isTrue);
      expect(result.contains(']0;'), isFalse);
    });

    test('preserves any PROMPT_COMMAND the sourced rc file already set', () {
      final expected = r'${PROMPT_COMMAND:+; $PROMPT_COMMAND}';

      final result = bashPromptHookScript(userBashrc: null);

      expect(result.contains(expected), isTrue);
    });
  });

  group('zshPromptHookScript', () {
    test('sources the user rc file when one is given', () {
      final expected =
          '[ -f "/home/larry/.zshrc" ] && source "/home/larry/.zshrc"';

      final result = zshPromptHookScript(userZshrc: '/home/larry/.zshrc');

      expect(result.contains(expected), isTrue);
    });

    test('omits the source line when there is no user rc file', () {
      final result = zshPromptHookScript(userZshrc: null);

      expect(result.contains('source'), isFalse);
    });

    test('appends to precmd_functions rather than overwriting precmd', () {
      final expected = 'precmd_functions+=(__orthanc_title_hook)';

      final result = zshPromptHookScript(userZshrc: null);

      expect(result.contains(expected), isTrue);
    });
  });

  group('cmdPromptHookArguments', () {
    test('runs cmd.exe with /K so it stays interactive', () {
      const expected = '/K';

      final result = cmdPromptHookArguments();

      expect(result.first, expected);
    });

    test('sets an OSC 2 title, never OSC 0, via the PROMPT special codes', () {
      final result = cmdPromptHookArguments();

      expect(result.last.contains(r']2;'), isTrue);
      expect(result.last.contains(r']0;'), isFalse);
    });
  });

  group('shellPromptHook', () {
    test('uses the cmd.exe hook on Windows regardless of executable', () {
      final expected = cmdPromptHookArguments();

      final result = shellPromptHook(
        isWindows: true,
        executable: 'cmd.exe',
        environment: const {},
      );

      expect(result.arguments, expected);
    });

    test(
      'returns no launch extras for a shell it does not know how to hook',
      () {
        const expected = ShellLaunch.none;

        final result = shellPromptHook(
          isWindows: false,
          executable: '/usr/bin/fish',
          environment: const {},
        );

        expect(result.arguments, expected.arguments);
        expect(result.environment, expected.environment);
      },
    );

    test('writes a bash rcfile and points --rcfile at it', () {
      final result = shellPromptHook(
        isWindows: false,
        executable: '/bin/bash',
        environment: const {'HOME': '/home/larry'},
      );

      expect(result.arguments.first, '--rcfile');
      final rcFile = File(result.arguments.last);
      expect(rcFile.existsSync(), isTrue);
      expect(
        rcFile.readAsStringSync(),
        bashPromptHookScript(userBashrc: '/home/larry/.bashrc'),
      );
    });

    test('writes a zsh .zshrc and points ZDOTDIR at its directory', () {
      final result = shellPromptHook(
        isWindows: false,
        executable: '/bin/zsh',
        environment: const {'HOME': '/home/larry'},
      );

      expect(result.arguments, isEmpty);
      final zdotdir = result.environment['ZDOTDIR'];
      expect(zdotdir, isNotNull);
      final rcFile = File('$zdotdir/.zshrc');
      expect(rcFile.existsSync(), isTrue);
      expect(
        rcFile.readAsStringSync(),
        zshPromptHookScript(userZshrc: '/home/larry/.zshrc'),
      );
    });
  });
}
