import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'scan_row.dart';

/// Static variant-matrix preview for [ScanRow].
///
/// All five sources, plus the two cases that only show up in a real batch: a product the
/// tenant HAS but has run out of (`Mevcut: 0 adet`, which is the most useful thing a scan
/// can tell you), and a barcode scanned six times that stayed one row.
///
/// Two things to check here. The left edge must be dead straight down all six rows: the
/// glyph column is fixed-width precisely so a row with a different icon does not shift its
/// own name, and this component exists in a codebase where that mistake was made twice.
/// And the barcodes must line up digit under digit, because the whole reason they render
/// in mono is so they can be compared against a label by eye.
class ScanRowPreview extends StatelessWidget {
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
            ),
            ScanRow(
              barcode: '8691234567890',
              productName: 'Tornavida Seti PH2',
              count: 1,
              onHandFormatted: '0',
            ),
            ScanRow(
              barcode: '8690632073415',
              productName: 'Sütaş Ayran 250 ml',
              source: ScanSource.catalog,
              count: 4,
            ),
            ScanRow(
              barcode: '6941487206643',
              productName: 'Powerbank 10000 mAh',
              source: ScanSource.unverified,
              count: 2,
            ),
            ScanRow(
              barcode: '8680000998877',
              productName: 'Kablo bağı 200 mm',
              source: ScanSource.recalled,
              count: 1,
            ),
            ScanRow(barcode: '8680000123456', source: ScanSource.unmatched, count: 1),
          ],
        ),
      ],
    );
  }
}
