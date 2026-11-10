<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Postes appaires. Un poste = un identifiant UUID tire UNE fois a sa premiere
     * ouverture (`device_id`, qui est aussi le NOM de son jeton Sanctum) et un
     * CODE court attribue ici (`P1`, `P2`...) qui prefixe ses pieces (DV-21 :
     * `V-P2-2026-001`). Le code est stable : se reconnecter, ou etre revoque puis
     * reappaire, ne le change jamais. Une reinstallation = un NOUVEAU poste.
     */
    public function up(): void
    {
        Schema::create('postes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->unique();
            $table->string('code', 10)->unique();
            $table->foreignUuid('dernier_utilisateur_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('appaire_le')->nullable();
            $table->timestamp('dernier_contact_le')->nullable();
            $table->timestamp('revoque_le')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('postes');
    }
};
