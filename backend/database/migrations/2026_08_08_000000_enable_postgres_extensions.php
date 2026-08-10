<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The PostgreSQL extensions this schema rests on, and one function it needs.
 *
 * Runs before every other inventory migration, because the columns and indexes they declare do not
 * exist without it. Dated `000000` for that reason.
 *
 * ### Why each one is here
 *
 * - `vector` (pgvector) carries the embedding column the resolution cascade's second step searches
 *   (D75). Version 0.8.2 locally.
 * - `pg_trgm` is what actually matches a truncated thermal-receipt line. `PNR SUT 1LT` is not a
 *   prefix, a suffix or a stem of `Pınar Süt 1 lt`; it is a bag of overlapping character triples,
 *   which is what trigram similarity measures.
 * - `unaccent` folds the diacritics (D82).
 *
 * There is deliberately no `tsvector` anywhere and therefore no text-search configuration to set up.
 * Stemmed full-text search belongs to Meilisearch (D74). Worth knowing rather than rediscovering:
 * PostgreSQL DOES ship a Turkish stemmer (`pg_catalog.turkish` and `turkish_stem` are both present
 * on this instance), so that split is a choice about typo tolerance and instant ranking, not a
 * workaround for a missing stemmer.
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        DB::statement('CREATE EXTENSION IF NOT EXISTS vector');
        DB::statement('CREATE EXTENSION IF NOT EXISTS pg_trgm');
        DB::statement('CREATE EXTENSION IF NOT EXISTS unaccent');

        $this->createImmutableUnaccent();
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement('DROP FUNCTION IF EXISTS depools_normalize(text)');

        // The extensions themselves are NOT dropped. Another migration's column may still be typed
        // `vector`, and dropping an extension takes its types with it, so a partial rollback would
        // fail in a way that reads as a corrupt migration state rather than as a dependency.
    }

    /**
     * The normalisation function every matching key is built from.
     *
     * ### Why a wrapper function exists at all
     *
     * `unaccent()` is not marked IMMUTABLE, because its dictionary can be replaced at runtime and
     * PostgreSQL will not promise a stable answer. Both generated columns and index expressions
     * require IMMUTABLE. So the standard community answer, which is what this is, is a thin wrapper
     * that declares the promise Postgres will not make on its own.
     *
     * **That promise is real and has a cost: changing the `unaccent` rules invalidates every index
     * built on this function, and the fix is a REINDEX rather than an error message.** Nothing warns
     * you. This comment is the warning.
     *
     * `unaccent('unaccent', ...)` names the dictionary explicitly rather than relying on the default
     * lookup, which is what makes the function safe to call from a context with no search_path.
     *
     * ### What it folds, and the one that is not obvious
     *
     * `ı→i`, `ş→s`, `ğ→g`, `ü→u`, `ö→o`, `ç→c`. The i/ı fold is a real loss of a distinction Turkish
     * actually makes, accepted because this is a MATCHING key and never a displayed value: `name`
     * keeps the original. D82 records the reasoning, and the short version is that a user without a
     * Turkish keyboard, a user in a hurry, and a receipt printer that emits no diacritics are the
     * three inputs the cascade most has to work on.
     */
    private function createImmutableUnaccent(): void
    {
        DB::statement(<<<'SQL'
            CREATE OR REPLACE FUNCTION depools_normalize(input text)
            RETURNS text
            AS $$
                SELECT lower(unaccent('unaccent', input))
            $$
            LANGUAGE sql
            IMMUTABLE
            PARALLEL SAFE
            STRICT
        SQL);
    }
};
