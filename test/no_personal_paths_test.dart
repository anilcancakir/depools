import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No tracked file carries a developer's home directory.
///
/// **This repository is public, and a personal absolute path is two defects at once.** It leaks the
/// author's filesystem layout, and it makes a documented command fail for everyone who copies it,
/// silently: a `cp` from a path that does not exist reports an error nobody reads, and a `grep`
/// against one matches nothing and reads as a clean result. The second failure is the one that has
/// actually happened here, in `.claude/agents/component-visual-reviewer.md`, where a path one segment
/// short of the project made every visual review pass its own check without running it.
///
/// The paths that legitimately hold one are all gitignored (`pubspec_overrides.yaml` needs ABSOLUTE
/// sibling paths, and `ios/Flutter/flutter_export_environment.sh`, `build/` and `.dart_tool/` are
/// generated), so tracking is exactly the right filter. `git ls-files` gives that, rather than a
/// hand-maintained skip list that would drift.
/// A home directory on each platform an agent might work from.
///
/// **`/home/runner` is excluded, and the exclusion is in the pattern rather than in a comment.** A
/// pasted CI log is legitimate content for a doc here, and every path in one begins
/// `/home/runner/work/depools/depools/`. A comment claiming the exclusion while the pattern matched
/// it anyway is what the review round caught, so the behaviour is pinned by the test below.
final RegExp _homeDirectory = RegExp(
  r'(/Users/[a-z][a-z0-9._-]*|/home/(?!runner(/|\b))[a-z][a-z0-9._-]*|C:\\Users\\)',
);

void main() {
  test('the pattern spares CI and catches a developer', () {
    // Pinned rather than described, because the description was wrong once already.
    expect(_homeDirectory.hasMatch('/home/runner/work/depools/depools/.dart_tool'), isFalse);
    expect(_homeDirectory.hasMatch('cd /home/runner'), isFalse);
    expect(_homeDirectory.hasMatch('/home/anilcan/Code'), isTrue);
    expect(_homeDirectory.hasMatch('/home/runnerx/Code'), isTrue);
    expect(_homeDirectory.hasMatch('/Users/somebody/Code'), isTrue);
    expect(_homeDirectory.hasMatch(r'C:\Users\somebody'), isTrue);
    expect(_homeDirectory.hasMatch('/usr/local/bin'), isFalse);
  });

  test('no tracked file carries a home directory path', () {
    final ProcessResult listed = Process.runSync('git', <String>['ls-files', '-z']);
    expect(listed.exitCode, 0, reason: 'git ls-files failed: ${listed.stderr}');

    final RegExp home = _homeDirectory;

    final List<String> offenders = <String>[];
    for (final String path in (listed.stdout as String).split('\u0000')) {
      if (path.isEmpty) continue;

      final File file = File(path);
      if (!file.existsSync()) continue;

      // This file names the shapes it forbids, so reading itself would always fail.
      if (path == 'test/no_personal_paths_test.dart') continue;

      // `pubspec.lock` is tracked AND locally poisoned by design: `flutter pub get` rewrites it with
      // the absolute sibling paths from `pubspec_overrides.yaml` on every run, so the working copy
      // always carries one and the committed copy never may. Its guard is `run_lockfile` in
      // `bin/check`, which reads the INDEX rather than the working tree and is the stronger test:
      // it rejects any `source: path` entry, absolute or relative.
      if (path == 'pubspec.lock') continue;

      final String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException {
        // A binary asset (a font, an icon) has no path to leak in text form.
        continue;
      }

      for (final RegExpMatch match in home.allMatches(text)) {
        final int line = text.substring(0, match.start).split('\n').length;
        offenders.add('$path:$line  ${match.group(0)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these tracked files carry a personal path, which a reader cannot copy and this '
          'repository publishes:\n${offenders.join('\n')}\n'
          'Derive it instead: the main checkout from inside a worktree is '
          r'`$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")`.',
    );
  });
}
