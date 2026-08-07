import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSButton, ButtonIntent, ButtonSize, MSInput, MSPageContainer, MSSkeleton, SkeletonShape;

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
  /// The first run is its own state and not a lesser one: an empty transcript is where a
  /// user decides whether this thing understands Turkish grocery sentences, and a blank box
  /// answers that with nothing.
  final bool hasTranscript;

  /// Creates the [AssistantView] mid-conversation.
  const AssistantView({super.key}) : hasTranscript = true;

  /// Creates the view before the first message.
  const AssistantView.fresh({super.key}) : hasTranscript = false;

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col bg-surface',
      children: [
        // Chrome, and it costs two rows. Fixed, so the mode and the counts never scroll away
        // (D50).
        MSPageContainer(className: 'pb-0', children: [_buildTitleRow(context), _buildStatusRow()]),
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
        SizedBox(
          height: (MediaQuery.sizeOf(context).height * 0.62).clamp(320.0, 720.0),
          child: MSPageContainer(className: 'py-0', child: _buildTranscript(context)),
        ),
        // Pinned. A chat you have to scroll to type into is not a chat.
        MSPageContainer(child: _buildComposer()),
      ],
    );
  }

  /// The screen's name, its automation mode and the activity panel, on ONE row.
  ///
  /// **This replaces an `MSPageHeader`, and the reason is the shape of the screen.** A page
  /// header spends a title line, a subtitle line, and then stacks its actions BELOW at phone
  /// width, which left the history icon orphaned on a row of its own. Three chrome layers stood
  /// between the app bar and the first message. A chat cannot afford that: the conversation is
  /// the content, so its identity gets one 44pt row and no more.
  ///
  /// The mode sits beside the name rather than under it, because it is one word of context
  /// rather than a subtitle, and because a wrapping subtitle is what pushed everything down.
  Widget _buildTitleRow(BuildContext context) {
    return WDiv(
      className: 'flex flex-row items-center gap-2 min-h-11',
      children: [
        WText('Asistan', className: 'text-base font-semibold text-fg axis-min'),
        WText('· yarı otomatik', className: 'text-xs text-fg-muted flex-auto min-w-0'),
        MSButton(
          onPressed: () => ActivityPanel.show(context),
          intent: ButtonIntent.ghost,
          className: 'h-11 w-11 justify-center',
          semanticLabel: 'Hareketler',
          child: const WIcon(_activityIcon, className: 'size-5'),
        ),
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
      className: 'flex flex-row wrap items-center gap-2 pb-3',
      children: [
        ChoiceChip(
          label: '$expiring tarihi yakın',
          semanticLabel: 'Tarihi yaklaşan $expiring ürünü göster',
          onTap: () {},
        ),
        ChoiceChip(label: '$low azalan', semanticLabel: 'Azalan $low ürünü göster', onTap: () {}),
        ChoiceChip(
          label: '$untargeted hedefsiz',
          semanticLabel: 'Hedefi olmayan $untargeted ürünü göster',
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
      const ChatMessage(text: 'kıymayı derin dondurucuya taşı', speaker: ChatSpeaker.user),
      _buildShortageCard(),
      const ChatMessage(text: 'neyim eksik', speaker: ChatSpeaker.user),
      _buildPlacementCard(),
      _buildWriteCard(),
      const ChatMessage(text: 'Süt stoğa yazıldı.'),
      const ChatMessage(text: '1 adet süt aldım', speaker: ChatSpeaker.user),
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
      children: const [
        WDiv(
          className: 'flex flex-row justify-end',
          child: MSSkeleton(shape: SkeletonShape.text, width: 140, height: 34),
        ),
        WDiv(
          className: 'flex flex-row justify-start',
          child: MSSkeleton(shape: SkeletonShape.text, width: 220, height: 16),
        ),
        WText('Daha eski mesajlar yükleniyor', className: 'text-xs text-fg-muted'),
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
      label: 'Stoğa yazıldı',
      action: MSButton(
        onPressed: () {},
        intent: ButtonIntent.ghost,
        size: ButtonSize.sm,
        child: const WText('Geri al'),
      ),
      children: const [
        MovementRow(
          reason: 'Satın alma',
          deltaAmount: 1,
          delta: '+1',
          unit: 'adet',
          // Product and surface, which is what criterion 4 asks a feed entry to carry.
          // The timestamp was here too and truncated the product name off the end, which
          // is the one part that cannot be dropped.
          meta: 'Pınar Süt Tam Yağlı 1 lt · asistan',
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
      label: 'Nereye',
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 py-1',
          children: [
            if (affinity != null)
              ChoiceChip(
                label: resolveLocationLabel(affinity.$1) ?? 'Buzdolabı',
                evidence: '${affinity.$2} kez',
                isSuggested: true,
                semanticLabel: '${resolveLocationLabel(affinity.$1)} konumuna koy',
              ),
            const ChoiceChip(label: 'Kiler', semanticLabel: 'Kiler konumuna koy'),
            // An explicit skip, because every chip has to be a real answer and "I will do
            // it later" is one of them.
            const ChoiceChip(label: 'Sonra', semanticLabel: 'Konumu şimdi belirleme'),
          ],
        ),
      ],
    );
  }

  /// The answer to "neyim eksik", rendered as the shopping list itself.
  Widget _buildShortageCard() {
    return SectionCard(
      label: 'Alınacak',
      count: '${pendingLines.length} ürün',
      // The way out to the real screen. Criterion 7 says every capability here is also
      // reachable in inventory mode, and a link is how that stops being a promise.
      action: MSButton(
        onPressed: () {},
        intent: ButtonIntent.ghost,
        size: ButtonSize.sm,
        child: const WText('Listeyi aç'),
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
      label: 'Onay bekliyor',
      children: [
        const MovementRow(
          reason: 'Konumlar arası taşıma',
          deltaAmount: -1,
          delta: '-1',
          unit: 'kg',
          meta: 'Kıyma · Mutfak › Buzdolabı',
          direction: MovementDirection.outbound,
        ),
        const MovementRow(
          reason: 'Konumlar arası taşıma',
          deltaAmount: 1,
          delta: '+1',
          unit: 'kg',
          meta: 'Kıyma · Mutfak › Derin dondurucu',
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
                child: const WText('Onayla'),
              ),
            ),
            WDiv(
              className: 'flex-1 min-w-0',
              child: MSButton(
                onPressed: () {},
                intent: ButtonIntent.ghost,
                fullWidth: true,
                className: 'justify-center',
                child: const WText('Reddet'),
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
      label: 'Örnek',
      children: [
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 py-1',
          children: [
            ChoiceChip(
              label: '1 adet süt aldım',
              semanticLabel: 'Bir adet süt aldım yaz',
              onTap: () {},
            ),
            ChoiceChip(
              label: 'yarım kilo kıyma aldım',
              semanticLabel: 'Yarım kilo kıyma aldım yaz',
              onTap: () {},
            ),
            ChoiceChip(label: 'neyim eksik', semanticLabel: 'Neyim eksik diye sor', onTap: () {}),
            ChoiceChip(
              label: 'buzdolabında ne var',
              semanticLabel: 'Buzdolabında ne var diye sor',
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
          className: 'flex flex-row items-center gap-2',
          children: [
            _composerButton(_cameraIcon, 'Fotoğraf çek', ButtonIntent.ghost),
            _composerButton(_micIcon, 'Sesle yaz', ButtonIntent.ghost),
            const WDiv(
              className: 'flex-1 min-w-0',
              child: MSInput(
                // Card tone so an enabled field does not read as disabled, and an explicit
                // height so it matches the buttons beside it.
                className: 'bg-surface-container h-11',
                placeholder: 'Ne aldınız, ne soracaksınız',
              ),
            ),
            _composerButton(_sendIcon, 'Gönder', ButtonIntent.primary),
          ],
        ),
        // Voice is the one input that confirms before committing, and saying so here is
        // cheaper than surprising someone with a confirmation card they did not expect.
        WText('Sesle yazılanlar kaydedilmeden önce onaylanır', className: 'text-xs text-fg-muted'),
      ],
    );
  }

  /// One composer button, at the row's shared height.
  Widget _composerButton(IconData icon, String label, ButtonIntent intent) {
    return MSButton(
      onPressed: () {},
      intent: intent,
      className: 'h-11 w-11 justify-center',
      semanticLabel: label,
      child: WIcon(icon, className: 'size-5'),
    );
  }
}
