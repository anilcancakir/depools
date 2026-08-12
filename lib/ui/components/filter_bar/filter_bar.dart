import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSButton, ButtonIntent, ButtonSize;

import '../../../app/models/product_filter.dart';
import '../filter_chip/filter_chip.dart';
import 'filter_bar.recipe.dart';

/// **FilterBar**
///
/// The row of chips under the stock list's search field. It has two modes and never
/// shows both at once:
///
/// - **Nothing applied**: the saved filters, as quick-access chips.
/// - **Something applied**: what is in force, each chip removable, plus "Temizle"
///   and, for an unsaved filter, "Kaydet".
///
/// **The modes are exclusive on purpose.** A row that mixes saved filters with
/// active criteria under one visual treatment leaves the user unable to tell what
/// is narrowing the list from what is merely on offer, which is the taxonomy
/// failure documented in `features/filtering-and-saved-views.md`. Switching mode is
/// also the clearest possible signal that a filter took effect.
///
/// **An applied filter that matches a saved one shows the saved NAME**, not its
/// decomposed criteria: "Süresi geçenler" is what the user chose and what they will
/// look for to turn it off. Only an ad-hoc filter built in the sheet is shown as
/// its parts. [SavedProductFilter.filter] equality is what decides, so a saved
/// filter the user then narrowed further correctly falls back to criteria chips.
@immutable
class FilterBar extends StatelessWidget {
  /// What is currently narrowing the list.
  final ProductFilter filter;

  /// The saved filters to offer, built-ins first.
  final List<SavedProductFilter> saved;

  /// Called with a replacement filter whenever a chip changes it.
  ///
  /// One callback for every mutation rather than one per gesture: removing a
  /// criterion, applying a saved filter and clearing everything all produce a new
  /// [ProductFilter], and the caller only ever needs to store it.
  final ValueChanged<ProductFilter> onChanged;

  /// Called when the user asks to save the current filter. Null hides "Kaydet".
  final VoidCallback? onSave;

  /// Resolves a location id to its name for a chip label.
  final String? Function(String id)? resolveLocation;

  /// Resolves a category id to its name for a chip label.
  final String? Function(String id)? resolveCategory;

  /// Creates a [FilterBar].
  const FilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.saved = const [],
    this.onSave,
    this.resolveLocation,
    this.resolveCategory,
  });

  /// The saved filter the current filter is exactly, if any.
  SavedProductFilter? get _appliedSaved {
    for (final SavedProductFilter candidate in saved) {
      if (candidate.filter == filter) return candidate;
    }
    return null;
  }

  /// Whether [item]'s constraints are already part of the current filter.
  ///
  /// Merging it changes nothing when they are, so the chip would be inert. Tested by merging rather
  /// than by comparing axis to axis: the question is exactly "would tapping this do anything", and
  /// `mergedWith` is the thing that would happen.
  bool _isApplied(SavedProductFilter item) => filter.mergedWith(item.filter) == filter;

  @override
  Widget build(BuildContext context) {
    final slots = filterBarRecipe()();

    if (filter.isEmpty) {
      // Nothing to show and nothing on offer: render no row at all rather than an
      // empty 44pt strip. A tenant with no saved filters is the first-run case.
      if (saved.isEmpty) return const WDiv(className: 'hidden');

      return WDiv(
        className: slots['scroller'],
        children: [
          for (final SavedProductFilter item in saved)
            FilterChip(label: item.name, onTap: () => onChanged(item.filter)),
        ],
      );
    }

    final SavedProductFilter? applied = _appliedSaved;

    return WDiv(
      className: slots['scroller'],
      children: [
        if (applied != null)
          FilterChip(
            label: applied.name,
            applied: true,
            onTap: () => onChanged(const ProductFilter()),
          )
        else
          for (final FilterCriterion criterion in filter.criteria(
            resolveLocation: resolveLocation,
            resolveCategory: resolveCategory,
          ))
            FilterChip(
              label: criterion.label,
              applied: true,
              onTap: () => onChanged(criterion.remainder),
            ),

        // **The offers stay on screen, which they did not before.** This mode used to render only
        // what was in force, so applying one built-in hid the other three: switching from "Expired"
        // to "Low stock" cost a tap to clear, a moment with the list unfiltered, and a second tap.
        // The X on an applied chip promises that a filter is one tap away from being undone, and the
        // row now keeps the same promise for adding one.
        //
        // Merged rather than replaced, so a cross-axis pair narrows (expired AND low stock is a real
        // question with real rows behind it) while a same-axis one overwrites, which is the only
        // thing a single-valued axis can mean.
        //
        // Whichever is applied is filtered OUT of the offers rather than shown inert: it is already
        // on the row to its left, with an X on it.
        for (final SavedProductFilter item in saved)
          if (!_isApplied(item))
            FilterChip(label: item.name, onTap: () => onChanged(filter.mergedWith(item.filter))),

        // "Kaydet" only for an ad-hoc filter. Offering it on an already-saved one
        // invites a second copy of the same criteria under a different name, which
        // is how a short saved list turns into an untrustworthy long one.
        //
        // **`py-3.5`, not `min-h-11`, and the difference is visible.** Both reach the 44pt
        // target; only one keeps the label centred. `min-h-11` grows the box DOWNWARD without
        // re-centring its child, so the text sat above centre and stopped lining up with the
        // chips beside it. Anılcan spotted it in the row. Padding grows both edges.
        //
        // `3.5` rather than `3` because these are `sm` buttons: 14 + 14 + a 16px `text-xs`
        // line is 44, where `py-3` would land at 40 and quietly miss the target the token was
        // there to hold. The anti-pattern table's `py-3` assumes the `md` size.
        if (applied == null && onSave != null)
          MSButton(
            onPressed: onSave,
            intent: ButtonIntent.ghost,
            size: ButtonSize.sm,
            className: 'py-3.5 axis-min',
            child: WText(Lang.get('components.filter_bar.save'), className: slots['textAction']),
          ),

        MSButton(
          onPressed: () => onChanged(const ProductFilter()),
          intent: ButtonIntent.ghost,
          size: ButtonSize.sm,
          className: 'py-3.5 axis-min',
          child: WText(Lang.get('components.filter_bar.clear'), className: slots['textAction']),
        ),
      ],
    );
  }
}
