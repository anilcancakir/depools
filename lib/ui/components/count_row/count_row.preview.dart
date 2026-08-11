import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'count_row.dart';

/// Static variant-matrix preview for [CountRow].
///
/// Four rows plus the placeholder: uncounted, counted and matching, counted and short, counted as
/// zero, and the skeleton the sheet shows while the balances are on their way.
///
/// The one to look at is the last pair. **Uncounted and zero are different facts** and they
/// must not look alike: the empty field carries a dash rather than a nought, because an
/// uncounted row is left untouched at commit while a zero writes the whole balance off. A count
/// sheet whose empty field meant zero would zero out every product the user did not reach.
///
/// The second row also shows the two-field case: a product with a content level is counted as
/// whole units PLUS an opened amount, never as one decimal.
class CountRowPreview extends StatelessWidget {
  /// Creates the CountRow preview.
  const CountRowPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [
            CountRow(name: 'Yoğurt 2 kg', unit: 'adet', verdict: 'Sayılmadı'),
            CountRow(
              name: 'Pınar Süt Tam Yağlı 1 lt',
              unit: 'adet',
              remainderUnit: 'ml',
              counted: '1',
              countedRemainder: '0',
              verdict: 'Sistemde 1 adet + 500 ml · 500 ml eksik',
              state: CountState.variance,
            ),
            CountRow(
              name: 'Kaşar Peyniri 500 g',
              unit: 'adet',
              counted: '1',
              verdict: 'Eşleşti · sistemde 1 adet',
              state: CountState.matched,
            ),
            CountRow(
              name: 'Ayçiçek Yağı 5 lt',
              unit: 'adet',
              counted: '0',
              verdict: 'Sistemde 2 adet · 2 adet eksik',
              state: CountState.variance,
            ),
          ],
        ),
        // The placeholder, in its own card so its geometry can be compared against the rows above
        // rather than read on its own. The two have to line up: the whole reason the skeleton is
        // this component rather than a bar list is that the sheet must not jump when content lands.
        WDiv(
          className: 'flex flex-col gap-1 p-4 rounded-lg bg-surface-container',
          children: [CountRow.skeleton(), CountRow.skeleton()],
        ),
      ],
    );
  }
}
