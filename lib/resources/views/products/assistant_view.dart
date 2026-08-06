import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageScaffold, MSButton, ButtonIntent, ButtonSize, MSInput;

import '../../../ui/components/chat_message/chat_message.dart';
import '../../../ui/components/choice_chip/choice_chip.dart';
import '../../../ui/components/movement_row/movement_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/components/shopping_row/shopping_row.dart';
import '../../../ui/components/stat_card/stat_card.dart';
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
    return MSPageScaffold(
      title: 'Asistan',
      subtitle: 'Yarı otomatik · stok değişikliği onay ister',
      children: [
        _buildOverview(),
        if (hasTranscript) ..._buildTranscript() else _buildOpeners(),
        _buildComposer(),
      ],
    );
  }

  /// The three figures a transcript cannot give.
  ///
  /// **Derived, never typed.** Each one counts the same fixtures the product list and the
  /// shopping list count, so the assistant's headline cannot say "6 azalan" while the
  /// shopping list shows eight. An assistant that contradicts the app it sits in is worse
  /// than no assistant, and this is the cheapest possible guard against it.
  Widget _buildOverview() {
    final int expiring = productFixtures.where((p) => p.isExpiringSoon || p.isExpired).length;
    final int low = pendingLines.length;
    // Products with no target level. A first pass counted products with no CATEGORY, which
    // rendered "0 ürün": true, and useless. This one is the honest third figure because it
    // explains the app's own silence: without a target there is nothing to fall below, so
    // these products can never reach the shopping list however low they get.
    final int untargeted = productFixtures.where((p) => p.parLevel == null).length;

    return SectionCard(
      label: 'Durum',
      children: [
        WDiv(
          // `items-start`, not `items-stretch`. This Row sits in a scrolling Column and
          // has no height to stretch to; the rule is in the anti-pattern table and this
          // is the second time it has been broken, so it is worth the comment.
          className: 'flex flex-row items-start gap-3 py-1',
          children: [
            WDiv(
              className: 'flex-1 min-w-0',
              // Short enough to stay on one line at phone width. The labels wrapped
              // unevenly at three tiles, which put the three values at three different
              // heights; `items-stretch` would have levelled them and is banned here for
              // a better reason, so the labels get shorter instead.
              child: StatCard(label: 'Tarihi yakın', value: '$expiring ürün'),
            ),
            WDiv(
              className: 'flex-1 min-w-0',
              child: StatCard(label: 'Azalan', value: '$low ürün'),
            ),
            WDiv(
              className: 'flex-1 min-w-0',
              child: StatCard(label: 'Hedefi yok', value: '$untargeted ürün'),
            ),
          ],
        ),
      ],
    );
  }

  /// The exchange, oldest first, newest above the composer.
  List<Widget> _buildTranscript() {
    return [
      const ChatMessage(text: '1 adet süt aldım', speaker: ChatSpeaker.user),
      const ChatMessage(text: 'Süt stoğa yazıldı.'),
      _buildWriteCard(),
      _buildPlacementCard(),
      const ChatMessage(text: 'neyim eksik', speaker: ChatSpeaker.user),
      _buildShortageCard(),
      const ChatMessage(text: 'kıymayı derin dondurucuya taşı', speaker: ChatSpeaker.user),
      _buildApprovalCard(),
    ];
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
  /// All three sit on one row at every width. A camera on a laptop is a worse camera, not an
  /// absent one, and hiding it by platform is what DESIGN.md's layout rule forbids.
  Widget _buildComposer() {
    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        WDiv(
          className: 'flex flex-row items-center gap-2',
          children: [
            MSButton(
              onPressed: () {},
              intent: ButtonIntent.ghost,
              className: 'min-h-11 min-w-11 justify-center',
              semanticLabel: 'Fotoğraf çek',
              child: const WIcon(_cameraIcon, className: 'size-5'),
            ),
            MSButton(
              onPressed: () {},
              intent: ButtonIntent.ghost,
              className: 'min-h-11 min-w-11 justify-center',
              semanticLabel: 'Sesle yaz',
              child: const WIcon(_micIcon, className: 'size-5'),
            ),
            const WDiv(
              className: 'flex-1 min-w-0',
              child: MSInput(placeholder: 'Ne aldınız, ne soracaksınız'),
            ),
            MSButton(
              onPressed: () {},
              className: 'min-h-11 min-w-11 justify-center',
              semanticLabel: 'Gönder',
              child: const WIcon(_sendIcon, className: 'size-5'),
            ),
          ],
        ),
        // Voice is the one input that confirms before committing, and saying so here is
        // cheaper than surprising someone with a confirmation card they did not expect.
        WText('Sesle yazılanlar kaydedilmeden önce onaylanır', className: 'text-xs text-fg-muted'),
      ],
    );
  }
}
