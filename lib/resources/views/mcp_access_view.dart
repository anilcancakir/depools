import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show ButtonIntent, ConfirmDialogVariant, MSButton, MSEmptyState, MagicStarterConfirmDialog;

import '../../ui/components/callout/callout.dart';
import '../../ui/components/section_card/section_card.dart';
import '../../ui/layouts/app_page_scaffold.dart';

/// Connecting the user's own assistant to their own inventory.
///
/// ### Why a screen and not a config file
///
/// `mcp-server.md` puts a read-only MCP server in v1, behind OAuth. Without a surface here, the
/// feature could ship and nobody could use it: there would be no way to see the address, to
/// authorise a client, or to take that authorisation back. Of the eleven feature documents this
/// was the only one with no mockup at all.
///
/// ### Revoking is the primary affordance, not an afterthought
///
/// What the user is doing on this screen is handing a third-party program a key to their stock
/// records. `mcp-server.md` inherits `data-model.md`'s tenancy rule verbatim, and the incident it
/// cites is Asana's 2025 MCP leak across roughly a thousand organisations, which went unnoticed for
/// over a month. The lesson a UI can carry is that every connection is listed, with when it was
/// last used, and one control removes it. A key you cannot see is a key you cannot take back.
///
/// ### It says read-only, plainly
///
/// v1 exposes five read tools and no writes (`iterations.md`), and a user connecting an assistant
/// will reasonably assume it can act. Saying so is not a disclaimer, it is the accurate description
/// of what they are about to grant, and it is what makes granting it comfortable.
@immutable
class McpAccessView extends StatelessWidget {
  static const IconData _emptyIcon = Icons.link_off_outlined;
  static const IconData _copyIcon = Icons.content_copy_outlined;
  static const IconData _revokeIcon = Icons.link_off_outlined;

  /// Whether any client is connected, which is the first-run state.
  final bool hasClients;

  /// Creates the [McpAccessView] with a connected client.
  const McpAccessView({super.key}) : hasClients = true;

  /// Creates the view before anything has connected.
  const McpAccessView.empty({super.key}) : hasClients = false;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: Lang.get('screens.mcp.title'),
      subtitle: Lang.get('screens.mcp.subtitle'),
      backLabel: Lang.get('screens.mcp.back'),
      backFallback: '/ayarlar',
      footer: _buildFooter(context),
      children: [
        _buildScope(),
        _buildAddress(),
        if (hasClients) _buildClients() else _buildEmpty(),
      ],
    );
  }

  /// What a connected assistant can and cannot do.
  Widget _buildScope() {
    return Callout(
      intent: CalloutIntent.info,
      title: Lang.get('screens.mcp.scope_title'),
      message: Lang.get('screens.mcp.scope_description'),
    );
  }

  /// The address to paste into the client.
  Widget _buildAddress() {
    return SectionCard(
      label: Lang.get('screens.mcp.address_group'),
      children: [
        // Mono, because this is a string that has to be copied EXACTLY and a proportional face
        // makes a URL harder to check character by character. DESIGN.md routes barcodes and
        // quantities the same way for the same reason.
        // demo-data-start: the tenant address, which the backend will mint per team
        WText(
          'https://mcp.depools.ai/t/8f21c4',
          className: 'text-sm font-mono text-fg',
        ),
        // demo-data-end
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.secondary,
          className: 'py-3 axis-min',
          child: WDiv(
            className: 'flex flex-row items-center gap-2',
            children: [
              const WIcon(_copyIcon, className: 'size-4'),
              WText(Lang.get('screens.mcp.copy')),
            ],
          ),
        ),
        WText(Lang.get('screens.mcp.address_note'), className: 'text-xs text-fg-muted'),
      ],
    );
  }

  /// Everything currently holding a key, and the control that takes it back.
  Widget _buildClients() {
    return SectionCard(
      label: Lang.get('screens.mcp.clients_group'),
      count: Lang.get('screens.mcp.client_count', {'count': 1}),
      children: [
        // demo-data-start: one connected client, standing in for the OAuth grant list
        WDiv(
          className: 'flex flex-row items-center justify-between gap-3 py-2 w-full min-h-11',
          children: [
            WDiv(
              className: 'flex flex-col gap-0.5 flex-1 min-w-0',
              children: [
                WText('Claude Desktop', className: 'text-sm font-medium text-fg truncate'),
                WText(
                  Lang.get('screens.mcp.last_used', {'when': '2 saat önce'}),
                  className: 'text-xs text-fg-muted truncate',
                ),
              ],
            ),
            WDiv(
              className: 'shrink-0',
              child: MSButton(
                onPressed: () {},
                intent: ButtonIntent.ghost,
                className: 'py-3 axis-min',
                semanticLabel: Lang.get('screens.mcp.revoke_one', {'client': 'Claude Desktop'}),
                child: const WIcon(_revokeIcon, className: 'size-4'),
              ),
            ),
          ],
        ),
        // demo-data-end
      ],
    );
  }

  /// Nothing connected yet, which is where every tenant starts.
  Widget _buildEmpty() {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: Lang.get('screens.mcp.empty_title'),
            description: Lang.get('screens.mcp.empty_description'),
          ),
        ),
      ],
    );
  }

  /// Revoking everything at once, which is what a user reaches for when something is wrong.
  ///
  /// Destructive intent and pinned, because the moment this is wanted is the moment it must not
  /// require scrolling to find.
  Widget _buildFooter(BuildContext context) {
    return MSButton(
      onPressed: hasClients
          ? () => MagicStarterConfirmDialog.show(
              context,
              title: Lang.get('screens.mcp.revoke_title'),
              description: Lang.get('screens.mcp.revoke_description'),
              confirmLabel: Lang.get('screens.mcp.revoke_confirm'),
              variant: ConfirmDialogVariant.danger,
            )
          : null,
      disabled: !hasClients,
      intent: hasClients ? ButtonIntent.destructive : ButtonIntent.secondary,
      fullWidth: true,
      className: 'justify-center',
      child: WText(Lang.get('screens.mcp.revoke_all')),
    );
  }
}
