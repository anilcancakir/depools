import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'draft_field.dart';

/// Static variant-matrix preview for [DraftField].
///
/// The three states side by side, which is the whole review: a user has to be able to
/// tell "still loading" from "the model gave up" from "this is a value", at a glance
/// and without reading. If loading and unsure look alike the card lies about whether
/// anything more is coming; if unsure and filled look alike the model's silence goes
/// unnoticed.
///
/// The fourth group is [DraftField.unconfirmed], which is orthogonal to the states: an
/// inferred value is filled and provisional at once. Compare it against the plain
/// filled field above; if the "tahmin" marker is not visible at a glance, a wrongly
/// inferred unit will sail through and change what every quantity means.
class DraftFieldPreview extends StatelessWidget {
  /// A tear-off rather than a closure, so every `const` in this file survives.
  ///
  /// The callbacks are here at all because a control previewed WITHOUT one is a dead
  /// control: `WAnchor` withholds the pointer cursor when it has no gesture, so the
  /// catalog showed no hand on hover and it was reported as a missing cursor in code
  /// that works. Eleven previews had this.
  static void _noop() {}

  /// Creates the DraftField preview.
  const DraftFieldPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Üç durum', className: 'text-xs text-fg-muted'),
            DraftField(label: 'Marka', state: DraftFieldState.loading, onTap: _noop),
            DraftField(label: 'SKU', state: DraftFieldState.unsure, onTap: _noop),
            DraftField(label: 'Kategori', value: 'Süt ürünleri', onTap: _noop),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Doğrulanmadı: dolu ama geçici', className: 'text-xs text-fg-muted'),
            DraftField(label: 'Birim', value: 'adet', unconfirmed: true, onTap: _noop),
            DraftField(label: 'İçerik', value: '1000 ml', unconfirmed: true, onTap: _noop),
            DraftField(label: 'Raf ömrü', value: '5 gün', unconfirmed: true, onTap: _noop),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            WText('Kendi metniyle boş durum', className: 'text-xs text-fg-muted'),
            DraftField(
              label: 'Açıklama',
              state: DraftFieldState.unsure,
              prompt: 'Fotoğraftan okunamadı',
            onTap: _noop),
            DraftField(label: 'Barkod', state: DraftFieldState.unsure, prompt: 'Barkod okutulmadı', onTap: _noop),
          ],
        ),
      ],
    );
  }
}
