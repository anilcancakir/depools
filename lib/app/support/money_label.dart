import 'package:magic/magic.dart';

/// Symbols for the currencies this app actually deals in. Anything else renders its own ISO code,
/// which is the honest answer for a code nobody has taught this table yet.
const Map<String, String> _currencySymbols = <String, String>{
  'TRY': '₺',
  'USD': '\$',
  'EUR': '€',
  'GBP': '£',
};

/// Formats [amount] with [currency] trailing it, in the ACTIVE locale.
///
/// Follows `ProductListItem.format`'s separator rule (`,` unless the locale is `en`) and reads
/// it from `Lang.current` for the same reason that docblock gives: every caller is a row being
/// built for whatever locale is on screen right now, and threading a parameter through them all
/// would only move the same decision further from the digits.
///
/// **Diverges from `format` on one point: money keeps both decimals.** A whole-number quantity
/// drops its `,00` because the trailing zeros are noise at that size; a price does not, because
/// `34,9` on a receipt reads as thirty-four point nine of something rather than as thirty-four
/// lira ninety. `34.9` always renders `34,90`.
///
/// The currency comes AFTER the number, with a symbol for `TRY`, `USD`, `EUR` and `GBP` and the
/// ISO code itself for anything else. A null [currency] renders the bare number: `receipts.currency`
/// is nullable (migration line 63), because a photograph does not always say.
///
/// **No thousands separator, and negatives need no special casing rather than never occurring.**
/// A receipt carries discount and refund lines, and this app's own preview fixture has one at
/// `-12,00`; `toStringAsFixed(2)` renders it as `-12,00` with the sign in front, which is what a
/// receipt prints. A thousands separator is the genuinely absent one, and `ProductListItem.format`
/// omits it too: a four-digit total reads fine at `1234,56` and adding a group separator means
/// deciding which one per locale, which is the `intl` question this file is deliberately not asking.
///
/// Symbol placement is NOT locale-switched. `$34.90` reads better than `34.90 $` on an English
/// screen, and doing that properly needs a package with real locale data, which is exactly what
/// `intl` is deliberately not pulled in for here: one separator plus four symbols is the whole
/// difference at this size, and a package plus its locale data is a large answer to a small
/// question. Worth revisiting once slice 2 starts filling `currency` from real receipts.
String moneyLabel(num amount, String? currency) {
  final String fixed = amount.toStringAsFixed(2);
  final String number = Lang.current.languageCode == 'en'
      ? fixed
      : fixed.replaceAll('.', ',');

  if (currency == null) return number;

  final String symbol = _currencySymbols[currency] ?? currency;
  return '$number $symbol';
}
