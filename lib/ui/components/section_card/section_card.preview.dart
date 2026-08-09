import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSButton, ButtonIntent, ButtonSize;

import '../product_row/product_row.dart';
import 'section_card.dart';

/// Static variant-matrix preview for [SectionCard].
///
/// Four cards covering what can break independently: plain, collapsible open,
/// collapsible closed, and collapsible carrying a trailing action as well.
///
/// The closed card is the one worth looking at. A collapsed section has to keep
/// showing its count, because a closed section with no count is indistinguishable
/// from an empty one, and its chevron has to point the other way. Tap either
/// collapsible header here to check both directions.
///
/// The last card is the crowded case: an action AND a chevron on one row. If the
/// chevron pushes "Tümü" off the row, or the two overlap, the header's trailing
/// slot is wrong.
class SectionCardPreview extends StatelessWidget {
  /// A tear-off rather than a closure, so the const expressions in this file survive.
  static void _noop() {}

  /// Creates the SectionCard preview.
  const SectionCardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        const SectionCard(
          label: 'Tüm ürünler',
          count: '42 ürün',
          children: [
            ProductRow(
              name: 'Ayçiçek Yağı 5 lt',
              meta: 'Yudum · Kiler › Raf 2',
              amount: 2,
              formatted: '2',
              unit: 'adet',
            ),
            ProductRow(
              name: 'Un',
              meta: 'Söke · Kiler › Raf 1',
              amount: 12.5,
              formatted: '12,50',
              unit: 'kg',
            ),
          ],
        ),
        const SectionCard(
          label: 'Dikkat gerekiyor',
          count: '3 ürün',
          collapsible: true,
          children: [
            ProductRow(
              name: 'Pınar Süt Tam Yağlı 1 lt',
              meta: 'Pınar · Buzdolabı, Kiler',
              amount: 5,
              formatted: '5',
              unit: 'adet',
              expiryLabel: 'Süresi geçti',
              daysUntilExpiry: -1,
            ),
            ProductRow(
              name: 'Bulgur',
              meta: 'Duru · Çekmece 2',
              amount: 0.8,
              formatted: '0,80',
              unit: 'kg',
              expiryLabel: '2 gün',
              daysUntilExpiry: 2,
            ),
          ],
        ),
        const SectionCard(
          label: 'Kapalı başlar',
          count: '18 ürün',
          collapsible: true,
          initiallyExpanded: false,
          children: [
            ProductRow(name: 'Kapalıyken görünmemeli', amount: 1, formatted: '1', unit: 'adet'),
          ],
        ),
        SectionCard(
          label: 'Aksiyon ve chevron',
          count: '9 kayıt',
          collapsible: true,
          action: MSButton(
            onPressed: () {},
            intent: ButtonIntent.ghost,
            size: ButtonSize.sm,
            className: 'min-h-11 axis-min',
            child: const WDiv(
              className: 'flex flex-row items-center gap-0.5 axis-min',
              children: [
                WText('Tümü'),
                WIcon(Icons.chevron_right_outlined, className: 'size-4'),
              ],
            ),
          ),
          children: const [
            ProductRow(
              name: 'Un',
              meta: 'Söke · Kiler › Raf 1',
              amount: 12.5,
              formatted: '12,50',
              unit: 'kg',
            ),
          ],
        ),
        // The failure state, which is the whole point of the `error` parameter: the section is
        // replaced in place and the page around it keeps working.
        SectionCard(
          label: 'Tarihler',
          count: '5 parti',
          error: 'Tarihler yüklenemedi',
          onRetry: _noop,
          children: const [],
        ),
        // The same failure with nothing to retry, which is what a permanent one looks like.
        SectionCard(
          label: 'Alışveriş listesi',
          error: 'Liste yüklenemedi',
          children: const [],
        ),
      ],
    );
  }
}
