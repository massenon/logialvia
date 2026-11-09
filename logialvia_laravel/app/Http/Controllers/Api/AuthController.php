<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Poste;
use App\Services\AuthentificationService;
use App\Services\PostesService;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;

class AuthController extends Controller
{
    public function __construct(
        private readonly AuthentificationService $authentification,
        private readonly PostesService $postes,
    ) {}

    /**
     * Appairage = connexion. Un jeton par poste, nomme d'apres l'identifiant du
     * poste (UUID), jamais d'apres le nom de la machine.
     */
    public function login(Request $request): JsonResponse
    {
        $donnees = $request->validate([
            'identifiant' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string'],
            'device_name' => ['required', 'uuid'],
        ], [
            'identifiant.required' => "L'identifiant est obligatoire.",
            'password.required' => 'Le mot de passe est obligatoire.',
            'device_name.required' => "L'identifiant du poste est obligatoire.",
            'device_name.uuid' => "L'identifiant du poste doit être un UUID.",
        ]);

        $resultat = $this->authentification->verifier(
            $donnees['identifiant'],
            $donnees['password'],
            $request->ip(),
            ['device_name' => $donnees['device_name']],
        );

        if ($resultat['utilisateur'] === null) {
            return response()->json(['message' => $resultat['erreur']], $resultat['statut']);
        }

        $utilisateur = $resultat['utilisateur'];
        $appairage = $this->postes->appairer($utilisateur, $donnees['device_name']);

        Audit::enregistrer('api.login', $utilisateur, [
            'poste' => $appairage['poste']->code,
            'device_id' => $donnees['device_name'],
        ]);

        return response()->json([
            'token' => $appairage['jeton'],
            'expires_at' => $appairage['expire_le']->toIso8601String(),
            'user' => $this->profil($utilisateur),
            'must_change_password' => $utilisateur->must_change_password,
            'poste' => ['id' => $appairage['poste']->id, 'code' => $appairage['poste']->code],
        ]);
    }

    /** Test de connexion du poste (« Tester la connexion ») : qui suis-je, quel poste. */
    public function me(Request $request): JsonResponse
    {
        $utilisateur = $request->user();
        $poste = Poste::query()->where('device_id', $utilisateur->currentAccessToken()->name)->first();

        return response()->json([
            'user' => $this->profil($utilisateur),
            'must_change_password' => $utilisateur->must_change_password,
            'poste' => $poste ? ['id' => $poste->id, 'code' => $poste->code] : null,
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Déconnecté.']);
    }

    /** Changement du mot de passe : seule action permise avec un mot de passe temporaire. */
    public function changerMotDePasse(Request $request): JsonResponse
    {
        $donnees = $request->validate([
            'mot_de_passe_actuel' => ['required', 'string'],
            'nouveau_mot_de_passe' => [
                'required', 'string', 'confirmed',
                fn (string $attribut, mixed $valeur, \Closure $echec) => ($m = \App\Support\RegleMotDePasse::erreur((string) $valeur)) !== null ? $echec($m) : null,
            ],
        ], [
            'mot_de_passe_actuel.required' => 'Le mot de passe actuel est obligatoire.',
            'nouveau_mot_de_passe.required' => 'Le nouveau mot de passe est obligatoire.',
            'nouveau_mot_de_passe.confirmed' => 'La confirmation ne correspond pas.',
        ]);

        $utilisateur = $request->user();

        if (! Hash::check($donnees['mot_de_passe_actuel'], $utilisateur->password)) {
            return response()->json(['message' => 'Le mot de passe actuel est incorrect.'], 422);
        }

        $utilisateur->forceFill([
            'password' => $donnees['nouveau_mot_de_passe'],
            'must_change_password' => false,
        ])->save();

        // Les autres postes de cet utilisateur devront se reconnecter.
        $courant = $utilisateur->currentAccessToken()->id;
        $utilisateur->tokens()->where('id', '!=', $courant)->delete();

        Audit::enregistrer('api.mot_de_passe_change', $utilisateur);

        return response()->json(['message' => 'Mot de passe modifié.']);
    }

    /** @return array<string, mixed> */
    private function profil($utilisateur): array
    {
        return [
            'id' => $utilisateur->id,
            'name' => $utilisateur->name,
            'username' => $utilisateur->username,
            'email' => $utilisateur->email,
            'roles' => $utilisateur->getRoleNames()->values()->all(),
        ];
    }
}
