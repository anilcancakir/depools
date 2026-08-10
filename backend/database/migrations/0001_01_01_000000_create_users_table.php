<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Laravel's own users migration, made uuid-aware.
 *
 * ### Why this file is edited at all
 *
 * Every other migration here routes its keys through `MigrationHelper`, so flipping
 * `magic-starter.use_uuids` switches them together. This one is Laravel's default and the starter
 * never published over it, so it hardcoded integers in two places: `users.id` via `$table->id()`,
 * and `sessions.user_id` via `foreignId()`.
 *
 * That made the flip a silent trap rather than a config change. `User` uses
 * `ConditionallyUsesUuids`, so with uuids enabled the model generates a uuid string and inserts it
 * into a bigint column. PostgreSQL rejects that outright. SQLite, which the suite used to run on,
 * is dynamically typed and would have stored it, which is the second and independent argument
 * behind D72.
 *
 * `password_reset_tokens` is keyed on the email address and needs nothing.
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            MigrationHelper::primaryKey($table);
            $table->string('name');
            $table->string('email')->unique();
            $table->timestamp('email_verified_at')->nullable();
            $table->string('password');
            $table->rememberToken();
            $table->timestamps();
        });

        Schema::create('password_reset_tokens', function (Blueprint $table) {
            $table->string('email')->primary();
            $table->string('token');
            $table->timestamp('created_at')->nullable();
        });

        Schema::create('sessions', function (Blueprint $table) {
            $table->string('id')->primary();
            // Deliberately NOT `->constrained()`: Laravel ships this column unconstrained because a
            // session may outlive the row it points at, and adding a foreign key here would make
            // pruning order matter for no gain. The type still has to match `users.id`.
            MigrationHelper::foreignKey($table, 'user_id')->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->longText('payload');
            $table->integer('last_activity')->index();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('users');
        Schema::dropIfExists('password_reset_tokens');
        Schema::dropIfExists('sessions');
    }
};
