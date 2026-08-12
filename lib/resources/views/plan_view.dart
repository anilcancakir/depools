import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show ButtonIntent, MSButton;

import '../../ui/components/quota_meter/quota_meter.dart';
import '../../ui/components/section_card/section_card.dart';
import '../../ui/layouts/app_page_scaffold.dart';

/// The plan, what it meters, and what happens when a meter runs out.
///
/// ### The screen exists to answer one question the MVP could not
///
/// D4 is blunt about the failure: the MVP metered five axes at once (users, products, locations,
/// barcode scans, AI requests) and a user could not tell which limit they had hit, so it surfaced
/// as a dead-end 403. `monetization.md` cut that to three axes, and this screen is the other half
/// of the fix: the limits are legible BEFORE they bite.
///
/// So every meter states its consequence, in its own words, in the same breath as its number. A bar
/// says how full something is; it does not say what stops.
///
/// ### Nothing here is a warning
///
/// `monetization.md` is explicit that at the limit everything existing keeps working and only the
/// metered action is blocked. That is a promise worth rendering: the notes say what stops rather
/// than what breaks, and the full state does not turn the screen red. A user at their product
/// limit has not done anything wrong.
///
/// ### Why history is a meter and not a feature flag
///
/// Retention is metered because Sortly meters it (D3), and it degrades rather than disappears:
/// history beyond the window becomes unqueryable, never deleted. The note says so, because
/// "deleted" is what a user will assume otherwise and it would be the one irreversible-sounding
/// thing on the screen.
@immutable
class PlanView extends StatelessWidget {
  static const IconData _upgradeIcon = Icons.arrow_upward;

  /// Whether the tenant has hit a limit, which is its own reviewable state.
  final bool isAtLimit;

  /// Creates the [PlanView] for a tenant with room left.
  const PlanView({super.key}) : isAtLimit = false;

  /// Creates the view for a tenant at their product limit.
  const PlanView.atLimit({super.key}) : isAtLimit = true;

  /// Products used, standing in for the unique-SKU meter.
  int get _products => isAtLimit ? 50 : 34;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: Lang.get('screens.plan.title'),
      subtitle: Lang.get('screens.plan.subtitle'),
      backLabel: Lang.get('screens.plan.back'),
      backFallback: '/settings',
      footer: _buildFooter(),
      children: [_buildCurrent(), _buildMeters(), _buildSeats()],
    );
  }

  /// Which plan is running, and until when.
  Widget _buildCurrent() {
    return SectionCard(
      label: Lang.get('screens.plan.current_group'),
      count: Lang.get('screens.plan.plan_free'),
      children: [
        WText(
          Lang.get('screens.plan.renewal'),
          className: 'text-sm text-fg-muted',
        ),
      ],
    );
  }

  /// The three axes, each with what it stops.
  Widget _buildMeters() {
    return SectionCard(
      label: Lang.get('screens.plan.usage_group'),
      children: [
        // **One box with a bigger gap, because three meters were reading as one block.** A meter's
        // own parts sit 6px apart and the card's body separates its children by about the same, so
        // a note ran straight into the next label with nothing between them. `gap-5` makes the
        // separation between meters larger than the separation inside one, which is the whole
        // grouping rule DESIGN.md states: more space between groups than within them.
        WDiv(
          className: 'flex flex-col gap-5 w-full',
          children: [
            QuotaMeter(
              label: Lang.get('screens.plan.meter_products'),
              used: _products,
              limit: 50,
              value: Lang.get('screens.plan.meter_products_value', {
                'used': _products,
                'limit': 50,
              }),
              note: Lang.get('screens.plan.meter_products_note'),
            ),
            QuotaMeter(
              label: Lang.get('screens.plan.meter_credits'),
              used: 86,
              limit: 100,
              value: Lang.get('screens.plan.meter_credits_value', {
                'used': 86,
                'limit': 100,
              }),
              note: Lang.get('screens.plan.meter_credits_note'),
            ),
            // **No bar, and that was a correction.** Retention was first rendered as `1 / 1`, which
            // filled the track and turned it red: the screen told a tenant on the free plan that they
            // had hit a limit they had not touched. Retention is not a quantity being consumed, it is
            // a WINDOW LENGTH that is the same on day one as on day three hundred. A meter with
            // nothing to fill draws no track, which is the same rule the unlimited case uses.
            QuotaMeter(
              label: Lang.get('screens.plan.meter_history'),
              used: 0,
              value: Lang.get('screens.plan.meter_history_value', {
                'months': 1,
              }),
              note: Lang.get('screens.plan.meter_history_note'),
            ),
          ],
        ),
      ],
    );
  }

  /// The axis that is deliberately NOT metered, said out loud.
  ///
  /// D4 makes seats unlimited so team adoption is never penalised, and a user comparing plans will
  /// look for the seat limit first because every other product has one. Stating its absence is
  /// worth more than leaving it out.
  Widget _buildSeats() {
    return SectionCard(
      label: Lang.get('screens.plan.seats_group'),
      count: Lang.get('screens.plan.seats_unlimited'),
      children: [
        WText(
          Lang.get('screens.plan.seats_note'),
          className: 'text-sm text-fg-muted',
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              WText(Lang.get('screens.plan.upgrade')),
              const WIcon(_upgradeIcon, className: 'size-4'),
            ],
          ),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.plan.compare')),
        ),
      ],
    );
  }
}
