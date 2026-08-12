import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSSkeleton, SkeletonShape;

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
  static const IconData _confirmIcon = Icons.done;

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

  /// Fills the row with the quantity on record, in one tap.
  ///
  /// Null hides the control, which is what the preview catalog and any read-only use get.
  final VoidCallback? onConfirmRecorded;

  /// What the record says, already formatted, for the confirmation control to name.
  ///
  /// **The button said "same as record" and never said what the record was**, so the one gesture on
  /// the sheet that commits a number without typing it asked the user to agree with a figure they
  /// could not see. That is the shape D58 exists to prevent from the other direction: the expected
  /// quantity stays hidden until a count is entered, precisely so the number does not lead the
  /// count, and a button that WRITES that number is the one place it has to be visible, because
  /// tapping it is the act of accepting it.
  ///
  /// Already formatted by the caller (`1 piece + 200 g`), which is `CountLine.figure`'s job: only it
  /// knows the base unit, the content unit and D26's whole-plus-remainder split. Null falls back to
  /// the bare label, which is what a row with no figure to state gets.
  final String? recordedFigure;

  /// Whether this is a placeholder rather than a row.
  ///
  /// **The skeleton is the row's own shadow, not three grey bars**, for the same reason
  /// `ProductRow.skeleton` is: a generic bar says "something is coming" while a placeholder with
  /// this row's geometry says WHAT is coming, and it keeps the sheet from jumping when the content
  /// lands. Only the same component can guarantee the two match.
  final bool isSkeleton;

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
    this.onConfirmRecorded,
    this.recordedFigure,
  }) : isSkeleton = false;

  /// Creates a placeholder with this row's exact geometry.
  const CountRow.skeleton({super.key})
    : name = '',
      unit = '',
      verdict = '',
      counted = null,
      countedRemainder = null,
      remainderUnit = null,
      state = CountState.uncounted,
      onChanged = null,
      onRemainderChanged = null,
      onDecrement = null,
      onIncrement = null,
      onConfirmRecorded = null,
      recordedFigure = null,
      isSkeleton = true;

  @override
  Widget build(BuildContext context) {
    final slots = countRowRecipe()(variants: {'state': state.name});

    if (isSkeleton) return _buildSkeleton(slots);

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
                // **One control, two segments, and the units inside the fields they belong to.**
                // This used to be two separately bordered boxes with their units floating beside
                // them and a `+` between, which read as two independent quantities. It is one
                // quantity in two parts (a whole count and an opened remainder), and on a product
                // whose base unit equals its content unit both floating labels said the same word,
                // so nothing on screen said which box was which.
                QuantityStepper(
                  semanticName: name,
                  value: counted,
                  unit: unit,
                  onChanged: onChanged,
                  onDecrement: onDecrement,
                  onIncrement: onIncrement,
                  remainderValue: countedRemainder,
                  remainderUnit: remainderUnit,
                  remainderPlaceholder: Lang.get('components.count_row.opened'),
                  onRemainderChanged: onRemainderChanged,
                ),
                // The remainder's width is reserved on rows that do not have one, so the numbers
                // line up down the list: a list of repeating controls is a TABLE, and the left edge
                // is where the eye reads. Without this the minus button sat 96px further right on
                // every row that had a remainder.
                //
                // `hidden md:flex` keeps the reservation where it does work. Below `md` the control
                // has the card to itself, so a reserved column there would be dead space.
                if (remainderUnit == null) WDiv(className: slots['reservedGroup']),
              ],
            ),
          ],
        ),
        // The verdict, and beside it the one-tap confirmation while the row is still uncounted.
        //
        // **This is what keeps the count blind without making it slow** (D58). Pre-filling every
        // field with the recorded quantity was the obvious way to save typing and it is the strongest
        // form of the anchoring D58 exists to prevent: it does not just show the number, it accepts
        // it, so every row would open as "matched" and a user tapping through would confirm the
        // ledger rather than check it. It also collapses "nobody looked" into "counted and agreed",
        // so a shelf where three rows of forty were counted would report forty.
        //
        // One tap does the same work and keeps the difference that matters: agreeing becomes the
        // user's own action, the way an unticked box differs from a pre-ticked one. It disappears
        // once the row is counted, because from then on the verdict says what the state is.
        WDiv(
          className: slots['verdictRow'],
          children: [
            WText(verdict, className: slots['verdict']),
            if (!isSkeleton && state == CountState.uncounted && onConfirmRecorded != null)
              WAnchor(
                onTap: onConfirmRecorded,
                semanticLabel: Lang.get('components.count_row.confirm_recorded_for', {'name': name}),
                child: WDiv(
                  className: slots['confirm'],
                  children: [
                    const WIcon(_confirmIcon, className: 'size-3.5'),
                    // The figure when there is one, so the control names the number it is about to
                    // write rather than asking the user to agree with something off screen.
                    WText(
                      recordedFigure == null
                          ? Lang.get('components.count_row.confirm_recorded')
                          : Lang.get('components.count_row.confirm_recorded_figure', {
                              'figure': recordedFigure!,
                            }),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The placeholder, drawn from the same slots the real row uses.
  ///
  /// **It mirrors the real row's structure element for element, because anything less moves the
  /// controls.** The stepper's box is 144 x 40 because that is what `QuantityStepper` measures: two
  /// 40px buttons either side of a 64px field. And the reserved group is rendered even though it is
  /// empty, for the same reason the real row renders it: it holds the column above `md`, so omitting
  /// it let the single visible group slide right into the space it should have occupied.
  ///
  /// A guessed size anywhere here would make the sheet grow or shrink on the frame the content
  /// arrives, which is the one thing a placeholder exists to prevent.
  Widget _buildSkeleton(Map<String, String> slots) {
    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['top'],
          children: [
            WDiv(
              className: slots['skeletonName'],
              child: const MSSkeleton(shape: SkeletonShape.text, width: 168, height: 14),
            ),
            WDiv(
              className: slots['controls'],
              children: [
                WDiv(
                  className: slots['group'],
                  children: const [
                    MSSkeleton(shape: SkeletonShape.block, width: 144, height: 40),
                    MSSkeleton(shape: SkeletonShape.text, width: 28, height: 12),
                  ],
                ),
                WDiv(
                  className: slots['reservedGroup'],
                  children: [
                    WDiv(className: slots['plus']),
                    WDiv(className: slots['field']),
                    WDiv(className: slots['unit']),
                  ],
                ),
              ],
            ),
          ],
        ),
        const MSSkeleton(shape: SkeletonShape.text, width: 120, height: 12),
      ],
    );
  }
}
