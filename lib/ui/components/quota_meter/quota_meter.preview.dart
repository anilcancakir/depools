import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'quota_meter.dart';

/// Every position a meter can be in, including the two that are easy to forget.
///
/// The unmetered case draws no bar, and the over-limit case draws a full one rather than
/// overflowing its track. Both are states a plan screen will really render.
@immutable
class QuotaMeterPreview extends StatelessWidget {
  /// Creates the [QuotaMeterPreview].
  const QuotaMeterPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-4 w-full max-w-md',
      children: const [
        QuotaMeter(
          label: 'Ürün sayısı',
          used: 34,
          limit: 100,
          value: '34 / 100 ürün',
          note: 'Limitte yeni ürün eklenemez, mevcutlar çalışmaya devam eder.',
        ),
        QuotaMeter(
          label: 'AI kredisi',
          used: 86,
          limit: 100,
          value: '86 / 100 kredi',
          note: 'Bittiğinde fiş okuma ve fotoğraftan tanıma durur, elle giriş etkilenmez.',
        ),
        QuotaMeter(
          label: 'Ürün sayısı',
          used: 50,
          limit: 50,
          value: '50 / 50 ürün',
          note: 'Limit doldu. Yeni ürün eklemek için plan yükseltilmeli.',
        ),
        QuotaMeter(
          label: 'Geçmiş',
          used: 0,
          value: 'Sınırsız',
          note: 'Tüm hareket geçmişi sorgulanabilir.',
        ),
      ],
    );
  }
}
