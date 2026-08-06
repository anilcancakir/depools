import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/product_filter.dart';
import 'filter_bar.dart';

/// Live preview for [FilterBar].
///
/// Stateful, unlike most previews here, because the whole component is a mode
/// switch and a static render can only ever show one side of it. Tap "Süresi
/// geçenler" and the row has to become a single applied chip carrying that NAME;
/// tap the × and the saved list has to come back. That round trip is the thing to
/// check, and a screenshot of either end proves nothing about the transition.
///
/// The third bar is the ad-hoc case: a filter nobody saved, shown as its parts,
/// with "Kaydet" offered. Note the second bar (an exact saved match) does not offer
/// "Kaydet", which is deliberate.
class FilterBarPreview extends StatefulWidget {
  /// Creates the FilterBar preview.
  const FilterBarPreview({super.key});

  @override
  State<FilterBarPreview> createState() => _FilterBarPreviewState();
}

class _FilterBarPreviewState extends State<FilterBarPreview> {
  ProductFilter _live = const ProductFilter();

  static const ProductFilter _adHoc = ProductFilter(
    query: 'süt',
    locationIds: {'loc-fridge'},
    stockState: StockStateFilter.belowPar,
  );

  static String? _resolveLocation(String id) =>
      const {'loc-fridge': 'Buzdolabı', 'loc-pantry': 'Kiler'}[id];

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            WText('Canlı: bir chip\'e dokun, mod değişsin', className: 'text-xs text-fg-muted'),
            FilterBar(
              filter: _live,
              saved: SavedProductFilter.builtIns,
              resolveLocation: _resolveLocation,
              onChanged: (next) => setState(() => _live = next),
              onSave: () {},
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            WText(
              'Kayıtlı filtre uygulanmış: adıyla görünür, Kaydet yok',
              className: 'text-xs text-fg-muted',
            ),
            FilterBar(
              filter: SavedProductFilter.builtIns.first.filter,
              saved: SavedProductFilter.builtIns,
              onChanged: (_) {},
              onSave: () {},
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-2',
          children: [
            WText(
              'Ad-hoc filtre: parçaları görünür, Kaydet önerilir',
              className: 'text-xs text-fg-muted',
            ),
            FilterBar(
              filter: _adHoc,
              saved: SavedProductFilter.builtIns,
              resolveLocation: _resolveLocation,
              onChanged: (_) {},
              onSave: () {},
            ),
          ],
        ),
      ],
    );
  }
}
