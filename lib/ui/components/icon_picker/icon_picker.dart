import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSInput;

import '../../../app/support/icon_catalogue.dart';
import '../app_icon/app_icon.dart';
import 'icon_picker.recipe.dart';

/// **IconPicker**
///
/// Search the icon catalogue and pick one, returning the chosen NAME.
///
/// The name is what a column stores, so a caller hands one in and gets one back; nothing here
/// exposes the svg. `locations.icon` is the first caller, and a product category is the plausible
/// second.
///
/// **It searches the server rather than filtering a bundled list**, because there is no bundled
/// list: 4,185 icons as `const IconData` would cost +1.81 MB, measured on this app. What it gains
/// beyond size is the search itself, since each icon carries a median of 34 tags, so `fridge`
/// reaches `kitchen` and `storage` reaches `shelves`.
///
/// **An empty query is a real state, not a blank screen.** The endpoint answers the popular end of
/// the catalogue when nothing is typed, so the picker opens showing something to choose.
///
/// ### Example
///
/// ```dart
/// IconPicker(selected: 'kitchen', onSelected: (String name) => setState(() => _icon = name))
/// ```
@immutable
class IconPicker extends StatefulWidget {
  /// The name currently chosen, if any.
  final String? selected;

  /// Called with the chosen icon's name.
  final ValueChanged<String> onSelected;

  /// Placeholder for the search field, already localised.
  final String searchPlaceholder;

  /// What to say while a search is running, already localised.
  final String searchingLabel;

  /// What to say when a query matches nothing, already localised.
  final String emptyLabel;

  /// Where the results come from. The container's singleton unless a caller says otherwise.
  ///
  /// **The seam exists for the preview catalog**, which has to render this without a server. A
  /// preview firing a real search would show whatever the developer's backend is doing, and would
  /// show nothing at all on a machine with no API running.
  final IconCatalogue? catalogue;

  /// Creates an [IconPicker].
  const IconPicker({
    super.key,
    required this.onSelected,
    required this.searchPlaceholder,
    required this.searchingLabel,
    required this.emptyLabel,
    this.selected,
    this.catalogue,
  });

  @override
  State<IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<IconPicker> {
  /// How long to wait after the last keystroke before asking the server.
  ///
  /// Every keystroke is a request without it, and a user typing `warehouse` would fire nine. Long
  /// enough to collapse a word, short enough that the grid feels like it is following along.
  static const Duration _debounce = Duration(milliseconds: 250);

  List<CatalogueIcon> _results = const <CatalogueIcon>[];
  bool _searching = true;
  Timer? _timer;

  /// Which query the visible results belong to, so a slow answer cannot overwrite a newer one.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    final int request = ++_requestId;

    setState(() => _searching = true);

    final IconCatalogue catalogue = widget.catalogue ?? Magic.make<IconCatalogue>('icons');
    final List<CatalogueIcon> icons = await catalogue.search(query);

    // A newer query started while this one was in flight, so this answer is stale by definition.
    // Dropped rather than shown: it is the result of something the user has already typed past.
    if (!mounted || request != _requestId) return;

    setState(() {
      _results = icons;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> slots = iconPickerRecipe()(variants: {});

    return WDiv(
      className: slots['root'],
      children: [
        MSInput(
          className: 'bg-surface-container',
          placeholder: widget.searchPlaceholder,
          onChanged: _onChanged,
        ),
        if (_results.isEmpty)
          WText(
            _searching ? widget.searchingLabel : widget.emptyLabel,
            className: slots['status'],
          )
        else
          WDiv(
            className: slots['grid'],
            children: [
              for (final CatalogueIcon icon in _results) _tile(icon),
            ],
          ),
      ],
    );
  }

  /// One icon in the grid.
  ///
  /// The glyph goes through [AppIcon] like everywhere else rather than rendering the svg directly,
  /// so the search result and the row it will become are drawn by the same code. The catalogue has
  /// already held everything a search returned, so this draws on the first frame with no fetch.
  Widget _tile(CatalogueIcon icon) {
    final Map<String, String> slots = iconPickerRecipe()(
      variants: {'state': icon.name == widget.selected ? 'selected' : 'idle'},
    );

    return WAnchor(
      onTap: () => widget.onSelected(icon.name),
      // The catalogue's own title, which is why the endpoint carries it: `Local shipping` is what a
      // screen reader should say, not `local_shipping`.
      semanticLabel: icon.title,
      child: WDiv(
        className: slots['tile'],
        child: AppIcon(
          name: icon.name,
          className: slots['glyph']!,
          catalogue: widget.catalogue,
        ),
      ),
    );
  }
}
