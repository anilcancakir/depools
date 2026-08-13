<?php

namespace App\Enums;

/**
 * How one model attempt ended.
 *
 * Closed, with a CHECK constraint on `ai_usage_events.outcome` behind it. The five are distinct
 * because each answers a different operational question, and collapsing any two of them would make a
 * report `monetization.md` needs unanswerable:
 *
 * - [Succeeded] is the only one that produced a card.
 * - [SchemaInvalid] is a 200 that our schema rejected. OpenRouter counts it as a success and bills it,
 *   which is exactly why our own loop exists on top of its fallback array (D77): the provider cannot
 *   see this failure.
 * - [ProviderError] is a timeout, a 5xx or a transport failure. Distinguishing it from the one above
 *   is what tells us whether a model is unreliable or merely bad at following a schema.
 * - [Refused] is the model declining. It costs tokens and produces nothing, and a rate of it rising
 *   means a prompt is tripping a moderation filter rather than an outage.
 * - [NoCredit] never reached a provider at all, so it has no tokens and no cost. It is recorded
 *   anyway, because "this tenant is hitting their limit" is the single most actionable usage fact and
 *   it is invisible if a declined action leaves no row.
 */
enum AiOutcome: string
{
    case Succeeded = 'succeeded';
    case SchemaInvalid = 'schema_invalid';
    case ProviderError = 'provider_error';
    case Refused = 'refused';
    case NoCredit = 'no_credit';
}
