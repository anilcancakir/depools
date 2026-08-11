<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use App\Models\Concerns\NormalisesName;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * One of a tenant's cross-cutting labels, canonical per tenant.
 *
 * A tag is what a single-parent category cannot express. A product carries exactly one
 * `product_category_id`, so `kahvaltı`, `soğuk zincir` and `sarf` have nowhere to live in the taxonomy:
 * they cut across it. `bakliyat` is the counter-example and it belongs in the taxonomy rather than here.
 *
 * ### Canonical, because a model writes these
 *
 * `ai-enrichment.md` lists tags among the fields enrichment GENERATES, so the failure mode is not a user
 * typing carelessly, it is a generator producing `kahvaltı` once and `Kahvaltı` next time. The unique
 * index on `(team_id, name_normalized)` means the second spelling RESOLVES to the first row rather than
 * competing with it, which is the same argument D89 made for the cascade's aliases.
 *
 * [findOrCreateFor] is the only sanctioned way in, for that reason.
 */
final class Tag extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;
    use NormalisesName;

    /** @var list<string> */
    protected $fillable = ['name'];

    /**
     * The canonical row for a name, creating it only when the fold is genuinely new.
     *
     * Matching on `name_normalized` rather than on `name` is the whole mechanism: without it, two
     * spellings become two tags, the filter chip row shows both, and a user has to tick both to get their
     * own shelf back.
     *
     * The DISPLAY name of an existing tag is left alone. First spelling wins, because a generator's later
     * capitalisation is not a reason to rewrite what a user has been looking at.
     */
    public static function findOrCreateFor(string $name): self
    {
        $normalized = self::normaliseName($name);

        $existing = self::query()->where('name_normalized', $normalized)->first();

        if ($existing !== null) {
            return $existing;
        }

        return self::create(['name' => $name]);
    }

    /**
     * The products carrying this tag.
     */
    public function products(): BelongsToMany
    {
        return $this->belongsToMany(Product::class, 'product_tag')
            ->using(ProductTag::class)
            ->withTimestamps();
    }
}
