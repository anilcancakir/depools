import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSButton, ButtonIntent, ButtonSize;

import 'section_header.dart';

/// Static variant-matrix preview for [SectionHeader].
///
/// The third row is the one worth looking at: the count sits with the label on the
/// left and the action is a real button on the right, with its own 44px hit target.
/// An earlier version put both on the right and used bare text for the action, which
/// crowded them into looking like one element and produced something that read as a
/// link and did nothing.
class SectionHeaderPreview extends StatelessWidget {
  /// Creates the SectionHeader preview.
  const SectionHeaderPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        const SectionHeader(label: 'Partiler'),
        const SectionHeader(label: 'Konumlar', count: '2 konum'),
        SectionHeader(
          label: 'Hareketler',
          count: '9 kayıt',
          action: MSButton(
            onPressed: () {},
            intent: ButtonIntent.ghost,
            size: ButtonSize.sm,
            child: const WText('Tümü'),
          ),
        ),
        WDiv(
          className: 'flex flex-col gap-2 p-3 rounded-lg bg-surface-container',
          children: [
            const SectionHeader(label: 'Partiler', count: '3 parti'),
            WText(
              'Bir bölüm başlığı gerçek içeriğin üstünde böyle durur.',
              className: 'text-sm text-fg',
            ),
          ],
        ),
      ],
    );
  }
}
