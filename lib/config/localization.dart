import 'package:magic/magic.dart';

/// Localization configuration.
///
/// **This file exists because its absence was a defect, not a default.** Without it every key
/// magic reads (`localization.locale`, `localization.fallback_locale`,
/// `localization.supported_locales`) fell through to its built-in default of `en`, so a Turkish
/// product shipped its entire authentication, profile, teams and notification surface in English:
/// `Profile Settings`, `Team Settings`, `Browser Sessions`, `Save`, `Upgrade Account`. The app's own
/// screens were Turkish because their strings are literals in Dart, which is exactly why nobody
/// noticed the framework ones were not.
///
/// ### Why the translation had to be complete before this file could exist
///
/// magic's `Translator` REPLACES its sentence map when a locale loads; it does not merge with the
/// fallback (`_sentences = data.map(...)`, then `_sentences[key] ?? key`). So a partial `tr.json`
/// is worse than English: every key it does not cover renders as the raw key, and the user reads
/// `auth.login_title` on the login screen. `assets/lang/tr.json` therefore covers all 273 leaves of
/// `en.json`, and the generator asserted that count in both directions before writing the file.
///
/// ### The default is `en` (D116)
///
/// The primary market is outside Turkey, so `en` is the default here, which also makes the three
/// halves agree: `backend/config/app.php` and `magic_starter` both already defaulted to `en` while
/// this file defaulted to `tr`. Turkish stays a COMPLETE translation rather than a partial one, for
/// the reason in the section above, and the in-app picker offers both.
///
/// ### `auto_detect_locale` stays off, and it is now a question rather than an answer
///
/// It was off because the product was Turkey-first, and following the device locale would have handed
/// a Turkish user's English-set phone an English interface over a Turkish product. D116 removes that
/// argument: with an international market and an `en` default, device detection would mostly help.
/// Leaving it off is deliberate rather than settled, because a device set to a locale we do not ship
/// (`de_DE`, `fr_FR`) has no tested path here, and the translator replacing rather than merging its
/// sentence map is exactly the mechanism that turns an untested path into raw keys on screen.
Map<String, dynamic> get localizationConfig => {
  'localization': {
    'path': 'lang',
    'locale': env('APP_LOCALE', 'en'),
    'fallback_locale': 'en',
    'supported_locales': ['tr', 'en'],
    'auto_detect_locale': false,
  },
};
