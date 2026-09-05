// `Clipboard` lives in the services library, not in `widgets.dart`. Imported narrowly rather than
// pulling in `material.dart`, which `.claude/rules/design.md` forbids for a view.
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show ButtonIntent, MSButton, MSPageScaffold, MSSwitch, MagicStarterConfig;

import '../../app/models/app_preferences.dart';
import '../../ui/components/option_row/option_row.dart';
import '../../ui/components/section_card/section_card.dart';

/// The app's own settings, as opposed to the account settings `magic_starter` already owns.
///
/// ### Why this screen exists at all
///
/// Two decisions were taken and had nowhere to live. D67 makes the assistant persistent on every
/// screen and promises it can be turned off; D66 turns the old two-front-doors choice into a
/// preference about which capture surface leads on the overview. Both are the user's to set, and
/// `nav.settings` pointed at the starter's profile screen, which knows nothing about either.
///
/// ### The assistant toggle is the concession that makes D67 honest
///
/// The research behind D66 is clear that a persistent chat affordance taxes users who would rather
/// click, and one they cannot dismiss makes that tax permanent. Defaulting to ON is the product
/// position (the AI is the layer this is operated through); the switch is what keeps that position
/// from being imposed.
///
/// The description says what the assistant CAN DO rather than what it is, because someone deciding
/// whether to keep a button on every screen needs to know what they would be giving up.
///
/// ### The start preference is two options, not three
///
/// There is no "overview" option, because the overview is not a choice: it is the home. Offering it
/// here would re-create the three-front-doors shape D66 exists to avoid.
@immutable
class SettingsView extends StatefulWidget {
  /// Creates the [SettingsView].
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  AppPreferences get _prefs => AppPreferences.instance;

  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: Lang.get('screens.settings.title'),
      subtitle: Lang.get('screens.settings.subtitle'),
      children: [
        _buildAssistant(),
        _buildStart(),
        _buildPlacement(),
        _buildAlerts(),
        _buildInbox(),
        _buildLinks(),
      ],
    );
  }

  /// When and about what the app interrupts the user.
  ///
  /// ### One summary, not a stream
  ///
  /// Expiry and low-stock alerts are v1 and had no design at all: `magic_notifications` was wired
  /// and depools' own alert types could be turned on or off nowhere. The shape Anılcan chose is a
  /// once-a-day summary at an hour the user picks, and the reasoning is about aggregate behaviour
  /// rather than about any single alert. Per-event notifications are more actionable one at a time
  /// and unusable at two hundred products: the user mutes the app, and a muted app tells them
  /// nothing at all.
  ///
  /// The hour is a preference because a bakery and a bar do not open at the same time, and a
  /// summary that arrives after the decision it informs is noise.
  ///
  /// The sub-toggles are inside the summary rather than beside it: they choose what the one
  /// notification talks about, so they are meaningless when it is off and are hidden then.
  Widget _buildAlerts() {
    final bool on = _prefs.dailyDigest;

    return SectionCard(
      label: Lang.get('screens.settings.alerts_group'),
      count: on
          ? Lang.get('screens.settings.alerts_at', {'hour': _prefs.digestHour})
          : Lang.get('screens.settings.assistant_off'),
      children: [
        WDiv(
          className: 'flex flex-row items-start justify-between gap-3 w-full',
          children: [
            WDiv(
              className: 'flex flex-col gap-1 flex-1 min-w-0',
              children: [
                WText(
                  Lang.get('screens.settings.digest_toggle'),
                  className: 'text-sm font-semibold text-fg',
                ),
                WText(
                  Lang.get('screens.settings.digest_note'),
                  className: 'text-xs text-fg-muted',
                ),
              ],
            ),
            // **A hairline, because the fill cannot carry the boundary in both appearances.**
            // Measured in light mode on a white card: the off track is #E7E6EC and the thumb is
            // white, so the control's own edge sits at about 1.2:1 against the card and the whole
            // switch nearly disappears. Dark mode hides this completely, which is why it survived
            // three screens. WCAG 1.4.11 asks 3:1 for a UI component's boundary.
            //
            // `border-color-control`, not `border-color-border`: the card hairline is deliberately
            // low contrast and clears nothing, and DESIGN.md records why that is right for a card
            // edge. A control edge is a different job, so it got its own token
            // (`lib/config/depools_control_tokens.dart`), measured at 3.13:1 on a card.
            WDiv(
              className: 'shrink-0',
              child: MSSwitch(
                className: 'border border-color-control',
                value: on,
                semanticLabel: Lang.get('screens.settings.digest_toggle'),
                onChanged: (bool next) async {
                  await _prefs.setDailyDigest(next);
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
        if (on) ...[
          WText(Lang.get('screens.settings.alerts_what'), className: 'text-xs text-fg-muted'),
          // **No `onTap`, because this one genuinely is not a choice.** Its own note says "Always
          // on. Without it the summary has nothing to say", and it carried `onTap: () {}`, so the
          // row read as a toggle, took a tap and answered nothing. `OptionRow` now skips its anchor
          // when there is no gesture, so it reads as the statement it is.
          OptionRow(
            label: Lang.get('screens.settings.alert_dates'),
            description: Lang.get('screens.settings.alert_dates_note'),
            isSelected: true,
            semanticLabel: Lang.get('screens.settings.alert_dates'),
          ),
          OptionRow(
            label: Lang.get('screens.settings.alert_low'),
            description: Lang.get('screens.settings.alert_low_note'),
            isSelected: _prefs.lowStockAlert,
            semanticLabel: Lang.get('screens.settings.alert_low'),
            onTap: () async {
              await _prefs.setLowStockAlert(!_prefs.lowStockAlert);
              if (mounted) setState(() {});
            },
          ),
          OptionRow(
            label: Lang.get('screens.settings.alert_count'),
            description: Lang.get('screens.settings.alert_count_note'),
            isSelected: _prefs.countReminder,
            semanticLabel: Lang.get('screens.settings.alert_count'),
            onTap: () async {
              await _prefs.setCountReminder(!_prefs.countReminder);
              if (mounted) setState(() {});
            },
          ),
        ],
      ],
    );
  }

  /// The address receipts can be forwarded to.
  ///
  /// **A settings section rather than a screen, because there is nothing to do here but read.**
  /// `iterations.md` puts a unique inbound address per tenant in v1 and nothing in the app showed
  /// it, so the feature could ship completely invisible. What a user needs is the string and a way
  /// to copy it exactly, which is one row.
  ///
  /// Mono for the address itself: it has to be typed into a mail client's forwarding rule, and a
  /// proportional face makes a character-by-character check harder. DESIGN.md routes barcodes and
  /// quantities the same way.
  /// The tenant's inbound address.
  ///
  /// A constant until the backend mints one per team, which is why it carries the demo-data marker
  /// at its render site. Held here so the copy button and the label cannot show different strings.
  // demo-data-start: the tenant's inbound address, minted by the backend per team
  static const String _inboxAddress = 'fis-8f21c4@in.depools.ai';
  // demo-data-end

  /// How long to wait for the clipboard before calling it a failure.
  ///
  /// Two seconds is far longer than a clipboard write takes and far shorter than a person will
  /// stare at a button. See [_copyInbox] for why a bound is needed at all.
  static const Duration _clipboardTimeout = Duration(seconds: 2);

  /// Put the inbound address on the clipboard and say so, either way.
  ///
  /// The confirmation matters more than usual here: a clipboard write is invisible, and the user is
  /// about to paste into another application, so silence would leave them checking.
  ///
  /// **And the write does not always answer.** On the web the platform channel reaches
  /// `navigator.clipboard.writeText`, which the browser gates on user activation. Measured on this
  /// screen: under a real click it resolves and the toast appears, and under a synthetic pointer
  /// event (a `fluttersdk_dusk` tap, which injects into the Flutter engine and never reaches the
  /// browser) the promise never settles at all. A bare `await` therefore hung forever and NEITHER
  /// branch below ran, which is why the button looked dead rather than failed.
  ///
  /// So the wait is bounded and both outcomes are reported. The timeout is not there to please a
  /// test harness: a promise that never settles is a button that never answers, and a browser can
  /// withhold the clipboard for reasons other than automation (a permissions policy inside an
  /// iframe is the ordinary one).
  Future<void> _copyInbox() async {
    bool copied = true;

    try {
      await Clipboard.setData(
        const ClipboardData(text: _inboxAddress),
      ).timeout(_clipboardTimeout);
    } on Object catch (error) {
      copied = false;
      Log.warning('The inbound address could not be copied: $error');
    }

    if (!mounted) return;

    final String title = Lang.get('screens.settings.inbox_group');

    if (copied) {
      MagicFeedback.success(title, Lang.get('screens.settings.inbox_copied'));

      return;
    }

    MagicFeedback.error(title, Lang.get('screens.settings.inbox_copy_failed'));
  }

  Widget _buildInbox() {
    return SectionCard(
      label: Lang.get('screens.settings.inbox_group'),
      children: [
        WText(Lang.get('screens.settings.inbox_note'), className: 'text-xs text-fg-muted'),
        // demo-data-start: the tenant's inbound address, minted by the backend per team
        WText(_inboxAddress, className: 'text-sm font-mono text-fg'),
        // demo-data-end
        // **The whole point of the row, and it was `onPressed: () {}`.** The address exists to be
        // typed into a mail client's forwarding rule, so the copy button is the row's reason for
        // being: without it the user is transcribing a hash by eye, which is exactly what the mono
        // face above was chosen to make survivable.
        MSButton(
          onPressed: _copyInbox,
          intent: ButtonIntent.secondary,
          className: 'py-3 axis-min',
          child: WText(Lang.get('screens.settings.inbox_copy')),
        ),
      ],
    );
  }

  /// The three surfaces that are their own screens.
  ///
  /// Settings is where a user looks for anything they can change, so it is where these are found;
  /// each is a screen of its own because each carries a list and actions rather than one value.
  Widget _buildLinks() {
    return SectionCard(
      label: Lang.get('screens.settings.more_group'),
      children: [
        // **The account, which had no door.** The starter's hub used to BE `/settings` and shadowed
        // this whole screen; moving its prefix to `/account` gave this screen back and would have
        // left the account screens unreachable in exchange, which is the same defect facing the
        // other way. Routed through `settingsHubRoute()` rather than a literal, so the link and the
        // config cannot drift apart.
        OptionRow(
          label: Lang.get('screens.settings.link_account'),
          description: Lang.get('screens.settings.link_account_note'),
          isSelected: false,
          semanticLabel: Lang.get('screens.settings.link_account'),
          onTap: () => MagicRoute.to(MagicStarterConfig.settingsHubRoute()),
        ),
        OptionRow(
          label: Lang.get('screens.settings.link_plan'),
          description: Lang.get('screens.settings.link_plan_note'),
          isSelected: false,
          semanticLabel: Lang.get('screens.settings.link_plan'),
          onTap: () => MagicRoute.to('/plan'),
        ),
        OptionRow(
          label: Lang.get('screens.settings.link_mcp'),
          description: Lang.get('screens.settings.link_mcp_note'),
          isSelected: false,
          semanticLabel: Lang.get('screens.settings.link_mcp'),
          onTap: () => MagicRoute.to('/mcp'),
        ),
      ],
    );
  }

  /// How much the app decides about placement on its own.
  ///
  /// **Mirrored from the locations screen rather than moved off it.** The dial started as a
  /// control below the location tree, which put it downstream of an infinite scroll: any tenant
  /// with enough locations to care about automated placement could not reach the setting that
  /// governs it. Anılcan named the shape, and it generalises past this one control, so the rule
  /// is now that a preference is reachable from settings whatever else also offers it.
  ///
  /// The stored value is `AppPreferences.placementAutomation`, so the two surfaces cannot
  /// disagree; this screen holds the canonical copy under `screens.settings.mode_*` and the
  /// locations screen reads the same keys.
  Widget _buildPlacement() {
    final PlacementAutomation current = _prefs.placementAutomation;

    return SectionCard(
      label: Lang.get('screens.settings.placement_group'),
      count: _modeLabel(current),
      children: [
        WText(Lang.get('screens.settings.placement_note'), className: 'text-xs text-fg-muted'),
        for (final PlacementAutomation mode in PlacementAutomation.values)
          OptionRow(
            label: _modeLabel(mode),
            description: _modeNote(mode),
            isSelected: current == mode,
            semanticLabel: _modeLabel(mode),
            onTap: () async {
              await _prefs.setPlacementAutomation(mode);
              if (mounted) setState(() {});
            },
          ),
      ],
    );
  }

  /// The already-localised label for a dial position.
  static String _modeLabel(PlacementAutomation value) => switch (value) {
    PlacementAutomation.manual => Lang.get('screens.settings.mode_manual'),
    PlacementAutomation.semiAuto => Lang.get('screens.settings.mode_suggested'),
    PlacementAutomation.fullAuto => Lang.get('screens.settings.mode_auto'),
  };

  /// What a dial position actually does, in one line.
  static String _modeNote(PlacementAutomation value) => switch (value) {
    PlacementAutomation.manual => Lang.get('screens.settings.mode_manual_note'),
    PlacementAutomation.semiAuto => Lang.get('screens.settings.mode_suggested_note'),
    PlacementAutomation.fullAuto => Lang.get('screens.settings.mode_auto_note'),
  };

  /// The persistent-assistant switch.
  Widget _buildAssistant() {
    final bool on = _prefs.assistantEverywhere;

    return SectionCard(
      label: Lang.get('screens.settings.assistant_group'),
      count: Lang.get(on ? 'screens.settings.assistant_on' : 'screens.settings.assistant_off'),
      children: [
        WDiv(
          className: 'flex flex-row items-start justify-between gap-3 w-full',
          children: [
            WDiv(
              className: 'flex flex-col gap-1 flex-1 min-w-0',
              children: [
                WText(
                  Lang.get('screens.settings.assistant_toggle'),
                  className: 'text-sm font-semibold text-fg',
                ),
                WText(
                  Lang.get('screens.settings.assistant_note'),
                  className: 'text-xs text-fg-muted',
                ),
              ],
            ),
            // `shrink-0` so the switch keeps its size while the description reflows around it.
            WDiv(
              className: 'shrink-0',
              child: MSSwitch(
                className: 'border border-color-control',
                value: on,
                semanticLabel: Lang.get('screens.settings.assistant_toggle'),
                onChanged: (bool next) async {
                  await _prefs.setAssistantEverywhere(next);
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Which capture surface leads on the overview.
  Widget _buildStart() {
    return SectionCard(
      label: Lang.get('screens.settings.start_group'),
      children: [
        WText(Lang.get('screens.settings.start_note'), className: 'text-xs text-fg-muted'),
        for (final CaptureVerb verb in CaptureVerb.values)
          OptionRow(
            label: Lang.get(
              verb == CaptureVerb.assistant
                  ? 'screens.settings.verb_assistant'
                  : 'screens.settings.verb_inventory',
            ),
            description: Lang.get(
              verb == CaptureVerb.assistant
                  ? 'screens.settings.verb_assistant_note'
                  : 'screens.settings.verb_inventory_note',
            ),
            isSelected: _prefs.captureVerb == verb,
            semanticLabel: Lang.get(
              verb == CaptureVerb.assistant
                  ? 'screens.settings.verb_assistant'
                  : 'screens.settings.verb_inventory',
            ),
            onTap: () async {
              await _prefs.setCaptureVerb(verb);
              if (mounted) setState(() {});
            },
          ),
        // Said once, at the bottom, rather than on each control: the storage is a property of this
        // whole screen and repeating it per row would read as a warning about the row.
        // `fg-muted`, not `fg-disabled`: this is a quiet note, and the disabled token is for
        // inactive controls. Using it here would make a true statement look switched off.
        WText(Lang.get('screens.settings.local_note'), className: 'text-xs text-fg-muted'),
      ],
    );
  }
}
