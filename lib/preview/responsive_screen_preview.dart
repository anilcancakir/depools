import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// A screen at both of its widths, in one preview.
///
/// ### Why this replaced a second file per screen
///
/// The first attempt at phone verification added a `*PhoneScreenPreview` beside every existing
/// screen preview: eleven new files whose only difference from their neighbour was one `chrome:`
/// argument. That is duplication dressed as coverage, and Anılcan named it: the components are
/// responsive, so the WIDTH is a variant of one preview rather than a reason for two.
///
/// It also contradicted the project's own contract. `.claude/rules/design.md` requires ONE preview
/// widget rendering every variant and state combination, precisely so a reviewer sees the whole
/// range in one place and a divergence between two of them is visible rather than a file away.
/// Splitting by width broke that for screens while components kept it.
///
/// ### Both, stacked, and the wide one first
///
/// The wide arrangement is what the catalog pane shows natively and what most review happens
/// against, so it leads. The 390px frame follows, and it is a FIXED frame rather than a narrowed
/// viewport because the catalog keeps its sidebar at every width: narrowing the window squeezes the
/// harness, not the screen, which is how a "400px" measurement once produced a confident wrong
/// answer.
///
/// The phone frame is also the only place the shell's app bar and bottom nav are mounted, which is
/// what exposed a composer falling behind the nav and a blank dashboard behind a layout assertion.
@immutable
class ResponsiveScreenPreview extends StatelessWidget {
  /// Which mock state the harness installs.
  final PreviewState state;

  /// The view under test, built once per width.
  final WidgetBuilder builder;

  /// Whether the wide half needs a bounded height.
  ///
  /// **Only a screen that fills the viewport needs this, and only the assistant does.** Most screens
  /// are a scrolling column and are happy with the unbounded height the catalog pane gives them. A
  /// chat window is the opposite shape: its composer sits at the bottom of the VIEWPORT and its
  /// transcript takes what is left, which is an `Expanded` and therefore needs a height to divide.
  ///
  /// The real app supplies that height because the assistant route renders outside the app shell.
  /// The catalog pane does not, so without this the wide half asserts on an unbounded height while
  /// the phone frame, which is bounded, renders correctly.
  final bool bounded;

  /// Creates a [ResponsiveScreenPreview].
  const ResponsiveScreenPreview({
    super.key,
    required this.builder,
    this.state = PreviewState.success,
    this.bounded = false,
  });

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 w-full',
      children: <Widget>[
        _labelled(
          'Geniş',
          bounded
              ? SizedBox(height: 720, child: ScreenPreviewScaffold(state: state, builder: builder))
              : ScreenPreviewScaffold(state: state, builder: builder),
        ),
        _labelled(
          'Telefon · 390px',
          ScreenPreviewScaffold(
            state: state,
            chrome: PreviewChrome.appMobile,
            builder: builder,
          ),
        ),
      ],
    );
  }

  /// One width, named, so a screenshot of the pair says which is which.
  Widget _labelled(String label, Widget child) {
    return WDiv(
      className: 'flex flex-col gap-2 w-full',
      children: <Widget>[
        WText(label, className: 'text-xs font-medium uppercase tracking-wide text-fg-muted'),
        child,
      ],
    );
  }
}
