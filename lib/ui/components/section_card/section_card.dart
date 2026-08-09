import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../section_header/section_header.dart';
import 'package:magic_starter/magic_starter.dart' show ButtonIntent, ButtonSize, MSButton;

import '../callout/callout.dart';
import 'section_card.recipe.dart';

/// **SectionCard**
///
/// One titled group of rows on a screen: the card surface, its [SectionHeader],
/// and the rows inside it.
///
/// It exists because both product screens had written the same card by hand eight
/// times. That is not only repetition: the sections have to agree, and a card whose
/// radius or gap drifted from its neighbour inside the same scroll view reads as a
/// different kind of thing rather than as a sibling.
///
/// ### Collapsing
///
/// [collapsible] makes the whole header the tap target and adds a chevron in
/// [SectionHeader]'s indicator slot. It is opt-in per section, because collapsing
/// is not free: a collapsed section hides its rows behind a tap, which is right for
/// a section a user reads occasionally and wrong for the one they came for.
///
/// **A collapsed section drops its children rather than hiding them.** Wind's
/// `hidden` still builds the subtree, so hiding a long list would keep paying for
/// every row. The count in the header is what keeps the section honest while
/// closed: "Dikkat gerekiyor, 3 ürün" collapsed still tells you there are three.
///
/// [initiallyExpanded] defaults to true. A section that starts closed on first
/// visit is a section a new user never discovers, and the attention section in
/// particular has to be visible before it can do its job.
///
/// ### Example
///
/// ```dart
/// SectionCard(
///   label: 'Dikkat gerekiyor',
///   count: '3 ürün',
///   collapsible: true,
///   children: [ProductRow(...), ProductRow(...)],
/// )
/// ```
class SectionCard extends StatefulWidget {
  static const IconData _expandedIcon = Icons.expand_less_outlined;
  static const IconData _collapsedIcon = Icons.expand_more_outlined;

  /// The section label, forwarded to [SectionHeader].
  final String label;

  /// An optional already-formatted count, for example `'3 ürün'`.
  final String? count;

  /// An optional tappable trailing control, forwarded to [SectionHeader].
  ///
  /// Safe to combine with [collapsible]: the header lays the action and the
  /// chevron out side by side. The action's own tap wins over the header's,
  /// because [WAnchor] does not receive a tap a descendant already handled.
  final Widget? action;

  /// The rows inside the card.
  final List<Widget> children;

  /// Whether the header toggles the body.
  final bool collapsible;

  /// Whether a [collapsible] section starts open.
  final bool initiallyExpanded;

  /// An already-localised message replacing [children] when this section could not load.
  ///
  /// ### Why the failure state lives here and not on each screen
  ///
  /// Every screen in this app is built out of these cards, and each card usually has its own
  /// source: the overview reads dates, shortages, the shopping list and recent movements from four
  /// places. Anılcan's call was that a failure replaces the SECTION and leaves the rest of the page
  /// working, so a dates request that times out does not take the four counters and the capture
  /// actions with it.
  ///
  /// Putting it on the card rather than on the screens is what makes that uniform: a screen opts in
  /// with one parameter and cannot invent a different failure shape.
  final String? error;

  /// Called by the retry action shown with [error]. Null renders the message with no action.
  final VoidCallback? onRetry;

  /// Creates a [SectionCard].
  const SectionCard({
    super.key,
    required this.label,
    required this.children,
    this.count,
    this.action,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.error,
    this.onRetry,
  });

  @override
  State<SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<SectionCard> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final slots = sectionCardRecipe()();

    // A non-collapsible card is never expandable, whatever the flag says, so the
    // body renders unconditionally there. Reading `_expanded` in that case would
    // let `initiallyExpanded: false` silently hide a section with no way to open it.
    final bool showBody = !widget.collapsible || _expanded;
    final String? error = widget.error;

    final Widget header = SectionHeader(
      label: widget.label,
      count: widget.count,
      action: widget.action,
      indicator: widget.collapsible
          ? WIcon(
              _expanded ? SectionCard._expandedIcon : SectionCard._collapsedIcon,
              className: slots['chevron'],
            )
          : null,
    );

    return WDiv(
      className: slots['root'],
      children: [
        if (widget.collapsible)
          WAnchor(onTap: _toggle, semanticLabel: widget.label, child: header)
        else
          header,
        if (showBody)
          WDiv(
            className: slots['body'],
            children: error == null
                ? widget.children
                : <Widget>[
                    // `danger` rather than `neutral`: a section the user cannot see the contents of
                    // is a gap in what they are being told, and a quiet note reads as decoration
                    // next to three sections that did load.
                    Callout(
                      intent: CalloutIntent.danger,
                      title: error,
                      message: Lang.get('components.section_card.error_message'),
                      action: widget.onRetry == null
                          ? null
                          : MSButton(
                              onPressed: widget.onRetry,
                              intent: ButtonIntent.secondary,
                              size: ButtonSize.sm,
                              className: 'py-3.5 axis-min',
                              child: WText(Lang.get('components.section_card.retry')),
                            ),
                    ),
                  ],
          ),
      ],
    );
  }
}
