<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Enums\MovementReason;
use App\Enums\MovementSource;
use App\Http\Controllers\Controller;
use App\Models\Location;
use App\Models\Product;
use App\Services\StockWriter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * The three things that happen to stock.
 *
 * ### These are events, not a resource
 *
 * There is no `PATCH /products/{id}` setting a quantity, and its absence is the API's most
 * important shape. Offering one would invite the client to believe stock is a number it owns, which
 * is the mental model the ledger exists to replace: a client that sets 5 has destroyed the answer
 * to how it got there, what was wasted, and what expires first.
 *
 * ### A domain refusal is 422, not 500
 *
 * `StockWriter` throws when there is not enough stock, which is a fact about the tenant's shelf
 * rather than a fault in the server. It comes back as a validation-shaped error so the client can
 * show it next to the field the user typed into, the same as any other rejected input.
 */
final class StockController extends Controller
{
    public function __construct(private readonly StockWriter $writer) {}

    public function receive(Request $request): JsonResponse
    {
        $data = $this->validateMove($request, [
            'expires_at' => ['nullable', 'date'],
            'lot_code' => ['nullable', 'string', 'max:64'],
        ]);

        [$product, $location] = $this->resolve($data);

        return $this->guard(function () use ($product, $location, $data, $request): JsonResponse {
            $movement = $this->writer->receive(
                $product,
                $location,
                (float) $data['quantity'],
                $this->source($data),
                $data['expires_at'] ?? null,
                $data['lot_code'] ?? null,
                $request->user()->getKey(),
                $data['idempotency_key'] ?? null,
            );

            return response()->json(['data' => ['movement_id' => $movement->getKey()]], 201);
        });
    }

    public function consume(Request $request): JsonResponse
    {
        $data = $this->validateMove($request, [
            // Only the outflow reasons. `purchase` here would let a client write an inbound
            // movement through the outbound endpoint and skip lot creation entirely.
            'reason' => ['nullable', Rule::enum(MovementReason::class)],
        ]);

        [$product, $location] = $this->resolve($data);

        $reason = isset($data['reason'])
            ? MovementReason::from($data['reason'])
            : MovementReason::Consumption;

        return $this->guard(function () use ($product, $location, $data, $reason, $request): JsonResponse {
            $written = $this->writer->consume(
                $product,
                $location,
                (float) $data['quantity'],
                $reason,
                $this->source($data),
                $request->user()->getKey(),
            );

            // A list, because a consumption spanning two lots is two ledger facts and the client's
            // undo has to reverse both.
            return response()->json(['data' => ['movement_ids' => $written->pluck('id')]], 201);
        });
    }

    public function transfer(Request $request): JsonResponse
    {
        $data = $request->validate([
            'product_id' => ['required'],
            'from_location_id' => ['required'],
            'to_location_id' => ['required', 'different:from_location_id'],
            'quantity' => ['required', 'numeric', 'gt:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],
        ]);

        $product = Product::query()->findOrFail($data['product_id']);
        $from = Location::query()->findOrFail($data['from_location_id']);
        $to = Location::query()->findOrFail($data['to_location_id']);

        return $this->guard(function () use ($product, $from, $to, $data, $request): JsonResponse {
            [$out, $in] = $this->writer->transfer(
                $product,
                $from,
                $to,
                (float) $data['quantity'],
                $this->source($data),
                $request->user()->getKey(),
            );

            return response()->json([
                'data' => ['movement_ids' => [$out->getKey(), $in->getKey()]],
            ], 201);
        });
    }

    /**
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private function validateMove(Request $request, array $extra = []): array
    {
        return $request->validate(array_merge([
            'product_id' => ['required'],
            'location_id' => ['required'],
            'quantity' => ['required', 'numeric', 'gt:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],
            'idempotency_key' => ['nullable', 'string', 'max:64'],
        ], $extra));
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array{0: Product, 1: Location}
     */
    private function resolve(array $data): array
    {
        // Both go through the scoped models, so an identifier belonging to another tenant is a 404
        // here exactly as it is on a read.
        return [
            Product::query()->findOrFail($data['product_id']),
            Location::query()->findOrFail($data['location_id']),
        ];
    }

    /** @param array<string, mixed> $data */
    private function source(array $data): MovementSource
    {
        return isset($data['source'])
            ? MovementSource::from($data['source'])
            : MovementSource::Manual;
    }

    /**
     * Turn a domain refusal into a 422 the client can render beside a field.
     */
    private function guard(callable $write): JsonResponse
    {
        try {
            return $write();
        } catch (RuntimeException $e) {
            // Deliberately narrow: only the writer's own refusals are translated. Anything else
            // propagates, because a swallowed exception here would report success for a write that
            // did not happen, which on a ledger is the worst possible failure.
            return response()->json([
                'message' => $e->getMessage(),
                'errors' => ['quantity' => [$e->getMessage()]],
            ], 422);
        }
    }
}
