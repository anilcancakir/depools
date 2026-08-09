import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

/// A sheet's body, in a frame that reads like the sheet it will be shown in.
///
/// ### Why the sheets needed this
///
/// Six of them (`StockInSheet`, `StockOutSheet`, `StockMoveSheet`, `FieldEditorSheet`,
/// `ProductFilterSheet`, `UnitDefinitionSheet`) had no catalog entry at all, so the only way to
/// look at one was to boot the app and drive to the screen that opens it. Every `*View` in this
/// app is previewable and none of these were, which is a gap in coverage rather than a decision:
/// `.claude/rules/design.md` counts a bottom sheet as a screen, and half the interaction decisions
/// in `stock-movements.md` live inside one.
///
/// ### It is a frame, not the real sheet
///
/// `MSBottomSheet.show` needs a route to push onto and returns a value to a caller, neither of
/// which a static catalog entry has. So the body is rendered directly, inside a card that carries
/// the title and description the real sheet would draw above it. What that verifies is the body:
/// its layout, its states, its copy, at both widths. What it deliberately does not verify is the
/// presentation, which is `magic_starter`'s and is the same for every sheet in the app.
///
/// The width cap is the sheet's own: a bottom sheet does not span a desktop window, and reviewing
/// a body at 1200px would be reviewing a shape that never ships.
@immutable
class SheetPreviewFrame extends StatelessWidget {
  /// The sheet's title, as the real sheet would show it.
  final String title;

  /// The line under the title, when the real sheet has one.
  final String? description;

  /// The sheet body under test.
  final Widget child;

  /// Creates a [SheetPreviewFrame].
  const SheetPreviewFrame({
    super.key,
    required this.title,
    required this.child,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'w-full max-w-md p-4 rounded-lg bg-surface-container border border-color-border',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 pb-4',
          children: [
            WText(title, className: 'text-base font-semibold text-fg'),
            if (description != null)
              WText(description!, className: 'text-sm text-fg-muted'),
          ],
        ),
        child,
      ],
    );
  }
}
