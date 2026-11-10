<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** Journal d'audit du serveur : tout geste sensible y laisse une trace. */
    public function up(): void
    {
        Schema::create('audit_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('action', 80)->index();
            // Sans cle etrangere : une trace survit a la suppression de son auteur.
            $table->uuid('utilisateur_id')->nullable()->index();
            $table->string('identifiant', 255)->nullable();
            $table->json('detail')->nullable();
            $table->string('ip', 45)->nullable();
            $table->timestamp('created_at')->useCurrent();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
    }
};
