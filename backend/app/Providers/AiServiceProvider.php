<?php

namespace App\Providers;

use App\Ai\Contracts\IconSuggestionGateway;
use App\Ai\Contracts\ModelCaller;
use App\Ai\Contracts\ProductEnrichmentGateway;
use App\Ai\Contracts\ReceiptExtractionGateway;
use App\Ai\LaravelAi\LaravelAiIconSuggestionGateway;
use App\Ai\LaravelAi\LaravelAiModelCaller;
use App\Ai\LaravelAi\LaravelAiProductEnrichmentGateway;
use App\Ai\LaravelAi\LaravelAiReceiptExtractionGateway;
use Illuminate\Support\ServiceProvider;

/**
 * Binds each gateway contract to its implementation.
 *
 * Its own provider rather than three more lines in `AppServiceProvider`, because this is the list
 * `architecture.md` says a `laravel/ai` breaking change has to touch and nothing else: keeping it in
 * one file is what makes that claim checkable instead of aspirational.
 *
 * Every binding is `bind` rather than `singleton`. A gateway holds no state between calls, and a
 * singleton would outlive a test's swap of it inside the same process.
 */
final class AiServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->bind(ModelCaller::class, LaravelAiModelCaller::class);
        $this->app->bind(ProductEnrichmentGateway::class, LaravelAiProductEnrichmentGateway::class);
        $this->app->bind(IconSuggestionGateway::class, LaravelAiIconSuggestionGateway::class);
        $this->app->bind(ReceiptExtractionGateway::class, LaravelAiReceiptExtractionGateway::class);
    }
}
