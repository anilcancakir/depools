import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'scan_row.dart';

/// Static variant-matrix preview for [ScanRow].
///
/// All five sources plus the pending state, and the two cases that only show up in a real
/// batch: a product the tenant HAS but has run out of (`Mevcut: 0 adet`, which is the most
/// useful thing a scan can tell you), and a barcode scanned six times that stayed one row.
///
/// Two things to check here. The left edge must be dead straight down all seven rows: the
/// glyph column is fixed-width precisely so a row with a different icon does not shift its
/// own name, and this component exists in a codebase where that mistake was made twice.
/// And the barcodes must line up digit under digit, because the whole reason they render
/// in mono is so they can be compared against a label by eye.
class ScanRowPreview extends StatelessWidget {
  /// A tear-off rather than a closure, so every `const` in this file survives.
  ///
  /// The callbacks are here at all because a control previewed WITHOUT one is a dead
  /// control: `WAnchor` withholds the pointer cursor when it has no gesture, so the
  /// catalog showed no hand on hover and it was reported as a missing cursor in code
  /// that works. Eleven previews had this.
  static void _noop() {}

  /// Creates the ScanRow preview.
  const ScanRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            ScanRow(
              barcode: '8690504004073',
              productName: 'Pınar Süt Tam Yağlı 1 lt',
              count: 6,
              onHandFormatted: '2',
            onTap: _noop),
            ScanRow(
              barcode: '8691234567890',
              productName: 'Tornavida Seti PH2',
              count: 1,
              onHandFormatted: '0',
            onTap: _noop),
            ScanRow(
              barcode: '8690632073415',
              productName: 'Sütaş Ayran 250 ml',
              source: ScanSource.catalog,
              count: 4,
            onTap: _noop),
            ScanRow(
              barcode: '6941487206643',
              productName: 'Powerbank 10000 mAh',
              source: ScanSource.unverified,
              count: 2,
            onTap: _noop),
            ScanRow(
              barcode: '8680000998877',
              productName: 'Kablo bağı 200 mm',
              source: ScanSource.recalled,
              count: 1,
            onTap: _noop),
            ScanRow(barcode: '8680000123456', source: ScanSource.unmatched, count: 1, onTap: _noop),
            // **No `onTap`, and that is the state rather than an omission.** A row whose answer is
            // still arriving has no card worth opening, and the view passes null for the same reason.
            // The count still renders, because a repeat read while the lookup is out is a real second
            // carton.
            ScanRow(barcode: '4011200296908', count: 2, pending: true),
          ],
        ),
      ],
    );
  }
}
