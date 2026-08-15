import 'package:flutter/foundation.dart';

/// Runs a payload mapping, answering null instead of throwing out of an async controller.
///
/// **A screen that cannot read its payload has to say so, and three of them did not.** Every wired
/// controller here guards the REQUEST (`if (!response.successful) setError(...)`) and none guarded
/// the MAPPING. `ProductListItem.fromApi` reads required fields with hard casts
/// (`json['base_unit'] as String`), so an absent or null one throws a `TypeError` out of the async
/// method that called it, the state never leaves `loading`, and the screen sits on skeleton rows with
/// no message.
///
/// Measured rather than reasoned about: pointed at a server whose `/products` answered
/// `base_unit: null`, the stock list showed placeholders indefinitely with nothing in telescope's log
/// buffer and nothing in `dusk:exceptions`. Finding it took a direct API probe, because every
/// instrument reported a 200.
///
/// ### Reported, not swallowed
///
/// `FlutterError.reportError` is the framework's own channel and is what telescope's exception
/// watcher hooks, so the payload that could not be read still reaches a console and a buffer. The
/// only thing this changes is that the screen resolves to a state the user can act on. A bare
/// `catch` that returned null silently would be the anti-pattern this project's rules name.
///
/// [describing] names what was being read, because the stack alone says `fromApi` and every screen
/// calls that.
T? mappedOrNull<T>(T Function() map, {required String describing}) {
  try {
    return map();
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'depools',
        context: ErrorDescription('mapping $describing'),
      ),
    );

    return null;
  }
}
