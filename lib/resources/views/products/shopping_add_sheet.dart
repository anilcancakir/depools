import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSBottomSheet, MSButton, ButtonIntent, MSInput;

/// Adding something to the shopping list by hand.
///
/// **It may not be in the catalogue at all** (D100), and typing it here creates no product: doing
/// so would consume D4's unique-SKU meter, walking a free-tier tenant toward their limit for
/// something they never intend to stock. So the sheet asks for words and a number, not for a
/// product.
///
/// ### Two fields, and only one of them is required
///
/// The name is the line. The quantity defaults to one, because "one of these" is what a hand-typed
/// line almost always means, and a required number in front of a shopping list is a toll on the
/// gesture the list exists to make cheap.
@immutable
class ShoppingAddSheet extends StatefulWidget {
  /// Creates the [ShoppingAddSheet].
  const ShoppingAddSheet({super.key});

  /// Opens the sheet and returns what to add, or null when it was dismissed.
  static Future<ShoppingAddDraft?> show(BuildContext context) {
    return MSBottomSheet.show<ShoppingAddDraft>(
      context,
      title: Lang.get('screens.shopping.add_title'),
      body: const ShoppingAddSheet(),
    );
  }

  @override
  State<ShoppingAddSheet> createState() => _ShoppingAddSheetState();
}

class _ShoppingAddSheetState extends State<ShoppingAddSheet> {
  /// **A controller rather than a `value` prop plus a parsed copy in state.**
  ///
  /// The first version held a `num` and ignored an edit it could not parse. That is a real hazard
  /// rather than a hypothetical one: emptying the box left the model on its previous value, so the
  /// button stayed live and submitted a number the field was not showing. A controller has no
  /// second copy to disagree with, and `_parsedQuantity` reads the one the user can see.
  ///
  /// **`dusk:fill` cannot drive this field, and that is the harness rather than the app.** Measured:
  /// with `InputType.number` neither `dusk:fill` nor `dusk:press_key` puts anything in it, and
  /// removing that one line makes the same fill land immediately. So the quantity path is covered
  /// by a widget test instead, and the E2E pass drives the name, the submit and the result.
  final TextEditingController _quantity = TextEditingController(text: '1');

  String _name = '';

  /// The quantity as a number, or null when the box does not hold one.
  num? get _parsedQuantity {
    final num? parsed = num.tryParse(_quantity.text.trim().replaceAll(',', '.'));

    return parsed != null && parsed > 0 ? parsed : null;
  }

  /// A line needs words and a number. Both are checked here rather than at submit, so the button
  /// tells the truth about whether pressing it will do anything.
  bool get _isValid => _name.trim().isNotEmpty && _parsedQuantity != null;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-4 w-full',
      children: [
        _buildName(),
        _buildQuantity(),
        _buildActions(),
      ],
    );
  }

  Widget _buildName() {
    return WDiv(
      className: 'flex flex-col gap-2 w-full',
      children: [
        WText(
          Lang.get('screens.shopping.add_name'),
          className: 'text-xs font-medium uppercase tracking-wide text-fg-muted',
        ),
        MSInput(
          className: 'h-11 bg-surface-container',
          placeholder: Lang.get('screens.shopping.add_name'),
          semanticLabel: Lang.get('screens.shopping.add_name'),
          onChanged: (String next) => setState(() => _name = next),
        ),
      ],
    );
  }

  /// How many, prefilled with one.
  ///
  /// One is the answer a hand-typed line almost always wants, so it is there to accept rather than
  /// to type. Emptying the box disables the button rather than silently reinstating the one: the
  /// button saying "Add" while adding a number nobody chose is the worse of the two.
  Widget _buildQuantity() {
    return WDiv(
      className: 'flex flex-col gap-2 w-full',
      children: [
        WText(
          Lang.get('screens.shopping.add_quantity'),
          className: 'text-xs font-medium uppercase tracking-wide text-fg-muted',
        ),
        MSInput(
          className: 'h-11 bg-surface-container',
          controller: _quantity,
          // A numeric keyboard, which is right for a person even though it is the reason
          // `dusk:fill` cannot drive this field (see the class doc). The instrument does not get
          // to choose the keyboard.
          type: InputType.number,
          semanticLabel: Lang.get('screens.shopping.add_quantity'),
          // Only to re-evaluate the button. The text itself is the controller's, so nothing here
          // writes it back and nothing can overwrite what the user is typing.
          onChanged: (String _) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return WDiv(
      className: 'flex flex-col gap-2 w-full',
      children: [
        MSButton(
          onPressed: _isValid
              ? () => Navigator.of(context).pop(
                  ShoppingAddDraft(name: _name.trim(), quantity: _parsedQuantity!),
                )
              : null,
          disabled: !_isValid,
          // The fill carries the disabled state, because MSButton's own disabled styling does not.
          intent: _isValid ? ButtonIntent.primary : ButtonIntent.secondary,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.shopping.add_submit')),
        ),
        MSButton(
          onPressed: () => Navigator.of(context).pop(),
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.shopping.add_cancel')),
        ),
      ],
    );
  }
}

/// What the user typed into [ShoppingAddSheet].
@immutable
class ShoppingAddDraft {
  /// What to buy, already trimmed.
  final String name;

  /// How many, always positive.
  final num quantity;

  /// Creates a [ShoppingAddDraft].
  const ShoppingAddDraft({required this.name, required this.quantity});
}
