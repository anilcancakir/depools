import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'movement_row.dart';

/// Static variant-matrix preview for [MovementRow].
///
/// A mixed history on purpose: purchase, consumption, waste and a correction in one
/// list, because that mix is what the ledger actually holds and what waste
/// reporting is computed from. If waste does not read differently from ordinary
/// consumption here, the UI is implying a distinction the data does make.
class MovementRowPreview extends StatelessWidget {
  /// Creates the MovementRow preview.
  const MovementRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Pınar Süt Tam Yağlı 1 lt', className: 'text-base font-semibold text-fg'),
            WText('Son hareketler', className: 'text-xs text-fg-muted'),
            MovementRow(
              reason: 'Satın alındı',
              deltaAmount: 3,
              delta: '+3',
              unit: 'adet',
              meta: 'Fiş taraması · 5 Ağu 18:22',
              direction: MovementDirection.inbound,
            ),
            MovementRow(
              reason: 'Tüketildi',
              deltaAmount: -1,
              delta: '-1',
              unit: 'adet',
              meta: 'Anılcan · bugün 09:14',
              direction: MovementDirection.outbound,
            ),
            MovementRow(
              reason: 'Zayi: bozuldu',
              deltaAmount: -1,
              delta: '-1',
              unit: 'adet',
              meta: 'Anılcan · bugün 09:15',
              direction: MovementDirection.waste,
            ),
            MovementRow(
              reason: 'Sayım düzeltmesi',
              deltaAmount: -0.5,
              delta: '-0,5',
              unit: 'kg',
              meta: 'Asistan onaylı · dün 21:40',
              direction: MovementDirection.correction,
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Uzun etiket ve büyük miktar', className: 'text-base font-semibold text-fg'),
            MovementRow(
              reason: 'Tedarikçiden alındı, e-Fatura ile eşleşti',
              deltaAmount: 1240.00,
              delta: '+1.240,00',
              unit: 'kg',
              meta: 'Yudum Gıda · e-Fatura FT2026-88421 · 1 Ağu 11:05',
              direction: MovementDirection.inbound,
            ),
          ],
        ),
      ],
    );
  }
}
