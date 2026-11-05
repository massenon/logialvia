# I2 — Gestion des Modules Actifs

Référence structurelle : table `MODULES_ACTIFS` (Doc D1). Règle métier : BR-ADM-002.

---

## 1. Principe

L'exploitation ALLMANY ET COMPAGNIE peut faire évoluer ses filières dans le temps (arrêt temporaire d'une production, ajout futur d'une nouvelle espèce). Le système doit permettre d'**activer/désactiver** un module sans jamais supprimer les données historiques déjà associées.

## 2. Modules Concernés (Élevage) et Modules Structurels

**Correction appliquée suite à l'audit réel de `parametres-generaux.html`** (Doc F8) — cette section a été révisée, la version précédente supposait à tort que toutes les filières étaient désactivables et actives par défaut.

| Module | Identifiant technique réel | Désactivable | État par défaut |
|---|---|---|---|
| Goliaths | `goliaths` | ❌ **Non — activité principale confirmée, verrouillé** (`checked disabled` dans le HTML source) | Toujours actif |
| Pintades | `pintades` | ❌ **Non — idem** | Toujours actif |
| Poissons-Chats | `pisciculture` | ✅ Oui | **Désactivé par défaut** — "fiche construite, paramètres non confirmés" |
| Poulets/Pondeuses | `aviculture_classique` | ✅ Oui | **Désactivé par défaut** — "filière dupliquée" |
| Lapins | `cuniculture` | ✅ Oui | **Désactivé par défaut** — "copie fidèle" |
| Comptabilité Analytique | — | ✅ (si confirmé nécessaire) | Non vérifié dans le HTML audité |
| Ventes, Stocks, Comptabilité (Journal/Plan/Bilan) | — | ❌ — non désactivables, cœur du système | Toujours actif |

**Implication de conception** : Goliaths et Pintades ne doivent **jamais** apparaître dans l'écran de gestion des modules comme des bascules interactives — ils sont affichés à titre informatif uniquement (`disabled`), reflet visuel de leur statut permanent.

## 3. Effet de la Désactivation

1. L'entrée correspondante disparaît de la navigation (Doc E3) — sidebar et dashboard élevage (Doc F2)
2. Les routes correspondantes deviennent inaccessibles même par saisie directe d'URL (`redirect` dans `go_router` vérifie `MODULES_ACTIFS.isActif` en plus de la permission RBAC, Doc I1)
3. **Les données historiques restent intactes en base** (`FICHE_JOURNEE`, `FICHE_VENTES_JOUR` de l'espèce désactivée ne sont jamais supprimées)
4. Les KPIs consolidés (Dashboard Élevage, Doc F2) excluent les filières désactivées du calcul en cours, mais les rapports historiques (Doc F7) peuvent toujours inclure une période où le module était actif

## 4. Réactivation

La réactivation d'un module restaure immédiatement l'accès à l'historique déjà présent — aucune ressaisie nécessaire, aucune perte de continuité dans le tableau mensuel (le premier jour saisi après réactivation reprend la cascade là où elle s'était arrêtée, BR-ELV-006).

## 5. Implémentation

```dart
class ModulesActifsProvider extends ChangeNotifier {
  // CORRECTIF : Goliaths et Pintades sont exclus de cette map — ils n'ont pas
  // d'entree MODULES_ACTIFS car ils ne sont jamais desactivables (Doc F8).
  // Seuls les 3 modules reellement bascules ont un etat par defaut a FALSE,
  // pas TRUE — corrige suite a l'audit reel de parametres-generaux.html.
  Map<String, bool> _etatModules = {
    'pisciculture': false,
    'aviculture_classique': false,
    'cuniculture': false,
  };

  bool estActif(String moduleId) {
    if (moduleId == 'goliaths' || moduleId == 'pintades') return true; // toujours actif, non conditionnel
    return _etatModules[moduleId] ?? false; // desactive par defaut si absent, pas actif par defaut
  }

  Future<void> basculer(String moduleId, bool actif) async {
    if (moduleId == 'goliaths' || moduleId == 'pintades') return; // no-op, jamais modifiable
    await repository.setModuleActif(moduleId, actif);
    _etatModules[moduleId] = actif;
    notifyListeners(); // rafraichit immediatement la navigation (Doc E3)
  }
}
```

### Vérification combinée dans le routeur (RBAC + Module Actif)

```dart
GoRoute(
  path: '/elevage/poissons-chats',
  redirect: (context, state) {
    final role = context.read<AuthProvider>().currentRole;
    final modulesProvider = context.read<ModulesActifsProvider>();
    if (!PermissionService.estAutorise(role, '/elevage/poissons-chats')) return '/dashboard';
    if (!modulesProvider.estActif('pisciculture')) return '/elevage/dashboard'; // identifiant technique reel
    return null;
  },
  builder: (_, __) => const FichePoissonsChatsScreen(),
),
```

## 6. Écran de Gestion (rattaché à F8, Paramètres Généraux ou une section dédiée de Paramètres Élevage F3)

`DataTable` simplifiée : Module, Statut (toggle `Switch`), Description. Réservé au rôle `admin` uniquement (Doc I1 §3).
