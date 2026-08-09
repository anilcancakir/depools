import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'location_row.dart';

/// Static variant-matrix preview for [LocationRow].
///
/// A tree at every depth the schema allows, plus an empty shelf. Two things to check:
/// that the indent still reads as nesting at depth 5 without eating a phone's width, and
/// that an empty location recedes without disappearing, since it is still a valid
/// destination for a stock-in.
///
/// The deepest chain is deliberately absurd. Real users will not nest six levels, but the
/// schema permits it, and a layout that only works to depth 2 fails silently on the one
/// tenant who does.
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
              icon: Icons.kitchen_outlined,
            onTap: _noop),
            LocationRow(
              name: 'Buzdolabı',
              depth: 1,
              productCount: 3,
              itemSummary: '3 ürün',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Derin dondurucu',
              depth: 1,
              productCount: 1,
              itemSummary: '1 ürün',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Kiler',
              depth: 0,
              productCount: 4,
              itemSummary: '4 ürün · 3 alt konum',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Raf 1',
              depth: 1,
              productCount: 1,
              itemSummary: '1 ürün',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Raf 2',
              depth: 1,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Çekmece 2',
              depth: 1,
              productCount: 1,
              itemSummary: '1 ürün',
              icon: Icons.shelves,
            onTap: _noop),
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
              icon: Icons.warehouse_outlined,
            onTap: _noop),
            LocationRow(
              name: 'Koridor B',
              depth: 1,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Raf A',
              depth: 2,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Kutu 3',
              depth: 3,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Bölme 1',
              depth: 4,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Göz 2',
              depth: 5,
              productCount: 2,
              itemSummary: '2 ürün',
              icon: Icons.shelves,
            onTap: _noop),
            LocationRow(
              name: 'Raf B',
              depth: 1,
              productCount: 0,
              itemSummary: 'Boş',
              icon: Icons.shelves,
            onTap: _noop),
          ],
        ),
      ],
    );
  }
}
