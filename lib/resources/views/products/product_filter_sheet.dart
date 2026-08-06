import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSBottomSheet, MSButton, MSSegmentedControl, ButtonIntent;

import '../../../app/models/product_filter.dart';
import '../../../ui/components/filter_chip/filter_chip.dart';

/// One selectable value on a multi-select axis.
///
/// [label] is what the chip says and [id] is what the filter stores. A location's
/// label carries its path ("Kiler › Raf 2") because two shelves called "Raf 2" in
/// different rooms are otherwise indistinguishable in a flat chip row.
@immutable
class FilterOption {
  /// The stored value.
  final String id;

  /// The already-localised chip label. Short, because it sits in a capsule.
  final String label;

  /// The full hierarchy path, when this option is a location.
  ///
  /// A chip wants "Buzdolabı" and a detail row wants "Mutfak › Buzdolabı": the short
  /// name fits a capsule in a scrolling row, and the path answers "where exactly" on
  /// a screen that has the width for it. Deriving one from the other loses either the
  /// context or the space, so a location carries both. Defaults to [label].
  final String? path;

  /// Creates a [FilterOption].
  const FilterOption({required this.id, required this.label, this.path});

  /// The path when one is declared, otherwise the label.
  String get fullPath => path ?? label;
}

/// The filter sheet for the stock list.
///
/// **A sheet rather than tokens in the search field.** Tokens look like the
/// Apple-native answer and are not at this axis count: HIG's own guidance on them
/// carries the caveat that "people may not know which tokens are available", and its
/// illustration of search in a bottom toolbar puts a separate Filter button beside
/// the field. Nine axes including a location hierarchy is what a filter control is
/// for. The reasoning and the citation live in
/// `docs/depools-system/features/filtering-and-saved-views.md`.
///
/// **Batch apply, not live.** Every change edits a draft, and the footer button
/// applies it. Filtering live as each chip toggles reflows the list behind the sheet
/// on every tap, which on a phone means the user loses their place while still
/// choosing. The footer says how many products the draft matches, so the user knows
/// what they are about to get before they commit to it.
///
/// **Multi-select axes are chips, not checkbox lists.** It reuses [FilterChip] in
/// its applied state, so "selected" looks identical here and in the row under the
/// search field: the same tinted capsule means the same thing in both places.
class ProductFilterSheet extends StatefulWidget {
  /// The filter the sheet opens on.
  final ProductFilter initial;

  /// Location options, deepest paths included, ordered as the tree reads.
  final List<FilterOption> locations;

  /// Category options.
  final List<FilterOption> categories;

  /// Tag options. Tags are their own value, so id and label match.
  final List<FilterOption> tags;

  /// Counts the products a draft filter would match, for the footer button.
  ///
  /// Passed in rather than computed here: the sheet does not own the catalogue, and
  /// a count computed from a different source than the list would eventually
  /// disagree with it.
  final int Function(ProductFilter draft) countMatches;

  /// Creates a [ProductFilterSheet].
  const ProductFilterSheet({
    super.key,
    required this.initial,
    required this.countMatches,
    this.locations = const [],
    this.categories = const [],
    this.tags = const [],
  });

  /// Opens the sheet and resolves with the applied filter, or null if dismissed.
  ///
  /// Null means "changed nothing", which is different from an empty filter
  /// ("cleared everything"), so a caller must not coalesce the two.
  static Future<ProductFilter?> show(
    BuildContext context, {
    required ProductFilter initial,
    required int Function(ProductFilter draft) countMatches,
    List<FilterOption> locations = const [],
    List<FilterOption> categories = const [],
    List<FilterOption> tags = const [],
  }) {
    return MSBottomSheet.show<ProductFilter>(
      context,
      title: 'Filtrele',
      body: ProductFilterSheet(
        initial: initial,
        countMatches: countMatches,
        locations: locations,
        categories: categories,
        tags: tags,
      ),
    );
  }

  @override
  State<ProductFilterSheet> createState() => _ProductFilterSheetState();
}

class _ProductFilterSheetState extends State<ProductFilterSheet> {
  late ProductFilter _draft = widget.initial;

  static const List<StockStateFilter> _stockStates = StockStateFilter.values;
  static const List<ExpiryFilter> _expiries = ExpiryFilter.values;

  void _set(ProductFilter next) => setState(() => _draft = next);

  /// Toggles one value on a multi-select axis.
  Set<String> _toggled(Set<String> current, String id) {
    return current.contains(id)
        ? current.where((String v) => v != id).toSet()
        : <String>{...current, id};
  }

  @override
  Widget build(BuildContext context) {
    final int matches = widget.countMatches(_draft);

    return WDiv(
      className: 'flex flex-col gap-5',
      children: [
        _group(
          'Stok durumu',
          MSSegmentedControl<StockStateFilter>(
            options: _stockStates.map(ProductFilter.stockStateLabel).toList(),
            selectedIndex: _stockStates.indexOf(_draft.stockState),
            onChanged: (index) => _set(_draft.copyWith(stockState: _stockStates[index])),
          ),
        ),
        // "Son kullanma" carries no day count, because the window is derived per
        // product from its shelf life: milk warns a day out, a tin two months out.
        // A segment saying "7 gün" would be a promise the filter no longer makes.
        _group(
          'Son kullanma',
          MSSegmentedControl<ExpiryFilter>(
            options: _expiries.map(ProductFilter.expirySegmentLabel).toList(),
            selectedIndex: _expiries.indexOf(_draft.expiry),
            onChanged: (index) => _set(_draft.copyWith(expiry: _expiries[index])),
          ),
        ),
        if (widget.locations.isNotEmpty)
          _chipGroup(
            'Konum',
            widget.locations,
            _draft.locationIds,
            (id) => _set(_draft.copyWith(locationIds: _toggled(_draft.locationIds, id))),
          ),
        if (widget.categories.isNotEmpty)
          _chipGroup(
            'Kategori',
            widget.categories,
            _draft.categoryIds,
            (id) => _set(_draft.copyWith(categoryIds: _toggled(_draft.categoryIds, id))),
          ),
        if (widget.tags.isNotEmpty)
          _chipGroup(
            'Etiket',
            widget.tags,
            _draft.tags,
            (id) => _set(_draft.copyWith(tags: _toggled(_draft.tags, id))),
          ),

        // The apply pair. "Sıfırla" clears the draft in place rather than closing,
        // so a user who over-filtered can start again without reopening the sheet.
        WDiv(
          className: 'flex flex-col gap-2 pt-2',
          children: [
            MSButton(
              onPressed: () => Navigator.of(context).pop(_draft),
              fullWidth: true,
              className: 'justify-center',
              // The count, not "Uygula". A user about to filter a 42-product list
              // down to nothing should see that before they lose the list, not after.
              child: WText('$matches ürün göster'),
            ),
            MSButton(
              onPressed: () => _set(const ProductFilter()),
              // `disabled` as well as a null callback. MSButton takes them as separate
              // inputs and does NOT infer the look from the callback, so a null
              // onPressed alone blocks the tap while leaving the button looking
              // actionable, which is worse than either state on its own.
              disabled: _draft.isEmpty,
              intent: ButtonIntent.ghost,
              fullWidth: true,
              className: 'justify-center',
              child: const WText('Sıfırla'),
            ),
          ],
        ),
      ],
    );
  }

  /// A labelled group wrapping one control.
  Widget _group(String label, Widget control) {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        WText(label, className: 'text-xs font-medium uppercase tracking-wide text-fg-muted'),
        control,
      ],
    );
  }

  /// A labelled group of toggleable chips.
  ///
  /// The chips wrap rather than scroll here, unlike the row under the search field.
  /// A sheet can afford the height, and a scrolling row inside a scrolling sheet
  /// hides options behind a gesture the user has no reason to try.
  Widget _chipGroup(
    String label,
    List<FilterOption> options,
    Set<String> selected,
    void Function(String id) onToggle,
  ) {
    return _group(
      label,
      WDiv(
        className: 'flex flex-row wrap gap-2',
        children: [
          for (final FilterOption option in options)
            FilterChip(
              label: option.label,
              applied: selected.contains(option.id),
              onTap: () => onToggle(option.id),
            ),
        ],
      ),
    );
  }
}
