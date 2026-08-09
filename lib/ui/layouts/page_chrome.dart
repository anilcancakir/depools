import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

/// Carries the pinned footer a page wants, from inside the shell's scroll to outside it.
///
/// ### Why a scope and a host instead of a Column
///
/// The obvious way to pin a footer is `Column(children: [Expanded(scroll), footer])`, and it
/// cannot be done from a page in this app. `magic_starter`'s shell puts every route inside
/// `WDiv(className: 'flex-1 overflow-y-auto')`, so a page is handed UNBOUNDED height: an
/// `Expanded` there fails as `RenderBox was not laid out`, which names nothing.
///
/// What does work is what the assistant launcher already proved: wrap OUTSIDE
/// `layout.app`, where the box is the window and a `Stack` can anchor to the viewport. So the
/// footer travels up rather than being laid out in place. The page declares it, this scope
/// carries it, and [PageChromeHost] draws it over the shell.
///
/// The alternative was a `footer:` slot on `MSPageScaffold` itself, which is the better home and
/// is a PR in another repository plus a publish cycle. The call site here is deliberately the
/// same shape (`footer:`), so adopting the upstream version later deletes this file and changes
/// nothing else.
class PageChrome extends InheritedNotifier<ValueNotifier<Widget?>> {
  /// Creates a [PageChrome] carrying [notifier] to its subtree.
  const PageChrome({super.key, required ValueNotifier<Widget?> notifier, required super.child})
    : super(notifier: notifier);

  /// The nearest chrome slot, or null outside a [PageChromeHost].
  ///
  /// Null is a legitimate answer rather than an error: the preview catalog renders screens with
  /// no shell around them, and a screen that cannot pin its footer there should still build.
  static ValueNotifier<Widget?>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageChrome>()?.notifier;
}

/// Draws the current page's pinned footer over the app shell.
///
/// Mounted in `routes/app.dart` outside `layout.app`, for the reason [PageChrome] explains.
///
/// The bottom inset clears the navigation bar and whatever the device puts under it, using the
/// same arithmetic the assistant launcher uses. A footer that overlapped a 44pt tab target would
/// steal taps from it, and on a phone the bottom edge is exactly where a thumb rests.
class PageChromeHost extends StatefulWidget {
  /// The shell this draws over.
  final Widget child;

  /// Creates a [PageChromeHost] wrapping [child].
  const PageChromeHost({super.key, required this.child});

  @override
  State<PageChromeHost> createState() => _PageChromeHostState();
}

class _PageChromeHostState extends State<PageChromeHost> {
  final ValueNotifier<Widget?> _footer = ValueNotifier<Widget?>(null);
  final GlobalKey _footerKey = GlobalKey();

  double _footerHeight = 0;

  @override
  void dispose() {
    _footer.dispose();
    super.dispose();
  }

  /// Measures the footer after it lays out, so everything else can clear it.
  ///
  /// **The measurement is what keeps the floating assistant button off the footer.** Both are
  /// anchored to the viewport, and the button's inset is a constant, so a footer taller than that
  /// constant lands underneath it. Rather than teach the button about footers, the height is
  /// folded into `MediaQuery.padding.bottom` for the whole subtree: the button already reads that
  /// padding to clear the navigation bar, so it lifts by exactly the right amount and needs to
  /// know nothing.
  ///
  /// A guessed constant was the alternative and it is wrong by construction: this footer is two
  /// lines of summary plus two buttons on one screen and a single button on another.
  void _measure() {
    final RenderObject? box = _footerKey.currentContext?.findRenderObject();
    final double next = box is RenderBox && box.hasSize ? box.size.height : 0;
    if ((next - _footerHeight).abs() < 0.5) return;
    if (mounted) setState(() => _footerHeight = next);
  }

  @override
  Widget build(BuildContext context) {
    return PageChrome(
      notifier: _footer,
      child: ValueListenableBuilder<Widget?>(
        valueListenable: _footer,
        builder: (BuildContext context, Widget? footer, Widget? _) {
          if (footer == null) {
            // Reset, or the next page keeps clearing a footer that is no longer there.
            if (_footerHeight != 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _footerHeight = 0);
              });
            }
            return widget.child;
          }

          WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

          final MediaQueryData media = MediaQuery.of(context);

          return Stack(
            children: <Widget>[
              MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    bottom: media.padding.bottom + _footerHeight,
                  ),
                ),
                child: widget.child,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 64,
                // The `Material` is the same one the assistant overlay needed, for the same
                // reason: this draws OUTSIDE `layout.app`, which is what was providing the
                // ancestor every `Text` under a `MaterialApp` resolves its style from. Without
                // it the whole footer renders in Flutter's yellow double-underlined fallback,
                // which looks like a theme bug and is not one.
                //
                // The fill and the hairline are what separate it from the content sliding
                // underneath. Without them the footer reads as a row that happens to be there
                // rather than as chrome, and the list scrolls through it illegibly.
                child: Material(
                  type: MaterialType.transparency,
                  child: WDiv(
                    key: _footerKey,
                    className: 'w-full bg-surface border-t border-color-border px-4 py-3',
                    child: footer,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
