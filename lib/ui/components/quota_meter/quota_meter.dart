import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'quota_meter.recipe.dart';

export 'quota_meter.recipe.dart' show QuotaTone;

/// **QuotaMeter**
///
/// One metered axis: how much of it is used, how much there is, and what happens at the end.
///
/// ### Why the note is required rather than optional
///
/// D4 names the MVP's failure precisely: it metered five axes at once and a user could not tell
/// which limit they had hit, so it surfaced as a dead-end 403. A bar and a fraction say how full
/// something is; they do not say what stops. Making the consequence a required parameter is what
/// keeps that from being forgotten one meter at a time.
///
/// ### The bar is measured, not painted
///
/// Wind's Core Law 3 forbids interpolating a computed value into a `className`, so there is no
/// `w-[63%]` here: it would break the parser cache and mint an entry per percentage. The recipe
/// paints the track and the fill, and a Flutter `FractionallySizedBox` decides how much of it
/// shows. Wind paints, Flutter measures.
///
/// ### The bar is never the only signal
///
/// The fraction is always rendered as text beside the label, because DESIGN.md's rule that colour
/// never carries meaning alone applies to a length as much as to a hue, and because "34 / 50 ürün"
/// is what a user would repeat to somebody else.
@immutable
class QuotaMeter extends StatelessWidget {
  /// What is being metered, already localised.
  final String label;

  /// How much is used.
  final num used;

  /// The ceiling, or null for an unmetered axis on this plan.
  final num? limit;

  /// The already-localised reading, for example `34 / 50 ürün`.
  final String value;

  /// What happens when this axis runs out, already localised.
  ///
  /// Required for the reason in the class doc: a meter that does not say what it stops is the
  /// defect D4 exists to prevent.
  final String note;

  /// Creates a [QuotaMeter].
  const QuotaMeter({
    super.key,
    required this.label,
    required this.used,
    required this.value,
    required this.note,
    this.limit,
  });

  /// How full it is, clamped so a limit already exceeded still renders a full bar.
  double get _fraction {
    final num? ceiling = limit;
    if (ceiling == null || ceiling <= 0) return 0;
    return (used / ceiling).clamp(0.0, 1.0).toDouble();
  }

  /// Where the reading sits, in the three positions a user can act on.
  QuotaTone get _tone {
    if (limit == null) return QuotaTone.calm;
    if (_fraction >= 1) return QuotaTone.full;
    return _fraction >= 0.8 ? QuotaTone.near : QuotaTone.calm;
  }

  @override
  Widget build(BuildContext context) {
    final slots = quotaMeterRecipe()(variants: {'tone': _tone.name});

    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['header'],
          children: [
            WDiv(
              className: 'flex-1 min-w-0',
              child: WText(label, className: slots['label']),
            ),
            WDiv(
              className: 'shrink-0',
              child: WText(value, className: slots['value']),
            ),
          ],
        ),
        // An unmetered axis draws no bar at all. A full-width bar would read as "at the limit",
        // which is the opposite of what unlimited means.
        if (limit != null)
          WDiv(
            className: slots['track'],
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _fraction,
              child: WDiv(className: slots['fill']),
            ),
          ),
        WText(note, className: slots['note']),
      ],
    );
  }
}
