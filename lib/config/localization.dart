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
/// ### `auto_detect_locale` stays off
///
/// Depools is Turkey-first and its content, its number formatting and its receipt vocabulary are
/// Turkish. Following the device locale would hand a Turkish user's English-set phone an English
/// interface over a Turkish product, which is the worse of the two mismatches. `en` stays in
/// `supported_locales` so the in-app language picker still offers it, and so the fallback below has
/// somewhere to land if `tr.json` ever fails to load.
Map<String, dynamic> get localizationConfig => {
  'localization': {
    'path': 'lang',
    'locale': env('APP_LOCALE', 'tr'),
    'fallback_locale': 'en',
    'supported_locales': ['tr', 'en'],
    'auto_detect_locale': false,
  },
};
