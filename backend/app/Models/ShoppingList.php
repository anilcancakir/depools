<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use App\Services\ShoppingListGenerator;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * The tenant's one open shopping list.
 *
 * D99: a single rolling list, because a user holds one mental "things to get" rather than a document
 * per trip. The row exists almost entirely to carry `generated_at`, and the migration records why
 * that could not be a column on `teams`.
 *
 * @see ShoppingListGenerator
 */
final class ShoppingList extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /** @var list<string> */
    protected $fillable = ['team_id', 'generated_at'];

    protected function casts(): array
    {
        return ['generated_at' => 'datetime'];
    }

    public function items(): HasMany
    {
        return $this->hasMany(ShoppingListItem::class);
    }
}
