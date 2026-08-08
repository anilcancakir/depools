<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Which surface created a movement.
 *
 * Kept apart from `reason` because the two answer different questions: `reason` is what happened to
 * the stock, this is how the app found out. A purchase can arrive by receipt photo, by barcode, or
 * by someone typing it, and the accuracy of each differs enough to be worth measuring.
 */
enum MovementSource: string
{
    case Manual = 'manual';
    case Receipt = 'receipt';
    case Invoice = 'invoice';
    case Barcode = 'barcode';
    case Photo = 'photo';
    case Assistant = 'assistant';
    case Mcp = 'mcp';
    case Import = 'import';
    case ShoppingList = 'shopping_list';
}
