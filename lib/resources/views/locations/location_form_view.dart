import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show ButtonIntent, MSButton, MSInput;

import '../../../app/support/location_appearance.dart';
import '../../../ui/components/choice_chip/choice_chip.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/layouts/app_page_scaffold.dart';
import 'location_fixtures.dart';
import 'location_index_view.dart' show LocationNode;

/// Creating or renaming a place, which the two "Konum ekle" buttons could not do.
///
/// ### The depth cap and the cycle guard are the design, not validation trivia
///
/// `data-model.md` caps `locations.depth` at 6 and rejects a location placed inside its own
/// descendant, and invariant 7 tests both. A form that discovers those at submit time turns a
/// modelled constraint into an error message. So the parent picker states the depth the choice
/// produces, and a parent that would breach the cap is simply not offered.
///
/// The MVP is the counterexample the schema section names: it walked `parent_location_id`
/// recursively with no depth limit and no cycle guard at all.
///
/// ### The icon is a real field, not decoration
///
/// `LocationRow` renders every node's glyph, roots and children alike, because a tree where only
/// roots carry one makes children read as text under a heading rather than as places. That only
/// works if this form actually asks for it, so the icon row sits beside the name rather than in an
/// optional section.
///
/// ### The starter template belongs here
///
/// `location-assignment.md` promises a first-run template ("Mutfak / Kiler / Depo") and the
/// locations empty state offers it. It creates several locations at once, so it is an action ON
/// this screen rather than a separate one.
@immutable
class LocationFormView extends StatefulWidget {
  /// Creates the [LocationFormView] for a new location.
  const LocationFormView({super.key});

  @override
  State<LocationFormView> createState() => _LocationFormViewState();
}

class _LocationFormViewState extends State<LocationFormView> {
  /// The tick on the chosen colour, so selection is never carried by the tint alone.
  static const IconData _selectedIcon = Icons.check;

  /// `data-model.md`'s cap, stated once.
  static const int _maxDepth = 6;

  String _name = '';
  String? _parentPath;

  /// **Names, not an index into a local list.** This screen used to hold its own six glyphs and
  /// store the position of the chosen one, which meant the form could not produce a value the
  /// column accepts: `locations.icon` is CHECKed against a catalogue of sixteen names, and a
  /// position is meaningless the moment that list is reordered. Both now come from
  /// `location_appearance.dart`, which is also what the tree reads.
  String _icon = locationIcons.keys.first;
  String _colour = locationFallbackColour;

  bool get _isValid => _name.trim().isNotEmpty;

  /// The depth this location would land at.
  int get _depth {
    if (_parentPath == null) return 1;
    final LocationNode? parent = _parentOf(_parentPath!);
    return (parent?.depth ?? 0) + 2;
  }

  LocationNode? _parentOf(String path) {
    for (final LocationNode node in locationTree) {
      if (node.path == path) return node;
    }
    return null;
  }

  /// Every existing place that could hold a child without breaching the cap.
  ///
  /// Filtered rather than validated: a parent that cannot legally take a child is not a choice the
  /// user should be able to make and then be told off for.
  List<LocationNode> get _parentOptions =>
      locationTree.where((LocationNode n) => n.depth + 2 <= _maxDepth).toList();

  /// The path this location will have, shown while it is still being decided.
  ///
  /// **The empty-name placeholder is an instruction, not a name.** It read "Yeni konum", which is
  /// the page title verbatim, so with nothing typed the line repeated the heading instead of
  /// previewing anything. "Depo › adı yazın" reads as a slot waiting to be filled, which is what
  /// it is.
  String get _preview {
    final String own = _name.trim().isEmpty ? Lang.get('screens.location_form.name_pending') : _name.trim();
    return _parentPath == null ? own : '$_parentPath › $own';
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: Lang.get('screens.location_form.title'),
      subtitle: Lang.get('screens.location_form.subtitle'),
      backLabel: Lang.get('screens.location_form.back'),
      backFallback: '/locations',
      footer: _buildFooter(),
      children: [
        _buildIdentity(),
        _buildParent(),
      ],
    );
  }

  Widget _buildIdentity() {
    return SectionCard(
      label: Lang.get('screens.location_form.identity_group'),
      children: [
        WDiv(
          className: 'flex flex-col gap-1.5',
          children: [
            WText(Lang.get('screens.location_form.name'), className: 'text-sm font-medium text-fg'),
            MSInput(
              className: 'bg-surface-container',
              placeholder: Lang.get('screens.location_form.name_placeholder'),
              onChanged: (String next) => setState(() => _name = next),
            ),
          ],
        ),
        _buildIconPicker(),
        _buildColourPicker(),
      ],
    );
  }

  /// The sixteen glyphs, each drawn in the hue currently chosen.
  ///
  /// **Tinting them with `_colour` is what ties the two pickers together.** They set one thing
  /// between them, the mark that will stand for this place in the tree, and two independent rows
  /// of swatches would make the user assemble that combination in their head. Here the icon row
  /// IS the preview, and the colour row only says which tint it is wearing.
  Widget _buildIconPicker() {
    return WDiv(
      className: 'flex flex-col gap-1.5',
      children: [
        WText(Lang.get('screens.location_form.icon'), className: 'text-sm font-medium text-fg'),
        WDiv(
          // Sixteen tiles will not fit a phone width, and the count is fixed rather than variable,
          // so this wraps rather than scrolls: a horizontal scroller hides options behind a gesture
          // that nothing on screen advertises.
          className: 'flex flex-row wrap items-center gap-2',
          children: [
            for (final String name in locationIcons.keys)
              WAnchor(
                onTap: () => setState(() => _icon = name),
                semanticLabel: Lang.get('screens.location_form.icon_pick', {
                  'name': Lang.get('screens.location_form.icons.$name'),
                }),
                // Card tone plus a hairline for the unselected state, and the brand fill only for
                // the chosen one. A tinted fill alone would carry selection by colour, and
                // DESIGN.md's rule applies to state as much as to status.
                child: WDiv(
                  className: name == _icon
                      ? 'size-11 rounded-md flex items-center justify-center bg-primary-container border border-color-border'
                      : 'size-11 rounded-md flex items-center justify-center bg-surface-container border border-color-border',
                  child: WIcon(
                    locationIcons[name]!,
                    className: 'size-5 ${locationGlyphClassName(_colour)}',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The seven hues, as plain filled swatches.
  ///
  /// **No glyph inside them, deliberately.** The icon row above is already showing the chosen
  /// glyph in the chosen hue, so repeating it seven times here would put two marks in a 44pt box
  /// for no new information, which is the crowding DESIGN.md warns about for a list row. The tick
  /// is the exception, and it is the one thing that has to be there: selection carried by tint
  /// alone is invisible to a colour-blind user, so the chosen swatch says so with a shape.
  ///
  /// `text-on-primary` for that tick rather than a per-hue foreground, because these fills follow
  /// the same brightness rule the primary does: dark in light mode, bright in dark. One alias that
  /// flips with the appearance therefore lands correctly on all seven.
  Widget _buildColourPicker() {
    return WDiv(
      className: 'flex flex-col gap-1.5',
      children: [
        WText(Lang.get('screens.location_form.colour'), className: 'text-sm font-medium text-fg'),
        WDiv(
          className: 'flex flex-row wrap items-center gap-2',
          children: [
            for (final String hue in locationColours)
              WAnchor(
                onTap: () => setState(() => _colour = hue),
                semanticLabel: Lang.get('screens.location_form.colour_pick', {
                  'name': Lang.get('screens.location_form.colours.$hue'),
                }),
                child: WDiv(
                  className:
                      'size-11 rounded-md flex items-center justify-center '
                      '${locationSwatchClassName(hue)} border border-color-border',
                  child: hue == _colour
                      ? const WIcon(_selectedIcon, className: 'size-5 text-on-primary')
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Where it sits, and what that costs in depth.
  Widget _buildParent() {
    return SectionCard(
      label: Lang.get('screens.location_form.parent_group'),
      count: Lang.get('screens.location_form.depth', {'depth': _depth, 'max': _maxDepth}),
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2',
          children: [
            ChoiceChip(
              label: Lang.get('screens.location_form.parent_none'),
              isSuggested: _parentPath == null,
              semanticLabel: Lang.get('screens.location_form.parent_none'),
              onTap: () => setState(() => _parentPath = null),
            ),
            for (final LocationNode node in _parentOptions)
              ChoiceChip(
                label: node.path,
                isSuggested: _parentPath == node.path,
                semanticLabel: node.path,
                onTap: () => setState(() => _parentPath = node.path),
              ),
          ],
        ),
        // The resulting path, spelled out. A tree is easy to get wrong from a chip row, and this
        // is the one line that says exactly what will be created.
        WText(_preview, className: 'text-sm font-medium text-fg'),
        WText(
          Lang.get('screens.location_form.depth_note', {'max': _maxDepth}),
          className: 'text-xs text-fg-muted',
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        MSButton(
          onPressed: _isValid ? () {} : null,
          disabled: !_isValid,
          intent: _isValid ? ButtonIntent.primary : ButtonIntent.secondary,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.location_form.save')),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.location_form.template')),
        ),
      ],
    );
  }
}
