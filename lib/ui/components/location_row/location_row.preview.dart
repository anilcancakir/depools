import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'location_row.dart';

/// Static variant-matrix preview for [LocationRow].
///
/// A tree at every depth the schema allows, an empty shelf, and every hue a location can carry.
/// Three things to check:
///
/// - the indent still reads as nesting at depth 5 without eating a phone's width;
/// - an empty location recedes without disappearing, since it is still a valid destination for a
///   stock-in;
/// - each hue is distinguishable from its neighbours in BOTH appearances, and the untinted row at
///   the end still reads as a place rather than as a broken one.
///
/// The deepest chain is deliberately absurd. Real users will not nest six levels, but the schema
/// permits it, and a layout that only works to depth 2 fails silently on the one tenant who does.
class LocationRowPreview extends StatelessWidget {
  /// A tear-off rather than a closure, so every `const` in this file survives.
  ///
  /// The callbacks are here at all because a control previewed WITHOUT one is a dead
  /// control: `WAnchor` withholds the pointer cursor when it has no gesture, so the
  /// catalog showed no hand on hover and it was reported as a missing cursor in code
  /// that works. Eleven previews had this.
  static void _noop() {}

  /// Creates the LocationRow preview.
  const LocationRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Gerçek bir ev', className: 'text-xs text-fg-muted'),
            LocationRow(
              name: 'Mutfak',
              depth: 0,
              productCount: 5,
              itemSummary: '5 ürün · 2 alt konum',
              icon: 'kitchen',
              colour: 'red',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Buzdolabı',
              depth: 1,
              productCount: 3,
              itemSummary: '3 ürün',
              icon: 'fridge',
              colour: 'blue',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Derin dondurucu',
              depth: 1,
              productCount: 1,
              itemSummary: '1 ürün',
              icon: 'freezer',
              colour: 'teal',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Kiler',
              depth: 0,
              productCount: 4,
              itemSummary: '4 ürün · 3 alt konum',
              icon: 'pantry',
              colour: 'amber',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Raf 1',
              depth: 1,
              productCount: 1,
              itemSummary: '1 ürün',
              icon: 'shelf',
              colour: 'green',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Çekmece 2',
              depth: 1,
              productCount: 1,
              itemSummary: '1 ürün',
              icon: 'drawer',
              onTap: _noop,
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Boş bir raf ve derin yuvalama', className: 'text-xs text-fg-muted'),
            LocationRow(
              name: 'Depo',
              depth: 0,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: 'warehouse',
              colour: 'violet',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Koridor B',
              depth: 1,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: 'shelf',
              colour: 'violet',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Raf A',
              depth: 2,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: 'shelf',
              colour: 'violet',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Kutu 3',
              depth: 3,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: 'box',
              colour: 'violet',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Bölme 1',
              depth: 4,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: 'crate',
              colour: 'violet',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Göz 2',
              depth: 5,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: 'drawer',
              colour: 'violet',
              onTap: _noop,
            ),
            LocationRow(
              name: 'Raf B',
              depth: 1,
              productCount: 0,
              itemSummary: 'Boş',
              icon: 'shelf',
              colour: 'violet',
              onTap: _noop,
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            // The last row carries no hue at all, which is not a filler case: both appearance
            // columns are nullable, so this is what every location looks like the day before
            // anybody opens the form.
            WText('Yedi renk ve renksiz', className: 'text-xs text-fg-muted'),
            LocationRow(name: 'Gri', depth: 0, productCount: 1, icon: 'home', colour: 'slate', onTap: _noop),
            LocationRow(name: 'Mavi', depth: 0, productCount: 1, icon: 'fridge', colour: 'blue', onTap: _noop),
            LocationRow(name: 'Turkuaz', depth: 0, productCount: 1, icon: 'freezer', colour: 'teal', onTap: _noop),
            LocationRow(name: 'Yeşil', depth: 0, productCount: 1, icon: 'shelf', colour: 'green', onTap: _noop),
            LocationRow(name: 'Sarı', depth: 0, productCount: 1, icon: 'pantry', colour: 'amber', onTap: _noop),
            LocationRow(name: 'Kırmızı', depth: 0, productCount: 1, icon: 'basket', colour: 'red', onTap: _noop),
            LocationRow(name: 'Mor', depth: 0, productCount: 1, icon: 'warehouse', colour: 'violet', onTap: _noop),
            LocationRow(name: 'Renksiz', depth: 0, productCount: 1, onTap: _noop),
          ],
        ),
      ],
    );
  }
}
