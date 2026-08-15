import 'package:depools/app/support/mapped_or_null.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A payload the client cannot read has to resolve the screen AND stay visible.
///
/// Those are two claims and they fail in opposite directions, so both are asserted here: a mapping
/// that threw used to leave the list on skeleton rows forever, and a `catch` that only returned null
/// would fix the screen by hiding the reason.
void main() {
  group('mappedOrNull', () {
    test('a mapping that succeeds is returned untouched', () {
      expect(mappedOrNull(() => 'read', describing: 'a payload'), 'read');
    });

    test('a mapping that throws answers null instead of escaping', () {
      // Captured only to keep it out of the suite's output: this helper reports by design, and the
      // default handler prints. What is asserted here is the RETURN; the report has its own test.
      final FlutterExceptionHandler? previous = FlutterError.onError;

      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = previous);

      // The real shape: `fromApi` reads a required field with a hard cast, so an absent one is a
      // TypeError thrown out of an async method that nothing awaits with a catch.
      final Object? read = mappedOrNull<String>(
        () => (<String, Object?>{'base_unit': null}['base_unit'] as String),
        describing: 'a product list payload',
      );

      expect(read, isNull);
    });

    test('and it is REPORTED, so the reason is not swallowed', () {
      // The half a bare try/catch would get wrong. `FlutterError.onError` is the channel telescope's
      // exception watcher hooks, so asserting it fired is asserting the failure reaches a console
      // and a buffer rather than only a null.
      final List<FlutterErrorDetails> reported = <FlutterErrorDetails>[];
      final FlutterExceptionHandler? previous = FlutterError.onError;

      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      mappedOrNull<String>(() => throw StateError('unreadable'), describing: 'a shelf payload');

      expect(reported, hasLength(1));
      expect(reported.single.exception, isStateError);
      expect(
        reported.single.context.toString(),
        contains('a shelf payload'),
        reason: 'the description says WHICH payload; the stack only ever says fromApi',
      );
    });
  });
}
