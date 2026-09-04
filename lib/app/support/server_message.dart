import 'package:magic/magic.dart';

/// The sentence to put in front of a user for a failed request.
///
/// Every controller here used to read `response['message']` and render whatever came back. That is
/// right for a 4xx, where the message is copy this API wrote (`422` validation, an `abort()` reason),
/// and wrong for a 5xx, where Laravel puts the EXCEPTION there: with `APP_DEBUG` on, the label
/// screen painted a Node.js stack trace into the UI, absolute paths and home directory included, in
/// the panel where the sheet preview belongs. With debug off the same field says `Server Error`,
/// which is not copy either.
///
/// So the status decides, not the shape of the string. A message that has to be inspected to be
/// trusted is a message that will leak the first time a new failure mode produces a tidy-looking
/// line, and the whole point of a 5xx is that the client cannot know what happened.
///
/// [fallback] is the screen's own already-localised sentence, which is also what an empty or absent
/// message falls back to.
String serverMessage(MagicResponse response, String fallback) {
  if (!response.clientError) return fallback;

  final Object? message = response['message'];

  return message is String && message.trim().isNotEmpty ? message : fallback;
}
