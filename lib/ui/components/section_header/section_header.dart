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
/// **[indicator] is the slot for something that is NOT tappable**: a chevron
/// showing whether a collapsible section is open, a spinner, a count badge. It
/// exists so that case stops being smuggled through [action], where a
/// non-interactive widget reads as a dead control. An indicator only makes sense
/// when an ancestor already makes the whole row the tap target, which is what
/// [SectionCard] does when it is collapsible.
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

  /// An optional non-interactive trailing indicator, rendered after [action].
  ///
  /// Only meaningful when an ancestor makes the whole header tappable.
  final Widget? indicator;

  /// Creates a [SectionHeader].
  const SectionHeader({super.key, required this.label, this.count, this.action, this.indicator});

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
        if (action != null || indicator != null)
          WDiv(className: slots['trailing'], children: [?action, ?indicator]),
      ],
    );
  }
}
