import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSInput;

import '../quantity_stepper/quantity_stepper.dart';
import 'count_row.recipe.dart';

/// How far a row has got in a count.
enum CountState {
  /// Nobody has counted it. Distinct from counting zero, and the distinction is the whole
  /// reason this enum exists: an uncounted row must not be adjusted at all.
  uncounted,

  /// Counted, and it agreed with the system.
  matched,

  /// Counted, and it did not.
  variance,
}

/// **CountRow**
///
/// One product being physically counted.
///
/// **The expected figure is hidden until a count is entered** (D58). Warehouse practice calls
/// this a blind count and the reason is anchoring: a counter shown "5" will look at a shelf
/// and see five. Once a number is in, the system figure and the difference appear
/// immediately, so a discrepancy is diagnosable while the user is still standing in front of
/// the shelf. Blind while counting, informed straight after.
///
/// **An empty field means NOT COUNTED, never zero.** Those are different facts with different
/// consequences: an uncounted row is left alone, and a row counted as zero writes the whole
/// balance off. A count sheet whose empty field meant zero would zero out every product the
/// user did not get to.
@immutable
class CountRow extends StatelessWidget {
  /// The product name.
  final String name;

  /// The count as typed, or null when nothing has been entered.
  final String? counted;

  /// The unit the count is in.
  final String unit;

  /// The opened-unit count, for a product that has a content level.
  ///
  /// Null when the product has no inner unit. Present as its OWN field rather than as a
  /// decimal in the main one, because D26 forbids collapsing a count and an open remainder
  /// into one number: "1,5 adet" is not a thing anybody can verify against a shelf, while
  /// "1 adet and 500 ml" is exactly what they are looking at.
  final String? countedRemainder;

  /// The inner unit, for example `ml`.
  final String? remainderUnit;

  /// The already-localised verdict: what the system held and what the difference is. Only
  /// meaningful once [counted] is set; the caller composes it because only it knows the
  /// arithmetic.
  final String verdict;

  /// Which state the row is in.
  final CountState state;

  /// Called as the count changes.
  final ValueChanged<String>? onChanged;

  /// Called when the count is stepped down.
  final VoidCallback? onDecrement;

  /// Called when the count is stepped up.
  final VoidCallback? onIncrement;

  /// Called as the opened-unit count changes.
  final ValueChanged<String>? onRemainderChanged;

  /// Creates a [CountRow].
  const CountRow({
    super.key,
    required this.name,
    required this.unit,
    required this.verdict,
    this.counted,
    this.countedRemainder,
    this.remainderUnit,
    this.state = CountState.uncounted,
    this.onChanged,
    this.onRemainderChanged,
    this.onDecrement,
    this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final slots = countRowRecipe()(variants: {'state': state.name});

    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['top'],
          children: [
            WText(name, className: slots['name']),
            WDiv(
              className: slots['controls'],
              children: [
                // A stepper on the countable field and a plain box on the remainder. The step
                // is one, so it only belongs where the unit is countable: plus-one-millilitre on
                // an opened carton is a control that cannot reach most of its own values.
                WDiv(
                  className: slots['stepper'],
                  child: QuantityStepper(
                    semanticName: name,
                    value: counted,
                    onChanged: onChanged,
                    onDecrement: onDecrement,
                    onIncrement: onIncrement,
                  ),
                ),
                WText(unit, className: slots['unit']),
                // The opened-unit column is ALWAYS reserved. A product with no content level
                // gets empty space of the same width, so every field in the list stays in its
                // column. Rendering the pair only where it exists moved the fields on the rows
                // that had it, which is the leading-glyph mistake one axis over.
                if (remainderUnit == null) ...[
                  WDiv(className: slots['plus']),
                  WDiv(className: slots['field']),
                  WDiv(className: slots['unit']),
                ] else ...[
                  WText('+', className: slots['plus']),
                  WDiv(
                    className: slots['field'],
                    child: MSInput(
                      // `bg-surface-container` overrides the recipe's `-high` fill. MSInput ships the input
                      // tone, which is `#E5E5EA` on a `#FFFFFF` card in light mode: darker than its
                      // container, so it reads as recessed and therefore disabled, and the hairline is
                      // too close in value to rescue it. Card tone plus the recipe's own border is the
                      // outlined-field look every platform uses for an ENABLED input.
                      className: 'bg-surface-container',
                      value: countedRemainder ?? '',
                      placeholder: '—',
                      type: InputType.number,
                      onChanged: onRemainderChanged,
                    ),
                  ),
                  WText(remainderUnit!, className: slots['unit']),
                ],
              ],
            ),
          ],
        ),
        WText(verdict, className: slots['verdict']),
      ],
    );
  }
}
