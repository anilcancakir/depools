import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSButton, ButtonIntent, ButtonSize, MSSkeleton, SkeletonShape;

import 'list_footer.recipe.dart';

/// How a paginated list ends.
enum ListFooterState {
  /// A page is in flight. Skeleton rows stand in for what is arriving.
  loadingMore,

  /// Everything is loaded.
  end,

  /// The next page failed. Retryable, and the loaded rows stay.
  error,
}

/// **ListFooter**
///
/// The bottom of a paginated list, in one of three states.
///
/// **They must not look alike.** A list that silently stops paying out is
/// indistinguishable from one that finished, so the user cannot tell whether to keep
/// scrolling, and a failed page that shows nothing looks like the end of the data. This is
/// the same class of problem as an invisible active filter: the screen is short and does
/// not say why.
///
/// **Pagination is cursor-based, not offset.** In an inventory app stock changes while the
/// user scrolls, and an offset page skips or repeats rows the moment anything above the
/// window moves. A cursor on the sort key is stable under insertion.
///
/// **The URL carries the search and the filter, not the cursor.** A filtered list is worth
/// addressing and sharing; a scroll position is not. Reloading returns to the top of the
/// same filtered list, which is what a user expects from a link.
///
/// The skeleton count matches the page size, so the space the incoming rows will occupy is
/// the space reserved for them and the list does not jump when they land.
@immutable
class ListFooter extends StatelessWidget {
  /// Which state to render.
  final ListFooterState state;

  /// How many skeleton rows to show while a page is in flight.
  final int pageSize;

  /// The already-formatted total, shown when the list has ended.
  final String? totalLabel;

  /// Called when the user retries a failed page.
  final VoidCallback? onRetry;

  /// One placeholder in the shape of the rows this list holds, repeated [pageSize] times.
  ///
  /// **The caller supplies it because only the caller knows the shape.** This component used to
  /// draw flat text bars while its own comment claimed they were "the shape of what is coming":
  /// the intention was written down and never delivered, and a stack of equal bars under a list
  /// of thumbnails and figures says nothing about what is arriving. Pass
  /// `ProductRow.skeleton()` and the placeholder is drawn by the same component as the content,
  /// so it cannot drift.
  final Widget? skeleton;

  /// Creates a [ListFooter].
  const ListFooter({
    super.key,
    required this.state,
    this.pageSize = 3,
    this.totalLabel,
    this.onRetry,
    this.skeleton,
  });

  @override
  Widget build(BuildContext context) {
    final slots = listFooterRecipe()();

    return WDiv(
      className: slots['root'],
      children: [
        switch (state) {
          // Skeleton ROWS, not a spinner, and they have to be the ROW's shape: the list keeps
          // its rhythm and nothing jumps when the page lands. Falls back to a bar only when the
          // caller gave no shape, which is a caller worth fixing rather than a case to design
          // for.
          ListFooterState.loadingMore => WDiv(
            className: 'flex flex-col w-full',
            children: [
              for (int i = 0; i < pageSize; i++)
                skeleton ?? const MSSkeleton(shape: SkeletonShape.text, height: 16),
            ],
          ),
          ListFooterState.end => WText(totalLabel ?? 'Hepsi yüklendi', className: slots['text']),
          ListFooterState.error => WDiv(
            className: 'flex flex-col items-center gap-2',
            children: [
              // Says what failed and what is intact. "Yüklenemedi" alone would leave the
              // user unsure whether the rows above are trustworthy.
              WText('Sonraki sayfa yüklenemedi', className: slots['error']),
              WText('Yüklenen satırlar yerinde', className: slots['text']),
              MSButton(
                onPressed: onRetry,
                intent: ButtonIntent.secondary,
                size: ButtonSize.sm,
                className: 'py-2 axis-min',
                child: const WText('Tekrar dene'),
              ),
            ],
          ),
        },
      ],
    );
  }
}
