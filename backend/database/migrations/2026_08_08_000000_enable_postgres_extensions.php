<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The PostgreSQL extensions this schema rests on.
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
 *
 * ### What is deliberately NOT here
 *
 * **No `unaccent`, and no function.** An earlier version of this migration created a
 * `depools_normalize(text)` wrapper declared IMMUTABLE so a generated column and an index expression
 * could call it. Anılcan's constraint removed that whole shape: computation lives in Laravel, not in
 * the database. So `name_normalized` is a plain column that PHP writes, `pg_trgm` indexes it as an
 * ordinary column, and Postgres computes nothing.
 *
 * That is genuinely less machinery: no extension, no function, and no IMMUTABLE promise to break
 * when a transliteration table changes. What it costs is stated where the column is written rather
 * than here, because the cost is drift: a generated column cannot disagree with `name`, and a
 * PHP-written one can.
 *
 * **No `tsvector` and no text-search configuration.** Stemmed full-text belongs to Meilisearch
 * (D74). Worth knowing rather than rediscovering: PostgreSQL DOES ship `pg_catalog.turkish` and
 * `turkish_stem`, so that split is a choice about typo tolerance and instant ranking, not a
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
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        // The extensions are NOT dropped. Another migration's column may still be typed `vector`,
        // and dropping an extension takes its types with it, so a partial rollback would fail in a
        // way that reads as a corrupt migration state rather than as a dependency.
    }
};
