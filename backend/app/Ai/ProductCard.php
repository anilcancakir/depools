<?php

namespace App\Ai;

/**
 * The three fields a product card carries across the model boundary, and nothing else.
 *
 * Deliberately NOT `ProductCandidate`. That one carries `source`, `confidence`, `productId` and
 * `contributable`, which are facts about where a row came from and who may share it: they are our
 * business, not the model's, and `legal-and-privacy.md` asks that what leaves the process be only
 * what the feature requires. A shape with nothing extra in it is the cheapest way to guarantee that.
 */
final readonly class ProductCard
{
    public function __construct(
        public string $name,
        public ?string $brand = null,
        public ?string $description = null,
    ) {}

    /**
     * @return array<string, string|null>
     */
    public function toArray(): array
    {
        return [
            'name' => $this->name,
            'brand' => $this->brand,
            'description' => $this->description,
        ];
    }
}
