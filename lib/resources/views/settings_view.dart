import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSPageScaffold, MSSwitch;

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
      ],
    );
  }

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
            suggestionReason: Lang.get(
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
        WText(Lang.get('screens.settings.local_note'), className: 'text-xs text-fg-disabled'),
      ],
    );
  }
}
