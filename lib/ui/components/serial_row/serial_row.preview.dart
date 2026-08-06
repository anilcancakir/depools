import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'serial_row.dart';

/// Static variant-matrix preview for [SerialRow].
///
/// Five units covering what varies: a warranty comfortably in the future, one inside
/// its warning window, one already expired, one with no warranty at all, and one that
/// has left the building.
///
/// The thing to check is the serial column. These are read aloud and typed back in, so
/// if they do not line up character for character down the left edge, the mono is not
/// resolving and the component has lost the reason it renders them that way.
class SerialRowPreview extends StatelessWidget {
  /// Creates the SerialRow preview.
  const SerialRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            SerialRow(
              serial: 'MK-DHP484-002391',
              warrantyLabel: '14 gün',
              warrantyDaysRemaining: 14,
              receivedLabel: '12 Şub alındı · Depo › Raf A',
            ),
            SerialRow(
              serial: 'MK-DHP484-002392',
              warrantyLabel: '2 gün',
              warrantyDaysRemaining: 2,
              receivedLabel: '12 Şub alındı · Depo › Raf A',
            ),
            SerialRow(
              serial: 'MK-DHP484-001044',
              warrantyLabel: 'Garanti bitti',
              warrantyDaysRemaining: -1,
              receivedLabel: '3 Mar 2024 alındı · Depo › Raf A',
            ),
            SerialRow(serial: 'ASSET-0091', receivedLabel: 'garanti kaydı yok · Depo › Raf A'),
            SerialRow(
              serial: 'MK-DHP484-000817',
              warrantyLabel: 'Garanti bitti',
              warrantyDaysRemaining: -400,
              receivedLabel: 'satıldı · 8 Tem',
              isGone: true,
            ),
          ],
        ),
      ],
    );
  }
}
