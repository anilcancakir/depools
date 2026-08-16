import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/support/unit_label.dart';
import 'field_editor_sheet.dart';

/// Asking how much of a product to keep on hand.
///
/// **The one number this app asks a person for.** `forecasting.md` wants it asked at the moment it
/// becomes useful rather than on the creation form, which is why the form deliberately omits it and
/// why this opens from the surfaces that reveal the gap: a running-low row that has no target, and
/// the product's own screen.
///
/// The reorder point is NOT asked here or anywhere (D48). "What is the supplier lead time for milk?"
/// is the question `product.md` says ends a household user's relationship with a product, so the app
/// infers that threshold from the tenant's own shopping rhythm and the phrase never reaches the
/// interface.
///
/// ### Three answers, and the sheet already distinguishes them
///
/// [FieldEditorSheet] pops the typed value on save, an empty string on clear, and null on dismiss.
/// That is exactly the vocabulary this needs: a number, a deliberate "no target", and "I changed my
/// mind", which must not be collapsed into two. Clearing is a real answer and dismissing is not an
/// answer at all.
abstract final class TargetSheet {
  /// The one-tap answers.
  ///
  /// Small whole numbers, because the question is "how many do you like to have" and the honest
  /// answers to that are small. They are not derived from the current stock: offering "the amount
  /// you happen to have right now" as the first chip would anchor the user to a number that is on
  /// screen precisely because it is too low.
  static const List<String> _quickAnswers = <String>['1', '2', '3', '5', '10'];

  /// Opens the editor and returns what the user decided.
  ///
  /// A [TargetDecision] rather than a bare `num?`, because null has to mean two different things
  /// and a caller that could not tell them apart would write "cleared" every time somebody
  /// dismissed the sheet.
  static Future<TargetDecision> show(
    BuildContext context, {
    required String unit,
    num? current,
  }) async {
    final String? answer = await FieldEditorSheet.show(
      context,
      label: Lang.get('screens.target.title'),
      // Says which situation this is. "No target yet" and "the target is 2" are different starting
      // points and the field alone cannot tell them apart.
      provenance: current == null
          ? Lang.get('screens.target.none_yet')
          : Lang.get('screens.target.current', {
              'value': current,
              'unit': unitLabel(unit, current),
            }),
      value: current?.toString(),
      unit: unit,
      kind: FieldEditorKind.number,
      // Nothing to clear. A target is a value the user set, never one the app inferred, so the
      // sheet's promise about removing the `otomatik` mark would be a sentence about a mark that
      // does not exist on this field.
      clearsMark: false,
      quickAnswers: _quickAnswers,
      // Which is what puts the clear button on the sheet. A target is optional by design: a product
      // with none is not misconfigured, it is one nobody has decided about.
      isOptional: true,
    );

    if (answer == null) return const TargetDecision.dismissed();
    if (answer.isEmpty) return const TargetDecision.cleared();

    final num? parsed = num.tryParse(answer.replaceAll(',', '.'));

    // Unparseable or non-positive is treated as no decision rather than as a clear. The server
    // refuses both anyway, and a round trip that answered 422 would tell the user their target had
    // failed to save when what actually happened is that they typed something that is not a target.
    if (parsed == null || parsed <= 0) return const TargetDecision.dismissed();

    return TargetDecision.set(parsed);
  }
}

/// What the user decided in [TargetSheet].
@immutable
class TargetDecision {
  /// The new target, or null when there is none to write.
  final num? value;

  /// Whether anything should be written at all.
  final bool isDecision;

  /// A target to keep.
  const TargetDecision.set(num this.value) : isDecision = true;

  /// No target on this product, deliberately.
  const TargetDecision.cleared() : value = null, isDecision = true;

  /// The sheet was closed without an answer.
  const TargetDecision.dismissed() : value = null, isDecision = false;
}
