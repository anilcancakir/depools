import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show ButtonIntent, MSButton, MSInput;

import '../../../app/support/icon_catalogue.dart';
import '../../../app/support/location_appearance.dart';
import '../../../ui/components/choice_chip/choice_chip.dart';
import '../../../ui/components/icon_picker/icon_picker.dart';
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
  /// Nothing chosen yet, which is the honest state of a form the user just opened.
  ///
  /// It used to default to the first of sixteen, which quietly put a house on any location the user
  /// did not think about. `locations.icon` is nullable precisely so "not said" is expressible.
  String? _icon;
  String _colour = locationFallbackColour;

  /// Whether the glyph on screen was chosen for the user rather than by them.
  ///
  /// Drives the note beside the icon label, and nothing else: a value is a value however it arrived.
  bool _iconIsAutomatic = false;

  /// Set the moment the user opens the picker and taps, and never unset.
  ///
  /// **A suggestion is a DEFAULT and it stops the instant there is an answer.** Without this, typing
  /// after choosing an icon would quietly replace the choice, which is the one thing an automatic
  /// value must never do.
  bool _iconIsUserChosen = false;

  /// The name the last suggestion was asked about, so the same text is never paid for twice.
  ///
  /// A model call spends one of the tenant's AI credits, and a form is edited in bursts: without
  /// this, adding and deleting one character would buy the same answer again.
  String? _suggestedFor;

  /// What that name suggested, so typing back to it restores the glyph rather than paying again.
  ///
  /// Null is a real answer here and it is kept as one: a name the model was unsure of stays unsure,
  /// and re-deriving it would spend a credit to be told the same thing.
  String? _suggestedIcon;

  /// Whether a suggestion is in flight, for the note beside the icon label.
  bool _isSuggesting = false;

  /// The debounce, cancelled on every keystroke and on dispose.
  Timer? _suggestTimer;

  @override
  void dispose() {
    _suggestTimer?.cancel();
    super.dispose();
  }

  bool get _isValid => _name.trim().isNotEmpty;

  /// Called on every keystroke in the name field.
  ///
  /// **700ms, which is a pause rather than a gap between letters.** Shorter and a two-word name
  /// buys two answers; longer and the glyph lands after the user has moved on to the parent picker.
  void _onNameChanged(String next) {
    setState(() {
      _name = next;

      // **A derived value does not outlive what it was derived from.** Without this the glyph from
      // the previous name stayed on screen under a note claiming it came from the current one, and
      // it stayed there for good when the next suggestion answered null: the form would then SAVE
      // a picture chosen for a name the user had typed over.
      //
      // Cleared on the keystroke rather than when the replacement lands, because the window between
      // them is a second of the screen saying something untrue.
      if (_iconIsAutomatic) {
        _icon = null;
        _iconIsAutomatic = false;
      }
    });

    _suggestTimer?.cancel();

    if (_iconIsUserChosen) return;

    _suggestTimer = Timer(const Duration(milliseconds: 700), _suggest);
  }

  /// Ask the catalogue what this name looks like, and take the answer only if it still applies.
  ///
  /// **Everything is re-checked AFTER the await, not only before it.** The request is roughly 600ms
  /// against a live provider, which is long enough for the user to tap an icon, clear the field or
  /// leave the screen, and a response that landed on any of those would overwrite an answer with a
  /// guess. The name is compared as well as the flags, because a slow response for "Depo" must not
  /// paint a warehouse on a field that now reads "Buzdolabı".
  Future<void> _suggest() async {
    final String name = _name.trim();

    if (name.isEmpty || _iconIsUserChosen) return;

    // Typed back to a name already asked about: re-apply what it answered instead of buying it
    // again. Reached whenever an edit is undone, which the clear above made ordinary rather than
    // rare, since deleting a character and putting it back now goes through here.
    if (name == _suggestedFor) {
      final String? held = _suggestedIcon;

      if (held != null) {
        setState(() {
          _icon = held;
          _iconIsAutomatic = true;
        });
      }

      return;
    }

    _suggestedFor = name;
    _suggestedIcon = null;

    setState(() => _isSuggesting = true);

    // `'icons'` is the container key `AppServiceProvider` registers, and it is a SINGLETON: the
    // suggestion it holds is the same instance the picker and the tree read, so the glyph draws
    // without a second request.
    final CatalogueIcon? icon = await Magic.make<IconCatalogue>('icons').suggest(name);

    if (!mounted) return;

    setState(() {
      _isSuggesting = false;

      // Null is ordinary: the model unsure of the name, no credit, the kill switch, or a word the
      // catalogue does not have. The neutral icon and the picker were already the answer.
      if (icon == null || _iconIsUserChosen || _name.trim() != name) return;

      _icon = icon.name;
      _iconIsAutomatic = true;
      _suggestedIcon = icon.name;
    });
  }

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
              onChanged: _onNameChanged,
            ),
          ],
        ),
        _buildIconPicker(),
        _buildColourPicker(),
      ],
    );
  }

  /// The catalogue, searched.
  ///
  /// **This was sixteen tiles of our own choosing, and it is 4,185 searchable ones now.** A curated
  /// row is easy to build and impossible to find a shelf in: the user who keeps stock in a van, a
  /// basement or a chest freezer was offered a box. The picker searches the `icons` table, where
  /// each icon carries a median of 34 tags, so `fridge` reaches `kitchen` and `storage` reaches
  /// `shelves` without the user knowing Material's naming.
  ///
  /// The glyphs are NOT tinted with the chosen hue here, which the sixteen-tile version did. That
  /// tied the two pickers together so the user saw the combination they were assembling, and it
  /// stops working over a grid the user is scanning for a SHAPE: fifty red glyphs read as one
  /// texture. The colour row below still shows the hue on its own, and the tree shows the pair.
  Widget _buildIconPicker() {
    return WDiv(
      className: 'flex flex-col gap-1.5',
      children: [
        WText(Lang.get('screens.location_form.icon'), className: 'text-sm font-medium text-fg'),
        // **Above the grid, not below it.** Measured at 390x844: fifty tiles at six per row put
        // anything under the picker well past the fold, so a note explaining the glyph that is
        // already highlighted at the top would only ever be read on a desktop.
        ?_buildIconNote(),
        IconPicker(
          selected: _icon,
          onSelected: (String name) => setState(() {
            _icon = name;
            _iconIsUserChosen = true;
            _iconIsAutomatic = false;
          }),
          searchPlaceholder: Lang.get('screens.location_form.icon_search'),
          searchingLabel: Lang.get('screens.location_form.icon_searching'),
          emptyLabel: Lang.get('screens.location_form.icon_empty'),
        ),
      ],
    );
  }

  /// One line saying where the glyph came from, or nothing.
  ///
  /// **The note is what makes an automatic value honest.** A glyph that simply appears reads as a
  /// value the user set and forgot, so they stop looking at it; saying it was chosen for them is
  /// what turns it into a default they can disagree with. `text-ai` because DESIGN.md gives that
  /// family to anything the app inferred, and borrowing another status colour would make a hint read
  /// as a warning.
  Widget? _buildIconNote() {
    if (_isSuggesting) {
      return WText(
        Lang.get('screens.location_form.icon_suggesting'),
        className: 'text-xs text-fg-muted',
      );
    }

    if (!_iconIsAutomatic) return null;

    return WText(
      Lang.get('screens.location_form.icon_auto'),
      className: 'text-xs text-ai',
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
