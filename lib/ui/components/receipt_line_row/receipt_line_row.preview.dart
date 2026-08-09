import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'receipt_line_row.dart';

/// Static variant-matrix preview for [ReceiptLineRow].
///
/// The four resolution states in one card, in the proportion a real receipt has them:
/// mostly settled, a couple needing the user, one dropped. That proportion is the review:
/// if the settled rows carry as much visual weight as the unresolved ones, a user with
/// twenty-two lines cannot see the two that need them.
///
/// The extracted strings are real Turkish thermal-receipt truncations. "ORG KEM TAV" is
/// the case the doc names as the hard one, and it is here unresolved on purpose.
class ReceiptLineRowPreview extends StatelessWidget {
  /// A tear-off rather than a closure, so every `const` in this file survives.
  ///
  /// The callbacks are here at all because a control previewed WITHOUT one is a dead
  /// control: `WAnchor` withholds the pointer cursor when it has no gesture, so the
  /// catalog showed no hand on hover and it was reported as a missing cursor in code
  /// that works. Eleven previews had this.
  static void _noop() {}

  /// Creates the ReceiptLineRow preview.
  const ReceiptLineRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            ReceiptLineRow(
              extracted: 'PNR SUT 1LT',
              productName: 'Pınar Süt Tam Yağlı 1 lt',
              amount: 2,
              formatted: '2',
              unit: 'adet',
              price: '69,80 TL',
              locationLabel: 'Mutfak › Buzdolabı',
            onTap: _noop),
            ReceiptLineRow(
              extracted: 'DURU BULGUR 1K',
              productName: 'Bulgur',
              amount: 1,
              formatted: '1',
              unit: 'kg',
              price: '42,50 TL',
              locationLabel: 'Kiler › Çekmece 2',
            onTap: _noop),
            ReceiptLineRow(
              extracted: 'ORG KEM TAV',
              resolution: LineResolution.unresolved,
              amount: 1.2,
              formatted: '1,20',
              unit: 'kg',
              price: '184,00 TL',
            onTap: _noop),
            ReceiptLineRow(
              extracted: 'ZYT YAG 5LT TARIS',
              productName: 'Tariş Zeytinyağı 5 lt',
              resolution: LineResolution.created,
              amount: 1,
              formatted: '1',
              unit: 'adet',
              price: '1.240,00 TL',
              locationLabel: 'Kiler › Raf 2',
            onTap: _noop),
            ReceiptLineRow(
              extracted: 'POSET',
              resolution: LineResolution.rejected,
              amount: 1,
              formatted: '1',
              unit: 'adet',
              price: '0,50 TL',
            onTap: _noop),
          ],
        ),
      ],
    );
  }
}
