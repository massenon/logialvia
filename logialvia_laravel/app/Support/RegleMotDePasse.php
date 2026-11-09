<?php

namespace App\Support;

/**
 * Regle de complexite du mot de passe — IDENTIQUE au poste Flutter
 * (`CompteViewModel.erreurComplexite`, `compte_view_model.dart`) : 8 caracteres minimum,
 * une majuscule, un chiffre. Memes messages. Une seule regle pour le web, l'API et le seeder.
 */
class RegleMotDePasse
{
    public const INDICATION = 'Min. 8 caractères, 1 majuscule, 1 chiffre';

    /** @return string|null Le message du poste, ou `null` si le mot de passe convient. */
    public static function erreur(string $motDePasse): ?string
    {
        if (mb_strlen($motDePasse) < 8) {
            return 'Le mot de passe doit compter au moins 8 caractères.';
        }
        if (! preg_match('/[A-ZÀ-Þ]/u', $motDePasse)) {
            return 'Le mot de passe doit contenir au moins une majuscule.';
        }
        if (! preg_match('/\d/', $motDePasse)) {
            return 'Le mot de passe doit contenir au moins un chiffre.';
        }

        return null;
    }
}
