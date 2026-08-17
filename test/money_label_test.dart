import 'dart:ui';

import 'package:depools/app/support/money_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// The one place a price becomes a string, following `ProductListItem.format`'s separator rule
/// and diverging on the one point money needs: both decimals, always.
///
/// ### Why the locale switch here is real and `unitLabel`'s is not
///
/// `unit_label_test.dart` cannot assert on a translated word because the catalogue never loads
/// under the test binding, only `Lang.isLoaded` flips to true while the sentence map stays empty
/// (see that file's docblock). `moneyLabel` does not have that problem: it never calls
/// `Lang.get`, it only reads `Lang.current.languageCode` to pick the separator, and
/// `Translator.setLocale` sets `_locale` unconditionally, even when the catalogue fetch behind it
/// fails. So switching locale here through `Lang.setLocale` and asserting on the separator is
/// exercising the real branch, not a fallback.
void main() {
  setUp(() async {
    // Each test starts from a known locale rather than whatever the previous test left behind,
    // since `Translator` is a process-wide singleton and tests in this file run in one binding.
    await Lang.setLocale(const Locale('en'), reload: false);
  });

  test('a fraction keeps both decimals in English, unlike a quantity', () {
    // The divergence from `ProductListItem.format` this function exists for: `34.9` would print
    // `34.9` there and must print `34.90` here, because a receipt total dropping its trailing
    // zero reads as a different number of decimals rather than as the same price.
    expect(moneyLabel(34.9, 'TRY'), '34.90 ₺');
  });

  test(
    'a fraction keeps both decimals in Turkish, with the comma separator',
    () async {
      await Lang.setLocale(const Locale('tr'), reload: false);

      expect(moneyLabel(34.9, 'TRY'), '34,90 ₺');
    },
  );

  test(
    'a whole number still carries its ,00, which a copy of format() would drop',
    () async {
      // `ProductListItem.format` prints a whole value through bare `toString()`, so `10` stays
      // `10`. Money is the opposite case: `10,00 ₺` is the price, and `10 ₺` reads as truncated.
      expect(moneyLabel(10, 'TRY'), '10.00 ₺');

      await Lang.setLocale(const Locale('tr'), reload: false);
      expect(moneyLabel(10, 'TRY'), '10,00 ₺');
    },
  );

  test('a null currency renders the bare number, in both locales', () {
    // `receipts.currency` is nullable (migration line 63): a photograph does not always say.
    expect(moneyLabel(34.9, null), '34.90');
  });

  test(
    'a null currency renders the bare number under the Turkish separator too',
    () async {
      await Lang.setLocale(const Locale('tr'), reload: false);

      expect(moneyLabel(34.9, null), '34,90');
    },
  );

  test('an unknown currency code renders as itself, in both locales', () {
    // The honest answer for a code this table has not been taught: the code, not a guess and not
    // a blank.
    expect(moneyLabel(34.9, 'CHF'), '34.90 CHF');
  });

  test(
    'an unknown currency code renders as itself under the Turkish separator too',
    () async {
      await Lang.setLocale(const Locale('tr'), reload: false);

      expect(moneyLabel(34.9, 'CHF'), '34,90 CHF');
    },
  );

  test('USD, EUR and GBP each carry their own symbol', () {
    expect(moneyLabel(1, 'USD'), '1.00 \$');
    expect(moneyLabel(1, 'EUR'), '1.00 €');
    expect(moneyLabel(1, 'GBP'), '1.00 £');
  });
}
