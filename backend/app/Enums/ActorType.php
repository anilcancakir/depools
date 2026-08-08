<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Who wrote a movement.
 *
 * Separate from `actor_id` so an automated write is legible without a join, and so the assistant's
 * writes can be listed and undone as a group. D10's automation levels rest on this: a user
 * reviewing what the app did on its own filters the ledger by [Assistant] and [Mcp].
 */
enum ActorType: string
{
    case User = 'user';
    case Assistant = 'assistant';
    case McpClient = 'mcp_client';
    case System = 'system';
}
