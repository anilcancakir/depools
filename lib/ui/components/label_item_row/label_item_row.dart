import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/support/plural.dart';
import '../quantity_stepper/quantity_stepper.dart';
import 'label_item_row.recipe.dart';

/// How the label count for a line is arrived at.
enum LabelCountMode {
  /// The user picks it. A lot-tracked product's label identifies the PRODUCT, so any
  /// number of identical stickers is meaningful.
  free,

  /// It is the number of selected serials and cannot be edited. A serial-tracked
  /// product's labels are all different, one per unit.
  perSerial,
}

/// **LabelItemRow**
///
/// One product in a print batch: what will be printed, how many, and whether it already
/// was.
///
/// **The count means two different things, and the row has to say which.** D45: a
/// lot-tracked product's label identifies the product, so its quantity is free and three
/// stickers are three copies of one design. A serial-tracked product's labels are all
/// different, one per unit, so the quantity is the number of selected serials and editing
/// it would be editing how many units exist. The stepper is absent on those rows rather
/// than disabled, because a disabled control invites a fight the user cannot win.
///
/// **Printed rows stay.** Criterion 5 requires a partially printed batch to be resumable,
/// which means the printed lines have to remain visible and countable; a jammed printer at
/// label 40 of 96 is the case this exists for.
@immutable
class LabelItemRow extends StatelessWidget {
  static const IconData _printedIcon = Icons.check_circle_outline;
  static const IconData _pendingIcon = Icons.label_outline;

  /// The product name.
  final String name;

  /// The code that will be printed, or null when one has to be generated first.
  final String? code;

  /// How many labels this line contributes.
  final int count;

  /// Where the count comes from.
  final LabelCountMode mode;

  /// Whether this line has already been printed in this batch.
  final bool isPrinted;

  /// Called when the count goes down. Null on a [LabelCountMode.perSerial] line.
  final VoidCallback? onDecrement;

  /// Called when the count goes up. Null on a [LabelCountMode.perSerial] line.
  final VoidCallback? onIncrement;

  /// Creates a [LabelItemRow].
  const LabelItemRow({
    super.key,
    required this.name,
    required this.count,
    this.code,
    this.mode = LabelCountMode.free,
    this.isPrinted = false,
    this.onDecrement,
    this.onIncrement,
  });

  /// The already-localised second line: the code, or what will happen instead.
  ///
  /// A product with no barcode is never blocked (the doc says so outright); it says a code
  /// will be generated. That code is Code128 with a tenant prefix rather than a fabricated
  /// EAN-13, so an internal label can never be mistaken for a manufacturer barcode, and
  /// naming it here is what makes criterion 6 visible rather than merely true.
  String get _meta => switch ((code, mode)) {
    // **`'$c · $count seri'` was a hardcoded Turkish word and a concatenation**, which breaks two rules
    // on one line: the copy test cannot see an interpolated string and `localization_test` cannot check
    // a placeholder that is not there. It rendered as `MK-1 · 1 seri` on an English screen, and #79's
    // `mode: per_serial` is what made it reachable with real data for the first time.
    //
    // The count goes through `plural` like every other count in the app. The first version of this
    // line avoided it and gave the reason that no component reaches into `app/support`, which is
    // false: nine other components do, for `unit_label`, `icon_catalogue` and `location_appearance`.
    // So the English inflects here rather than being phrased around.
    (final String c?, LabelCountMode.perSerial) => Lang.get(
      'components.label_item_row.serial_meta',
      {
        'code': c,
        'count': plural('components.label_item_row.serial_count', count, {'count': count}),
      },
    ),
    (final String c?, _) => c,
    (null, _) => Lang.get('components.label_item_row.will_generate'),
  };

  @override
  Widget build(BuildContext context) {
    final slots = labelItemRowRecipe()(variants: {'state': isPrinted ? 'printed' : 'pending'});

    return WDiv(
      className: slots['root'],
      children: [
        // The gutter is reserved on every row whatever the state, so a printed line does
        // not shift its own name relative to a pending one.
        WDiv(
          className: slots['iconBox'],
          child: WIcon(isPrinted ? _printedIcon : _pendingIcon, className: slots['icon']),
        ),
        WDiv(
          className: slots['body'],
          children: [
            WText(name, className: slots['name']),
            WText(_meta, className: slots['meta']),
          ],
        ),
        // A printed line loses its stepper too. Its labels are on a sheet already, so
        // changing the count would describe a past event, and the row says as much two
        // lines down. Absent rather than disabled, the same call the serial row makes.
        if (mode == LabelCountMode.free && !isPrinted)
          QuantityStepper(
            semanticName: name,
            value: '$count',
            placeholder: '0',
            onDecrement: onDecrement,
            onIncrement: onIncrement,
          )
        // **This said `'$count etiket'` and nothing could see it.** `no_hardcoded_copy_test` scans for
        // Turkish CHARACTERS and `etiket` is pure ASCII, which that test's own comment records as a
        // permanent hole, so an English user resuming a half-printed batch read "4 etiket". It is the
        // branch for every PRINTED line as well as for a serial one, and #79's `is_printed` is what
        // made it reachable with server data.
        else
          WText(
            plural('components.label_item_row.fixed_count', count, {'count': count}),
            className: slots['fixedCount'],
          ),
      ],
    );
  }
}
