import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show
        MSButton,
        ButtonIntent,
        ButtonSize,
        MSInput,
        MSPageContainer,
        MSPageHeader,
        MSSkeleton,
        SkeletonShape;

import '../../../ui/components/chat_message/chat_message.dart';
import '../../../ui/components/choice_chip/choice_chip.dart';
import '../../../ui/components/movement_row/movement_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/shopping_row/shopping_row.dart';
import 'activity_panel.dart';
import 'product_fixtures.dart';
import 'shopping_fixtures.dart';

/// The assistant surface: capture by sentence, answers as components.
///
/// ### The hardest problem in the product, and the answer taken
///
/// `ai-assistant.md` names it outright: how does assistant mode present the stock overview
/// a transcript cannot give, given that getting this wrong is what makes chat-first apps
/// fail. Its own diagnosis is precise. Users cannot get an overview from a transcript, and
/// they scroll back through history trying to reconstruct what they decided.
///
/// Two answers, because those are two different failures.
///
/// **The assistant answers with components, never with prose about state** (D49). A
/// question about the shopping list returns the same `ShoppingRow`s the list screen renders.
/// A write returns the same `MovementRow` the product's history will show. So scrolling back
/// through the transcript shows state changes rather than sentences describing them, there
/// is nothing to reconstruct, and every answer is tappable through to the real screen. It
/// also makes it structurally impossible for the assistant to disagree with the rest of the
/// app about a number, which is the failure this codebase has already shipped once.
///
/// **The overview is chrome, not a message** (D50). Three figures sit above the transcript
/// and never enter it, because anything inside a transcript scrolls away and a summary that
/// scrolls away is not a summary. They are derived from the same fixtures the other screens
/// read, so the assistant's headline cannot drift from the product list's.
///
/// ### The capture shape
///
/// Act on parsed facts, ask afterwards, never act on a guess (D13). The milk is written
/// immediately as a movement; location is unknown and high-impact, so it becomes one grouped
/// card of chips. Never a second card in the same capture.
///
/// ### It has to feel like a chat window
///
/// **This is the one screen that does not go through `MSPageScaffold`.** That scaffold scrolls
/// all of its children, which on a transcript means the composer scrolls away and you have to
/// scroll down to type. Anılcan named it: it did not feel like a chat window. A chat surface is
/// a genuinely different page shape, so this one composes the same pieces itself
/// (`MSPageHeader`, `MSPageContainer`) with the transcript as the only scrolling part.
///
/// The transcript is `reverse: true`, which puts the newest exchange at the bottom where a chat
/// belongs and makes "scroll up for older" the natural direction: reaching the far end of a
/// reversed list IS reaching the start of the history, so that is where the older-messages
/// loader sits.
///
/// ### The approval gate is visible
///
/// Under semi-auto a stock-changing write pauses and returns a pending approval. That is
/// rendered as a card in the transcript rather than a dialog, because it belongs to the
/// exchange that produced it and because a dialog would be dismissed to get it out of the
/// way.
@immutable
class AssistantView extends StatelessWidget {
  static const IconData _sendIcon = Icons.arrow_upward;
  static const IconData _cameraIcon = Icons.photo_camera_outlined;
  static const IconData _micIcon = Icons.mic_none_outlined;
  static const IconData _activityIcon = Icons.history;

  /// Whether the conversation has started.
  ///
  /// The first run is its own state and not a lesser one: an empty transcript is where a user
  /// decides whether this thing understands Turkish grocery sentences, and a blank box answers
  /// that with nothing.
  final bool hasTranscript;

  /// Creates the [AssistantView] mid-conversation.
  const AssistantView({super.key}) : hasTranscript = true;

  /// Creates the view before the first message.
  const AssistantView.fresh({super.key}) : hasTranscript = false;

  /// **No inner width cap.** `MSPageContainer` already caps every screen in this app at the
  /// same width, and adding a second cap inside it made the header narrower than the transcript
  /// beneath it: two columns, one screen. Three className attempts and then an
  /// `Align` + `ConstrainedBox` all produced the same inconsistency, because the fix was to stop
  /// capping rather than to cap correctly.
  ///
  /// The readability worry the cap was meant to answer is already answered one level down:
  /// `ChatMessage` caps the user's bubble at `max-w-md`, so a sentence never spans the window
  /// however wide the card behind it is. And a card here being the same width as a card on the
  /// stock list is the point, not a problem.
  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col bg-surface',
      children: [
        // Chrome, and it costs two rows. Fixed, so the mode and the counts never scroll away
        // (D50).
        MSPageContainer(
          // **`pb-0`, and the reasoning that rejected it was wrong.** The shared geometry is
          // `px-4 md:px-5 pt-6 pb-16`, so the page's 64px bottom margin landed between the chips
          // and the transcript: 77px of dead band, measured, which is what Anılcan saw as the
          // screen looking cut. An earlier pass blamed a `p-*`/`py-*` family collision and
          // dropped the override, but the geometry names no `p-*` shorthand at all: `pb-*` and
          // `px-*` are separate families, so this replaces the bottom margin and nothing else.
          // Pixel-verified after the change: divider and cards both span 293..1331.
          //
          // Direct children, the way `MSPageScaffold` passes them.
          className: 'pb-0',
          children: [
            // **The standard header, and the reason it was ever replaced no longer holds.**
            // It was dropped because at 390px it stacked its action onto a row of its own,
            // but that was measured inside a phone frame this preview no longer uses. Every
            // other screen uses `MSPageHeader`, and consistency beats the forty pixels a
            // hand-rolled row saved.
            MSPageHeader(
              title: Lang.get('screens.assistant.title'),
              // **What the automation level DOES, not what it is called.** This said
              // "· yarı otomatik", which is a level name from D10 and means nothing to the
              // person reading it. The mode matters only through its consequence, so the
              // consequence is what gets said.
              subtitle: Lang.get('screens.assistant.subtitle'),
              actions: [
                MSButton(
                  onPressed: () => ActivityPanel.show(context),
                  intent: ButtonIntent.ghost,
                  className: 'h-11 w-11 px-0 justify-center',
                  semanticLabel: Lang.get('screens.assistant.activity'),
                  child: const WIcon(_activityIcon, className: 'size-5'),
                ),
              ],
            ),
            _buildStatusRow(),
          ],
        ),
        // The only scrolling part, and it needs a BOUNDED height to be one.
        //
        // `h-full` was the obvious way and wind asserts against it by name: the app shell wraps
        // a route in a vertical scroll, so `h-full` there resolves to infinity. The guard even
        // names the fix (`flex-1` inside a `flex flex-col`), which does not apply either,
        // because there is no bounded column to divide: the shell's scroll is the parent.
        //
        // So the height comes from the viewport, computed in Flutter because Core Law 3 forbids
        // interpolating it into a className. Clamped at both ends: below 280 a transcript shows
        // one exchange and above 640 the composer drifts off a laptop screen.
        //
        // The remaining gap is real and is the shell's: a composer pinned to the VIEWPORT
        // bottom needs `layout.app` not to scroll this route, which is a magic_starter change.
        // `py-0` on the container: two stacked `MSPageContainer`s put their vertical padding
        // back to back and left a dead band between the chips and the list. With the list's top
        // edge flush under the chrome, a half-visible card reads as content scrolled under a
        // boundary, which is what every chat does. With the band there it read as a rendering
        // fault, and Anılcan asked why it looked cut.
        ConstrainedBox(
          // **A ceiling, not a height, and that distinction was a visible defect.** A fixed
          // height plus `reverse: true` pins a short transcript to the BOTTOM of its box, so
          // a SHORT transcript to the bottom of its box and leaves the rest of the box empty.
          // The 77px band above this list turned out to be the container's `pb-16` rather than
          // this, and the ceiling is still the right shape: `AssistantView.fresh` carries two
          // openers and would otherwise render them against 450px of nothing.
          //
          // With a max and `shrinkWrap`, the list takes the smaller of its content and the
          // ceiling: short transcripts hug, long ones fill the ceiling and scroll with the
          // newest exchange at the bottom.
          //
          // **The fraction has to leave room for what it cannot see.** `MediaQuery` reports the
          // WINDOW, and the shell spends part of it on an app bar and a bottom nav before this
          // route gets any: at 0.62 the transcript alone was taller than what was left and the
          // composer fell below the fold, behind the nav. 0.45 plus the clamp keeps
          // chrome + transcript + composer inside the shell's box at both phone and laptop
          // heights, measured against the 390px frame.
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.sizeOf(context).height * 0.45).clamp(240.0, 520.0),
          ),
          child: MSPageContainer(className: 'py-0', child: _buildTranscript(context)),
        ),
        // Pinned. A chat you have to scroll to type into is not a chat.
        // `pt-3`: the page geometry's `pt-6` belongs at the TOP of a page, and this container is
        // in the middle of one. `pb-8` rather than the shared `pb-16`, because 64px under a
        // composer that is meant to sit at the bottom of the screen is dead page.
        MSPageContainer(className: 'pt-3 pb-8', child: _buildComposer()),
      ],
    );
  }

  /// The three figures a transcript cannot give, as one row of counters (D50).
  ///
  /// **Chips, not stat cards.** Three cards were three different heights, because their labels
  /// wrapped unevenly at phone width and put the three numbers on three baselines; they also
  /// overflowed the row to the right and cost more vertical space than the first message did. A
  /// chip is content-sized in width and uniform in height by construction, so this cannot
  /// misalign however the labels change, and it is the same pill the rest of the app already
  /// uses rather than a fourth thing to learn.
  ///
  /// Derived, never typed: each count reads the same fixtures the product list and the shopping
  /// list read, so the assistant cannot headline a number the rest of the app disagrees with.
  Widget _buildStatusRow() {
    final int expiring = productFixtures.where((p) => p.isExpiringSoon || p.isExpired).length;
    final int low = pendingLines.length;
    final int untargeted = productFixtures.where((p) => p.parLevel == null).length;

    return WDiv(
      // `pt-3`: the chips were sitting on the header's divider with no air between them, which
      // reads as a rendering fault rather than as two grouped rows.
      className: 'flex flex-row wrap items-center gap-2 pt-3 pb-3',
      children: [
        ChoiceChip(
          label: Lang.get('screens.assistant.chip_expiring', {'count': expiring}),
          semanticLabel: Lang.get('screens.assistant.chip_expiring_label', {'count': expiring}),
          onTap: () {},
        ),
        ChoiceChip(
          label: Lang.get('screens.assistant.chip_low', {'count': low}),
          semanticLabel: Lang.get('screens.assistant.chip_low_label', {'count': low}),
          onTap: () {},
        ),
        ChoiceChip(
          label: '$untargeted hedefsiz',
          semanticLabel: Lang.get('screens.assistant.chip_untargeted_label', {'count': untargeted}),
          onTap: () {},
        ),
      ],
    );
  }

  /// The exchange, newest at the bottom, older loading upward.
  ///
  /// `reverse: true` is what makes this a chat rather than a page of messages: the newest
  /// exchange sits against the composer, and the list's far end is the START of the history, so
  /// scrolling up is scrolling back and the loader belongs there. Rendered bottom-up for the
  /// same reason, which is why the children list is reversed.
  Widget _buildTranscript(BuildContext context) {
    // The first run has no history to scroll, so it gets the openers instead: sample utterances
    // in the user's own words, because the question a new user has is not "what can this do" but
    // "what do I type".
    final List<Widget> items = hasTranscript ? _newestFirst() : <Widget>[_buildOpeners()];

    return _transcriptList(items);
  }

  /// The exchange, newest first, because the list is reversed.
  List<Widget> _newestFirst() {
    return <Widget>[
      _buildApprovalCard(),
      // demo-data-start: the transcript the preview renders, standing in for a real exchange
      const ChatMessage(text: 'kıymayı derin dondurucuya taşı', speaker: ChatSpeaker.user),
      // demo-data-end
      _buildShortageCard(),
      const ChatMessage(text: 'neyim eksik', speaker: ChatSpeaker.user),
      _buildPlacementCard(),
      _buildWriteCard(),
      // demo-data-start: the transcript the preview renders, standing in for a real exchange
      const ChatMessage(text: 'Süt stoğa yazıldı.'),
      const ChatMessage(text: '1 adet süt aldım', speaker: ChatSpeaker.user),
      // demo-data-end
      // The far end of a reversed list is the top of the screen, so this is where "older
      // messages are coming" belongs. Skeletons in the shape of a message, not bars.
      _buildOlderLoader(),
    ];
  }

  /// The scrolling list itself.
  ///
  /// `separated`, so the spacing between messages is ONE value the list owns. Each item used to
  /// carry its own vertical padding, so a card-to-bubble gap and a bubble-to-bubble gap came out
  /// different and the rhythm was visibly uneven.
  Widget _transcriptList(List<Widget> items) {
    return ListView.separated(
      reverse: true,
      // Measured, not lazy: the ceiling above is only a ceiling if the list can report a
      // height smaller than it. The cost is that every exchange builds at once, which a
      // transcript this length can afford and a dead 99px band cannot.
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemCount: items.length,
      itemBuilder: (_, index) => items[index],
    );
  }

  /// Older history arriving as the user scrolls back.
  ///
  /// Two message-shaped placeholders rather than a spinner, and one of them right-aligned,
  /// because what is coming is an exchange: a bar says something is loading, a shape says what.
  Widget _buildOlderLoader() {
    return WDiv(
      className: 'flex flex-col gap-2 py-3',
      children: [
        WDiv(
          className: 'flex flex-row justify-end',
          child: MSSkeleton(shape: SkeletonShape.text, width: 140, height: 34),
        ),
        WDiv(
          className: 'flex flex-row justify-start',
          child: MSSkeleton(shape: SkeletonShape.text, width: 220, height: 16),
        ),
        WText(Lang.get('screens.assistant.older'), className: 'text-xs text-fg-muted'),
      ],
    );
  }

  /// The write, rendered as the ledger row it produced.
  ///
  /// Not "Süt eklendi (1 adet)" as a sentence. The same `MovementRow` the product's own
  /// history will show, so the transcript and the ledger cannot tell different stories, and
  /// so scrolling back through the conversation reads as a list of changes.
  Widget _buildWriteCard() {
    return SectionCard(
      label: Lang.get('screens.assistant.written'),
      action: MSButton(
        onPressed: () {},
        intent: ButtonIntent.ghost,
        size: ButtonSize.sm,
        child: WText(Lang.get('screens.assistant.undo')),
      ),
      children: [
        MovementRow(
          reason: Lang.get('screens.assistant.purchase'),
          deltaAmount: 1,
          delta: '+1',
          unit: 'adet',
          // Product and surface, which is what criterion 4 asks a feed entry to carry.
          // The timestamp was here too and truncated the product name off the end, which
          // is the one part that cannot be dropped.
          // demo-data-start: the transcript the preview renders, standing in for a real exchange
          meta: 'Pınar Süt Tam Yağlı 1 lt · asistan',
          // demo-data-end
          direction: MovementDirection.inbound,
        ),
      ],
    );
  }

  /// The one grouped card D13 allows, and no second one.
  ///
  /// The suggested chip carries its own count, which is the whole explanation: a suggestion
  /// the user can disagree with is one they will accept.
  Widget _buildPlacementCard() {
    final (String, int)? affinity = suggestLocationFor('cat-dairy');

    return SectionCard(
      label: Lang.get('screens.assistant.where_group'),
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 py-1',
          children: [
            if (affinity != null)
              ChoiceChip(
                // demo-data-start: the transcript the preview renders, standing in for a real exchange
                label: resolveLocationLabel(affinity.$1) ?? 'Buzdolabı',
                // demo-data-end
                evidence: '${affinity.$2} kez',
                isSuggested: true,
                semanticLabel: Lang.get('screens.assistant.where_put', {'location': resolveLocationLabel(affinity.$1)}),
              ),
            ChoiceChip(label: 'Kiler', semanticLabel: Lang.get('screens.assistant.where_put', {'location': 'Kiler'})),
            // An explicit skip, because every chip has to be a real answer and "I will do
            // it later" is one of them.
            ChoiceChip(label: Lang.get('screens.assistant.where_later'), semanticLabel: Lang.get('screens.assistant.where_skip')),
          ],
        ),
      ],
    );
  }

  /// The answer to "neyim eksik", rendered as the shopping list itself.
  Widget _buildShortageCard() {
    return SectionCard(
      label: Lang.get('screens.assistant.shopping_group'),
      count: Lang.get('screens.assistant.shopping_count', {'count': pendingLines.length}),
      // The way out to the real screen. Criterion 7 says every capability here is also
      // reachable in inventory mode, and a link is how that stops being a promise.
      action: MSButton(
        onPressed: () {},
        intent: ButtonIntent.ghost,
        size: ButtonSize.sm,
        child: WText(Lang.get('screens.assistant.shopping_open')),
      ),
      children: [
        for (final ShoppingFixture line in pendingLines.take(3))
          ShoppingRow(
            name: line.name,
            amount: line.amount,
            formatted: line.formatted,
            unit: line.unit,
            reason: line.reason,
            reasonDetail: line.reasonDetail,
            onToggle: () {},
          ),
      ],
    );
  }

  /// A stock-changing write under semi-auto: paused, and shown as what it will do.
  ///
  /// The card states the movement pair rather than the intent, because "kıymayı dondurucuya
  /// taşı" is the request and `-1 kg buzdolabından, +1 kg derin dondurucuya` is the thing
  /// being approved. Approving a sentence you did not write is how a user ends up approving
  /// something else.
  Widget _buildApprovalCard() {
    return SectionCard(
      label: Lang.get('screens.assistant.pending_group'),
      children: [
        const MovementRow(
          // demo-data-start: the transcript the preview renders, standing in for a real exchange
          reason: 'Konumlar arası taşıma',
          // demo-data-end
          deltaAmount: -1,
          delta: '-1',
          unit: 'kg',
          // demo-data-start: the transcript the preview renders, standing in for a real exchange
          meta: 'Kıyma · Mutfak › Buzdolabı',
          // demo-data-end
          direction: MovementDirection.outbound,
        ),
        const MovementRow(
          // demo-data-start: the transcript the preview renders, standing in for a real exchange
          reason: 'Konumlar arası taşıma',
          // demo-data-end
          deltaAmount: 1,
          delta: '+1',
          unit: 'kg',
          // demo-data-start: the transcript the preview renders, standing in for a real exchange
          meta: 'Kıyma · Mutfak › Derin dondurucu',
          // demo-data-end
          direction: MovementDirection.inbound,
        ),
        WDiv(
          className: 'flex flex-row items-center gap-2 pt-2',
          children: [
            WDiv(
              className: 'flex-1 min-w-0',
              child: MSButton(
                onPressed: () {},
                fullWidth: true,
                className: 'justify-center',
                child: WText(Lang.get('screens.assistant.approve')),
              ),
            ),
            WDiv(
              className: 'flex-1 min-w-0',
              child: MSButton(
                onPressed: () {},
                // **Not ghost.** A ghost button beside a filled one is text with no boundary:
                // measured on screen, `Onayla` painted a 499px fill and `Reddet` painted
                // nothing at all, so the pair read as one button and a caption rather than a
                // choice. Rejecting a suggestion is a peer of accepting it, not a footnote.
                //
                // `secondary` ships `bg-surface-container-high`, DESIGN.md's INPUT tone, which
                // on a white card is darker than its container and reads as disabled even with
                // the hairline. The caller className appends last, so card tone wins the fill
                // and the recipe's border survives.
                intent: ButtonIntent.secondary,
                fullWidth: true,
                className: 'justify-center bg-surface-container',
                child: WText(Lang.get('screens.assistant.reject')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The first run: what you can say, in the user's own words.
  ///
  /// Sample utterances rather than a feature list, because the question a new user has is
  /// not "what can this do" but "what do I type". They are chips so the first message costs
  /// one tap, and they are deliberately Turkish grocery sentences with the shapes the parser
  /// has to survive.
  Widget _buildOpeners() {
    return SectionCard(
      label: Lang.get('screens.assistant.opener_group'),
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 py-1',
          children: [
            ChoiceChip(
              label: Lang.get('screens.assistant.opener_buy'),
              semanticLabel: Lang.get('screens.assistant.opener_buy_label'),
              onTap: () {},
            ),
            ChoiceChip(
              label: Lang.get('screens.assistant.opener_mince'),
              semanticLabel: Lang.get('screens.assistant.opener_mince_label'),
              onTap: () {},
            ),
            ChoiceChip(
              label: 'neyim eksik',
              semanticLabel: Lang.get('screens.assistant.opener_missing'),
              onTap: () {},
            ),
            ChoiceChip(
              label: Lang.get('screens.assistant.opener_ask'),
              semanticLabel: Lang.get('screens.assistant.opener_ask_label'),
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }

  /// Text, photo and voice, which are the three inputs `ai-assistant.md` names.
  ///
  /// **One height for every part, declared once.** The buttons carried `min-h-11` and the input
  /// carried whatever its own padding produced, so they sat at different heights in a row that
  /// reads as one control. `h-11` on all four, and `items-center` so nothing drifts if one of
  /// them ever measures differently.
  ///
  /// All three inputs sit on one row at every width. A camera on a laptop is a worse camera, not
  /// an absent one, and hiding it by platform is what DESIGN.md's layout rule forbids.
  Widget _buildComposer() {
    return WDiv(
      className: 'flex flex-col gap-2 py-3',
      children: [
        WDiv(
          // `items-end`: once the input grows the buttons stay on its last line rather than
          // floating in the middle of a four-line box.
          className: 'flex flex-row items-end gap-2',
          children: [
            _composerButton(_cameraIcon, Lang.get('screens.assistant.photo'), ButtonIntent.secondary),
            _composerButton(_micIcon, Lang.get('screens.assistant.voice'), ButtonIntent.secondary),
            WDiv(
              className: 'flex-1 min-w-0',
              child: MSInput(
                // Card tone so an enabled field does not read as disabled.
                className: 'bg-surface-container',
                placeholder: Lang.get('screens.assistant.composer'),
                // **Multiline, growing.** It was a single line at a fixed `h-11`, which is wrong
                // for this screen: the sentences it is built for are things like "dün akşam
                // markete gittim, iki litre süt bir de yarım kilo kıyma aldım", and a chat
                // composer that scrolls one line horizontally hides what you just typed. It
                // starts at one line so the row keeps the buttons' height until there is a
                // reason to grow, and stops at four so it cannot swallow the transcript.
                type: InputType.multiline,
                minLines: 1,
                maxLines: 4,
              ),
            ),
            _composerButton(_sendIcon, Lang.get('screens.assistant.send'), ButtonIntent.primary),
          ],
        ),
        // Voice is the one input that confirms before committing, and saying so here is
        // cheaper than surprising someone with a confirmation card they did not expect.
        WText(Lang.get('screens.assistant.voice_note'), className: 'text-xs text-fg-muted'),
      ],
    );
  }

  /// One composer button, at the row's shared height.
  ///
  /// **Two of the three are secondary, not ghost, and that is a correction.** Ghost paints no
  /// surface, so the camera and the microphone were bare glyphs sitting beside a filled send
  /// button: three controls in one row, one of which looked like a control. `secondary` gives
  /// them the hairline that makes a tappable region visible in both appearances, and send keeps
  /// `primary` because it IS the row's primary action.
  ///
  /// Card tone overrides the recipe's `bg-surface-container-high` for the same reason it does on
  /// `Reddet`: that token is the input fill, and it reads as disabled on a light card.
  Widget _composerButton(IconData icon, String label, ButtonIntent intent) {
    return MSButton(
      onPressed: () {},
      intent: intent,
      // `px-0` alongside the forced square. MSButton carries its own horizontal padding, and
      // with a fixed `w-11` that padding is asymmetric against the glyph: `justify-center`
      // centres inside the content box, not inside the button, so the arrow sat left of centre.
      // Same trap as `min-h-11` on this component, one axis over.
      className: intent == ButtonIntent.secondary
          ? 'h-11 w-11 px-0 justify-center bg-surface-container'
          : 'h-11 w-11 px-0 justify-center',
      semanticLabel: label,
      child: WIcon(icon, className: 'size-5'),
    );
  }
}
