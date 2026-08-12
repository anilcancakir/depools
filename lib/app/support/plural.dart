import 'package:magic/magic.dart';

/// Picks the singular or plural half of a `singular|plural` translation.
///
/// ```dart
/// // en: ':count change will be written|:count changes will be written'
/// plural('screens.stock_take.will_write', variances.length, {'count': variances.length});
/// ```
///
/// ### Why this exists here rather than in the framework
///
/// `magic`'s `Lang` has no `choice` (Laravel's `trans_choice`), so a count interpolated into a string
/// agrees with nothing: `1 rows saved`, `Save 1 differences`, `1 changes written`. Eight strings on
/// the count screen shipped that way, which is the kind of wrong that reads as nobody having looked.
///
/// **The real fix belongs in `magic`**, as a `Lang.choice(key, count, replace)`, and that is a PR in
/// that repository rather than an edit from here. This is the app-side stand-in, deliberately using
/// **Laravel's own pipe form** so the catalogues are already in the shape `Lang.choice` would read:
/// migrating means deleting this file and renaming the calls, with no touch to `en.json` or
/// `tr.json`.
///
/// ### The pipe rather than a `_one` / `_other` key pair
///
/// A key pair was the first shape and the localisation guard rejected it immediately, for a reason
/// worth keeping: `screens.mcp.revoke_one` already existed and means "revoke ONE connection", as
/// opposed to `revoke_all`. A suffix convention cannot tell that apart from a plural half, so the
/// guard would have demanded a `revoke_other` that has no meaning. The pipe lives in the VALUE, so
/// it collides with no name, keeps one key per string, and cannot drift out of sync with its own
/// other half.
///
/// ### Turkish carries one half, and that is correct rather than lazy
///
/// After a numeral Turkish does not inflect: `1 satır` and `5 satır` are both right. A `tr` value
/// with no pipe returns whole for every count, which is exactly what that grammar wants, so nothing
/// has to be duplicated to say it.
String plural(String key, int count, [Map<String, dynamic>? replace]) {
  final String value = Lang.get(key, replace);
  final int pipe = value.indexOf('|');

  // No pipe means the language does not inflect here, so the whole string is the answer. That also
  // makes a missing translation degrade to the raw key rather than to half of one.
  if (pipe < 0) return value;

  return count == 1 ? value.substring(0, pipe) : value.substring(pipe + 1);
}
