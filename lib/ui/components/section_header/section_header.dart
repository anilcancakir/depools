import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'section_header.recipe.dart';

/// **SectionHeader**
///
/// The label above a group of rows, with an optional count and an optional
/// trailing action. Sits a step below `MSPageHeader` in the type scale, because a
/// screen has one page title and several section heads.
///
/// The count is a formatted string, not an int, so a caller can write "42 ürün" or
/// "3 parti" rather than forcing this widget to know how to pluralise in a language
/// where pluralisation does not work like English.
///
/// **[action] must be something tappable, and must carry its own hit target.** The
/// row's `min-h-11` sizes the ROW, not the action inside it: an icon-only `MSButton`
/// centred in that row still lays out at its own padding, around 26dp, well under
/// the 44pt floor. Give it `className: 'p-3'` or an explicit `min-h-11 min-w-11`.
/// The count sits on the left so the right side reads as the one interactive spot.
/// Passing a bare [WText] here produces a control that looks like a link and does
/// nothing, which is worse than no action at all.
///
/// ### Example
///
/// ```dart
/// SectionHeader(
///   label: 'Hareketler',
///   count: '9 kayıt',
///   action: MSButton(size: ButtonSize.sm, intent: ButtonIntent.ghost, ...),
/// )
/// ```
@immutable
class SectionHeader extends StatelessWidget {
  /// The section label, already localised. Rendered uppercase by the recipe.
  final String label;

  /// An optional already-formatted count, for example `'9 kayıt'`.
  final String? count;

  /// An optional trailing control. Must be tappable and carry its own hit target.
  final Widget? action;

  /// Creates a [SectionHeader].
  const SectionHeader({
    super.key,
    required this.label,
    this.count,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final slots = sectionHeaderRecipe()();

    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['leading'],
          children: [
            WText(label, className: slots['label']),
            if (count != null) WText(count!, className: slots['count']),
          ],
        ),
        ?action,
      ],
    );
  }
}
