import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSCard, CardVariant, MSTypography, TypographyVariant;

/// Welcome view: the default landing page for a new Magic application.
///
/// Design-first: colors flow through the semantic alias tokens so the screen
/// tracks DESIGN.md in light and dark. Kept as a self-contained centered shell
/// (it is the pre-auth landing, rendered outside the app layout).
class WelcomeView extends StatelessWidget {
  /// Creates the [WelcomeView].
  const WelcomeView({super.key});

  static const _iconHero = Icons.auto_awesome;
  static const _iconDocs = Icons.menu_book;
  static const _iconGitHub = Icons.code;
  static const _iconCli = Icons.terminal;
  static const _iconArrow = Icons.arrow_forward_outlined;
  static const _iconHeart = Icons.favorite;

  @override
  Widget build(BuildContext context) {
    final appName = Config.get('app.name', '') ?? '';

    return WDiv(
      className: 'bg-surface min-h-screen w-full',
      child: SingleChildScrollView(
        child: WDiv(
          className: 'w-full max-w-[480px] mx-auto p-4 lg:p-8',
          child: WDiv(
            className: '''
              rounded-2xl bg-surface-container
              border border-color-border
              p-6 lg:p-8 flex flex-col items-center
            ''',
            children: [
              // 1. Hero.
              WDiv(
                className: '''
                  w-20 h-20 rounded-2xl
                  flex items-center justify-center
                  bg-primary
                ''',
                child: const WIcon(_iconHero, className: 'text-on-primary text-4xl'),
              ),
              const WSpacer(className: 'h-6'),
              MSTypography(appName, variant: TypographyVariant.h2, className: 'text-center'),
              const WSpacer(className: 'h-2'),
              const MSTypography('Built with Magic Framework', variant: TypographyVariant.caption),

              const WSpacer(className: 'h-8'),

              // 2. Quick-link cards.
              WDiv(
                className: 'w-full flex flex-col gap-3',
                children: [
                  _buildLinkCard(
                    icon: _iconDocs,
                    title: 'Documentation',
                    description: 'Read the Magic Framework docs to get started.',
                    url: 'https://magic.fluttersdk.com',
                  ),
                  _buildLinkCard(
                    icon: _iconGitHub,
                    title: 'GitHub',
                    description: 'Star the repo, report issues, or contribute code.',
                    url: 'https://github.com/fluttersdk/magic',
                  ),
                  _buildLinkCard(
                    icon: _iconCli,
                    title: 'CLI Commands',
                    description: 'Run `magic --help` to see all available commands.',
                    url: 'https://magic.fluttersdk.com/packages/magic-cli',
                  ),
                ],
              ),

              const WSpacer(className: 'h-8'),

              // 3. Footer.
              WDiv(
                className: 'flex flex-row items-center justify-center gap-1',
                children: [
                  const WText('Made with', className: 'text-xs text-fg-muted'),
                  const WIcon(_iconHeart, className: 'text-xs text-destructive'),
                  const WText('by', className: 'text-xs text-fg-muted'),
                  WAnchor(
                    onTap: () => Launch.url('https://anilcancakir.com'),
                    child: const WText('Anılcan Çakır', className: 'text-xs font-medium text-fg'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a single quick-link tile composing the shared [MSCard] component.
  Widget _buildLinkCard({
    required IconData icon,
    required String title,
    required String description,
    required String url,
  }) {
    return MSCard(
      variant: CardVariant.inset,
      child: WDiv(
        className: 'flex flex-col',
        children: [
          WDiv(
            className: 'flex flex-row items-center gap-3 mb-2',
            children: [
              WDiv(
                className: 'p-2 rounded-lg bg-primary-container',
                child: WIcon(icon, className: 'text-lg text-fg'),
              ),
              WText(title, className: 'text-base font-semibold text-fg'),
            ],
          ),
          WText(description, className: 'text-sm text-fg-muted mb-3'),
          WAnchor(
            onTap: () => Launch.url(url),
            child: WDiv(
              className: 'flex flex-row items-center gap-1',
              children: [
                const WText('Learn more', className: 'text-sm font-medium text-fg'),
                const WIcon(_iconArrow, className: 'text-sm text-fg'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
