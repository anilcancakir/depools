import 'dart:io';

import 'package:depools/app/support/server_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// Which failures are allowed to speak in the server's own words.
///
/// **The label screen printed a Node.js stack trace at the user**, in a red panel where the sheet
/// preview belongs: absolute paths, `node_modules` internals and the developer's home directory,
/// because the controller read `response['message']` and rendered it. Laravel puts the exception
/// message there when `APP_DEBUG` is on, and "Server Error" when it is not, so neither environment
/// produces a sentence worth showing.
///
/// A 4xx is the opposite case and the reason this is a rule rather than a ban: 422 and the `abort()`
/// messages are copy this API wrote on purpose, and replacing them with a generic fallback would
/// throw away the one thing that tells the user what to fix.
void main() {
  MagicResponse response(int status, Object? body) =>
      MagicResponse(data: body, statusCode: status);

  const String fallback = 'The sheet could not be rendered.';

  group('a server error never speaks for itself', () {
    test('a 500 carrying a stack trace is replaced by the fallback', () {
      // A server path rather than a home directory one: `no_personal_paths_test` scans tracked files
      // for `/Users/...` and cannot tell a fixture from a leak, which is the right way round.
      final MagicResponse failure = response(500, <String, dynamic>{
        'message': 'The command "PATH=\$PATH node \'/srv/app/vendor/spatie/browsershot/browser.cjs\'" '
            'failed.\nExit Code: 1(General error)\nError Output:\nError: Could not find Chrome',
      });

      expect(serverMessage(failure, fallback), fallback);
    });

    test('a 503 with tidy-looking copy is still replaced, because the status decides', () {
      // The rule is the status, not the shape. A one-line 5xx body reads like copy and is still the
      // framework talking about itself rather than to the user.
      final MagicResponse failure = response(503, <String, dynamic>{'message': 'Service Unavailable'});

      expect(serverMessage(failure, fallback), fallback);
    });
  });

  group('a client error is this API talking to the user', () {
    test('a 422 message survives', () {
      final MagicResponse failure = response(422, <String, dynamic>{
        'message': 'The name may not be greater than 255 characters.',
      });

      expect(serverMessage(failure, fallback), 'The name may not be greater than 255 characters.');
    });

    test('a 409 message survives, so a refusal can explain itself', () {
      final MagicResponse failure = response(409, <String, dynamic>{
        'message': 'This location still holds stock.',
      });

      expect(serverMessage(failure, fallback), 'This location still holds stock.');
    });

    test('a 4xx with no message falls back rather than showing an empty panel', () {
      expect(serverMessage(response(404, <String, dynamic>{}), fallback), fallback);
      expect(serverMessage(response(404, <String, dynamic>{'message': ''}), fallback), fallback);
    });
  });

  test('a request that never reached the server falls back', () {
    // `statusCode` is 0 when the transport failed, so it is neither a client nor a server error and
    // the body is whatever the driver put there.
    expect(serverMessage(response(0, null), fallback), fallback);
  });

  test('a non-map body cannot leak, whatever it holds', () {
    // Laravel's debug 500 is HTML when the client did not ask for JSON, and `operator []` on a
    // String returns null rather than throwing, so this is about the value, not the crash.
    expect(serverMessage(response(500, '<html><body>Whoops</body></html>'), fallback), fallback);
  });

  test('nothing under lib reads the response body message itself', () {
    // The rule above is only worth having if it is the only door. This was thirteen call sites
    // across nine controllers, each re-deriving the same two lines, and one of them shipped the
    // stack trace. A first pass that looked only for the subscript form then missed two more:
    // `response.errorMessage` and `response.firstError` reach the SAME field, and one of those was
    // in a VIEW rather than a controller, which is why this walks all of `lib`.
    //
    // Comments are skipped, because several of these files EXPLAIN the field they no longer read
    // and one says outright that it deliberately does not. A scanner that cannot tell a comment
    // from a statement reports prose as a violation, which is how a grep count stops being a
    // violation count.
    //
    // A BARE `firstError` is deliberately not matched: that is the `ValidatesRequests` getter over
    // `validationErrors`, populated only from a 422, and the receiver is what makes it safe.
    final RegExp raw = RegExp(
      r"""response\['message'\]|response\.errorMessage|response\.firstError""",
    );

    final List<File> sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    // The guard on the guard: a walk that finds nothing reports a clean app forever.
    expect(sources.length, greaterThanOrEqualTo(80));

    // **One site, listed rather than pattern-matched.** `product_form_view` prefers the 422 field
    // sentence over the envelope's "(and 1 more error)" summary and gates it on `isValidationError`
    // so the 5xx fallback never runs. A regex cannot tell that apart from an ungated read, and a
    // checker that guesses is worse than a list that gets read.
    const Set<String> gated = <String>{'lib/resources/views/products/product_form_view.dart'};

    // The helper is the door, so of course it reads the field. Excluded by identity rather than by
    // pattern, so it cannot cover for anything else.
    const String helper = 'lib/app/support/server_message.dart';

    final Iterable<File> offenders = sources.where(
      (File f) =>
          f.path != helper &&
          !gated.contains(f.path) &&
          f
              .readAsLinesSync()
              .where((String line) => !line.trimLeft().startsWith('//'))
              .any(raw.hasMatch),
    );

    expect(
      offenders,
      isEmpty,
      reason: offenders
          .map((File f) => '${f.path} reads the body message instead of calling serverMessage')
          .join('\n'),
    );

    // The exemption is real, so it has to still be earned: a list naming a file that stopped
    // gating its read is a list that quietly grants the next leak.
    for (final String path in gated) {
      expect(
        File(path).readAsStringSync().contains('isValidationError'),
        isTrue,
        reason: '$path is exempt but no longer gates its read on the status',
      );
    }
  });
}
