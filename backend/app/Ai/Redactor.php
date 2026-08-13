<?php

namespace App\Ai;

/**
 * Masks what does not need to leave the process, before anything reaches a model.
 *
 * `legal-and-privacy.md` makes this architectural rather than optional: sending personal data to a
 * model hosted outside Turkey is a cross-border transfer under KVKK Article 9, and the same content
 * crosses GDPR Chapter V at the same moment. The mitigation it names first is a redaction step that
 * runs before any content reaches a model, and running it inside the gateway is what makes it
 * impossible for a caller to forget.
 *
 * ### It over-masks on purpose
 *
 * A product name containing a 16-digit run is not a product name, and a description containing an
 * email address does not need it to be translated. So the patterns below are deliberately eager: the
 * cost of masking one legitimate long number is a slightly worse translation, and the cost of missing
 * one card fragment is a reportable transfer. That asymmetry is the whole argument.
 *
 * What it does NOT do is detect KVKK Article 6 special categories (health, biometric, union
 * membership). Those are handled by not soliciting them, which `legal-and-privacy.md` states as a
 * documented position rather than a filter, because a regex cannot recognise a health condition.
 */
final class Redactor
{
    private const MASK = '[…]';

    /**
     * The rules, in the order they run. Longest-matching first, so a card number is not partly eaten
     * by the phone rule before the card rule sees it.
     *
     * @var array<string, string>
     */
    private const PATTERNS = [
        // Card-like runs: 13 to 19 digits, optionally grouped by spaces or hyphens. Before the
        // national-identifier rule, which would otherwise consume the first 11 digits of a card.
        'card' => '/\b(?:\d[ -]?){13,19}\b/',
        // Turkish national identifier: exactly 11 digits, never starting with zero.
        'tckn' => '/\b[1-9]\d{10}\b/',
        'email' => '/[\w.+-]+@[\w-]+\.[\w.-]+/',
        // International and Turkish phone shapes. Requires a leading + or 0, so a bare 10-digit run
        // (a plausible product code) is left alone.
        'phone' => '/(?:\+\d{1,3}[ -]?)?0?\(?\d{3}\)?[ -]?\d{3}[ -]?\d{2}[ -]?\d{2}\b/',
    ];

    public function text(?string $value): ?string
    {
        if ($value === null || trim($value) === '') {
            return $value;
        }

        foreach (self::PATTERNS as $pattern) {
            $value = preg_replace($pattern, self::MASK, $value) ?? $value;
        }

        return $value;
    }

    /**
     * A card with every field masked.
     *
     * The name is masked too. It is the field least likely to carry personal data and the one whose
     * masking is most visible, and it is still masked, because a rule with an exception is a rule
     * somebody will extend the exception of.
     */
    public function card(ProductCard $card): ProductCard
    {
        return new ProductCard(
            name: (string) $this->text($card->name),
            brand: $this->text($card->brand),
            description: $this->text($card->description),
        );
    }
}
