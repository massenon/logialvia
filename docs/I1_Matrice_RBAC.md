# I1 — Matrice des Droits d'Accès (RBAC)

Référence structurelle : tables `ROLES`, `UTILISATEURS`, `PERMISSIONS_ROLE` (Doc D1). Règle métier : BR-ADM-001.

**⚠️ Corrigé (Doc K4 §8/§10)** : la version précédente de ce document supposait 4 rôles, dont un rôle `comptable` distinct. **Confirmé faux** par la lecture directe de `assets/js/sidebar.js` réel, dont le commentaire d'en-tête déclare explicitement : *"3 roles RBAC (pas 4)... aucun role comptable"*. Ce document est corrigé pour refléter les **3 rôles réels**.

---

## 1. Rôles du Système (3 rôles réels, confirmés)

Repris du sélecteur de test déjà présent dans le prototype (`#rbac-role-switcher`) — en production, le rôle est déterminé par le compte connecté, pas sélectionné manuellement (Doc F1, note sur le sélecteur de test). Confirmé également par les libellés réels de la modale "Ajouter un Utilisateur" (Doc F8 Onglet 3) : *"Agent de Vente"* / *"Agent d'Élevage"* — la divergence de nommage signalée dans Doc F8 est donc résolue : ce sont bien les libellés d'affichage des rôles `caissier`/`animalier`, pas des rôles distincts.

| Rôle technique | Libellé affiché | Description |
|---|---|---|
| `admin` | Administratrice | Accès complet, y compris administration (rôles, modules actifs, sauvegarde, **Comptabilité**) |
| `caissier` | Agent de Vente | Accès Ventes/POS, Clients, consultation Stocks — pas d'accès Comptabilité ni Élevage |
| `animalier` | Agent d'Élevage | Accès complet au module Élevage (5 fiches, Couvoir, Soins, Paramètres Élevage) — pas d'accès Comptabilité ni Ventes |

**Aucun rôle `comptable` distinct n'existe.** La totalité de la section Comptabilité (Doc F6) est réservée à `admin` uniquement — confirmé par `sidebar.js` réel : `data-role-group="admin"` sur l'intégralité du groupe de navigation COMPTABILITÉ, sans exception.

---

## 2. Matrice Complète — Rôle × Module

| Module / Écran | admin | caissier | animalier |
|---|:---:|:---:|:---:|
| Dashboard Principal | ✅ | ✅ | ✅ |
| Dashboard Élevage | ✅ | ❌ | ✅ |
| Cycle Couveuse | ✅ | ❌ | ✅ |
| Fiches d'Élevage (Goliaths, Pintades, + modules activables) | ✅ | ❌ | ✅ |
| Calendrier de Soins | ✅ | ❌ | ✅ |
| Paramètres Élevage | ✅ | ❌ | ✅ (limité, voir §3) |
| Ventes | ✅ | ✅ | ❌ |
| Clients et Créances | ✅ | ✅ | ❌ |
| Achats & Commandes | ✅ | ❌ | ❌ |
| Fournisseurs | ✅ | ❌ | ❌ |
| Saisie des Dépenses | ✅ | ❌ | ❌ |
| Gestion des Stocks | ✅ | ❌ | ❌ |
| Catalogue Produits | ✅ | ❌ | ❌ |
| Comptabilité (Hub, Journal, Grand Livre, Balance, États Financiers, Clôture, Analytique) | ✅ | ❌ | ❌ |
| Paramètres Généraux | ✅ | ❌ | ❌ |
| Rapports & Exports | ✅ | ❌ | ❌ |
| Mon Profil | ✅ | ✅ | ✅ |
| Aide & Contact | ✅ | ✅ | ✅ |

**Légende** : ✅ accès complet (lecture+écriture) · ❌ accès refusé (redirection, FRS-ADM-01)

**Différence structurelle avec la version précédente de ce document** : aucun état "👁️ lecture seule" n'existe dans le système réel — `sidebar.js` ne montre aucune section partiellement grisée par rôle, seulement des sections **entièrement visibles ou entièrement masquées** (`data-role-group`). La distinction accès-complet/lecture-seule que la version précédente inventait pour `comptable` n'a pas de fondement dans le fichier réel — retirée.

---

## 3. Nuance — "Accès Limité" sur Paramètres Élevage pour Animalier

L'Animalier peut modifier les seuils d'alerte et rations normatives (usage quotidien, Doc F3 Onglet Rationnement), mais **pas** activer/désactiver une filière entière (Doc I2) — cette dernière action reste réservée à `admin` uniquement, car elle a un impact structurel sur toute la navigation, pas seulement sur un paramètre de saisie.

---

## 4. Implémentation Technique

```dart
class PermissionService {
  static const Map<String, Set<String>> _routesAutoriseesParRole = {
    'admin': {'*'}, // acces total
    'caissier': {'/dashboard', '/ventes', '/clients', '/profil', '/aide', '/contact'},
    'animalier': {'/dashboard', '/elevage/dashboard', '/elevage/couveuse', '/elevage/goliaths',
      '/elevage/pintades', '/elevage/poissons-chats', '/elevage/lapins', '/elevage/poulets-pondeuses',
      '/elevage/soins', '/parametres/elevage', '/profil', '/aide', '/contact'},
  };

  static bool estAutorise(String role, String route) {
    final routes = _routesAutoriseesParRole[role];
    if (routes == null) return false;
    return routes.contains('*') || routes.contains(route);
  }
}
```

**Correspondance directe avec `sidebar.js` réel** : ce dictionnaire Dart doit rester la traduction fidèle des attributs `data-role-group="..."` déjà présents dans `sidebar.js` — toute modification de la navigation web (ajout/retrait d'un groupe, changement de `data-role-group`) doit être répercutée dans `_routesAutoriseesParRole`, jamais laissée diverger (source unique de vérité pour les permissions, Strict Avoid §12).

Branché dans le `redirect` de `go_router` (Doc E3 §6).

### Boutons d'Action — Masqués par Rôle, pas par un État "Lecture Seule" Générique
Contrairement à la version précédente de ce document, il n'existe pas de "mode lecture seule" transversal à masquer bouton par bouton — un rôle qui n'a pas accès à un module n'atteint simplement jamais cet écran (route absente de son ensemble autorisé, §2). Le seul cas de masquage conditionnel de bouton reste Doc I2 §3 (activation de module réservée à `admin`), au sein d'un écran par ailleurs accessible.
