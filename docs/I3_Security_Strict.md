# I3 — SECURITY_STRICT — Sécurité de l'Application Flutter Desktop

Ce document couvre l'ensemble des mesures de sécurité applicables à LogiALVIA : protection contre les failles courantes, validation des données et gestion des fichiers, configuration de l'environnement de production, protection des données locales, et traçabilité (Audit Logs, Security Logs). Chaque mesure est ancrée dans le contexte réel du projet — **application desktop locale, hors-ligne par défaut, sans serveur web** (Doc C1, Doc B1 §7) — avec un principe strict : aucune mesure n'est incluse par habitude ou par généricité ; chaque section précise explicitement si elle s'applique réellement à ce contexte, et pourquoi.

---

## 1. Protection contre les Failles Courantes

### Injection SQL — **S'applique, déjà couvert, renforcé ici**
La protection contre l'injection SQL repose sur l'**API typée de Drift**, qui construit des requêtes préparées par nature. Déjà posé en Strict Avoid §1 et NFRS-SEC-02 — rappelé ici comme référence centrale de sécurité :
```dart
// ✅ Toujours — Drift echappe et type automatiquement
await (db.select(db.ventes)..where((v) => v.client.equals(nomSaisi))).get();

// ❌ Jamais — construction de requete par concatenation de chaine
await db.customSelect("SELECT * FROM ventes WHERE client = '$nomSaisi'").get();
```
**Contrôle** : `grep -r "customSelect\|customStatement" lib/` avant chaque livraison — toute occurrence doit être justifiée explicitement en revue de code, jamais silencieuse.

### Failles XSS — **N/A dans le cas général, s'applique à 1 endroit précis**
Flutter ne rend pas de HTML par défaut (`Text()` affiche du texte brut, aucune interprétation de balises) — la classe de vulnérabilité XSS telle que définie pour le web n'existe structurellement pas dans l'app elle-même.

**Seule zone à risque réelle identifiée** : la génération PDF (Doc E9) insère des données utilisateur (nom client, libellés) dans un document structuré. Bien que `pw.Text()` du package `pdf` échappe correctement le contenu (pas d'injection de structure PDF possible via texte), toute future fonctionnalité qui générerait du HTML à partir de données utilisateur (ex. export HTML d'un rapport, non prévu actuellement) devrait échapper explicitement — **à surveiller si une telle fonctionnalité est ajoutée plus tard, non pertinent pour le périmètre actuel**.

### Attaques CSRF — **N/A, structurellement impossible**
Le CSRF exploite un navigateur qui envoie des requêtes authentifiées vers un serveur web à l'insu de l'utilisateur. LogiALVIA Flutter Desktop n'a ni serveur web recevant des requêtes cross-origin, ni session HTTP, ni navigateur impliqué dans son fonctionnement normal (Doc B1 §6, hors périmètre : pas de backend serveur pour cette phase). **Aucune mesure équivalente à `@csrf` n'est nécessaire ni pertinente.**

---

## 2. Validation des Données et Gestion des Fichiers

### Validation des Données — **S'applique, déjà couvert, référence croisée**
Les validateurs sont déjà spécifiés en **Doc E6** (règles par type de champ, `FormulaireJournalierValidator`, `PosValidator`). Rappel du principe : **toute donnée entrante est validée avant persistance**, jamais après — cohérent avec G2 §4.

### Envoi de Fichiers — **S'applique, nouveau détail nécessaire**
Fonctionnalités concernées : upload Logo/Favicon (Doc F8 Onglet 2), export/import de sauvegarde de base (Doc F8, `exporterSauvegarde()`).

**Règle stricte, jamais de confiance dans le fichier fourni par l'utilisateur** :
```dart
class FichierUploadValidator {
  static const _typesAutorises = {'png', 'jpg', 'jpeg', 'ico'};
  static const _tailleMaxOctets = 2 * 1024 * 1024; // 2 Mo, coherent avec Doc F8

  static Future<String?> valider(File fichier) async {
    final extension = fichier.path.split('.').last.toLowerCase();
    if (!_typesAutorises.contains(extension)) {
      return 'Format non autorisé. Formats acceptés : ${_typesAutorises.join(', ')}.';
    }
    final taille = await fichier.length();
    if (taille > _tailleMaxOctets) {
      return 'Fichier trop volumineux (max ${_tailleMaxOctets ~/ 1024 ~/ 1024} Mo).';
    }
    // Verification du contenu reel, pas seulement l'extension du nom de fichier
    final bytes = await fichier.openRead(0, 8).first;
    if (!_signatureCorrespondAuType(bytes, extension)) {
      return 'Le contenu du fichier ne correspond pas à son extension.';
    }
    return null; // valide
  }
}
```

**Règle de nommage à l'enregistrement** : jamais le nom de fichier original de l'utilisateur — toujours un nom généré (UUID + extension validée) :
```dart
final nomGenere = '${const Uuid().v4()}.$extension';
await fichierSource.copy(path.join(dossierAssets, nomGenere));
```

---

## 3. Configuration de l'Environnement — Mode Release

### Suppression des Informations de Débogage en Production
Aucune information de débogage ne doit fuiter dans un build `--release` distribué à l'utilisateur final.

```dart
// Regle stricte : tout log/print conditionne par kDebugMode
if (kDebugMode) {
  debugPrint('Détail technique interne: $erreurComplete');
}
// L'utilisateur final ne voit JAMAIS la stack trace brute — toujours un message
// traduit et generique (Doc K1 §8, pattern Resultat<T>/Echec deja pose)
showAppToast(context, 'Une erreur est survenue. Veuillez réessayer.', type: ToastType.error);
```

**Contrôle avant toute distribution** : `flutter build windows --release` (jamais `--debug` distribué), vérifier l'absence du bandeau "DEBUG" (déjà supprimé automatiquement en release par Flutter, mais à confirmer visuellement une fois avant chaque publication).

### Secrets Applicatifs
Aucun secret en dur dans le code source (rappel direct de Strict Avoid §13, déjà posé). S'applique concrètement si/quand une fonctionnalité future utilise des identifiants (SMTP, Doc F8 §Configuration Email ; passerelle Mobile Money réelle, hors périmètre actuel B1 §6) :
```dart
// ❌ Jamais
const smtpPassword = 'monMotDePasse123';

// ✅ Toujours — stockage securise natif, jamais en clair dans le code ni dans la base SQLite
final storage = FlutterSecureStorage();
await storage.write(key: 'smtp_password', value: motDePasseSaisi);
```
Package `flutter_secure_storage` à ajouter (Doc K3) si une fonctionnalité de ce type est confirmée.

### "HTTPS" — **N/A par défaut, s'applique conditionnellement**
Aucun appel réseau obligatoire au fonctionnement de l'application (Doc B1 §7, hors-ligne first). **Si** une fonctionnalité future ajoute un appel réseau (envoi SMTP, synchronisation optionnelle), celui-ci doit obligatoirement utiliser une connexion chiffrée (TLS pour SMTP, HTTPS pour toute API) — non pertinent tant qu'aucun appel réseau n'existe dans le périmètre actuel.

---

## 4. Sécurisation des Données Locales (Équivalent Réel de "Cookies" et "En-têtes HTTP")

Les concepts de "cookies sécurisés" et "en-têtes HTTP (CSP, X-Frame-Options)" **n'ont pas d'équivalent direct** — ce sont des mécanismes de protection du navigateur/serveur web, absents d'une app desktop. Le véritable point d'attention équivalent, pour une application à **persistance locale**, est la **protection du fichier de base de données SQLite lui-même** :

### Protection du Fichier de Base de Données
| Risque réel | Mesure |
|---|---|
| Accès en lecture par un autre programme sur le même poste | Fichier stocké dans le dossier applicatif protégé du système (`getApplicationSupportDirectory()`, pas un dossier partagé/public) |
| Vol du fichier `.db` (clé USB, copie) exposant toutes les données en clair | Évaluer `sqlcipher_flutter_libs` (chiffrement au repos) avant mise en production si les données sont jugées suffisamment sensibles (chiffre d'affaires, salaires si module RH futur) — déjà signalé en Strict Avoid §1, confirmé ici comme mesure à trancher explicitement, pas encore décidée |
| Copie de sauvegarde exportée (Doc F8, `exporterSauvegarde()`) laissée sur un support non protégé | Avertir explicitement l'utilisateur au moment de l'export (`AppToast` ou modale) que le fichier exporté n'est pas chiffré et doit être stocké de façon sécurisée |

### SEO (Métadonnées, JSON-LD, Sitemap) — **Entièrement N/A**
Ces mécanismes concernent l'indexation par des moteurs de recherche d'un site web public. LogiALVIA Flutter Desktop n'a pas de pages web indexables — **aucune action requise, ce point ne s'applique pas à ce projet**.

---

## 5. Architecture — Déjà Couvert

"Clean Architecture (DDD simplifié)" est déjà intégralement spécifié en **Doc C1** — pas dupliqué ici.

---

## 6. RBAC, Audit Logs et Security Logs

### RBAC — Déjà Couvert
Matrice complète déjà spécifiée en **Doc I1** — pas dupliquée ici.

### Audit Logs — Renforcement d'une Règle Déjà Posée (BR-ADM-003)
BR-ADM-003 (Doc B6) posait déjà le principe général de journalisation des suppressions. La table `AUDIT_LOGS` correspondante est intégrée dans **Doc D1** (dictionnaire de données, source unique — Strict Avoid §12).

**Actions à journaliser systématiquement** (au-delà des suppressions déjà couvertes) : clôture périodique/annuelle (Doc F6 §6), déclôture exceptionnelle (BR-CPT-006), modification du rôle d'un utilisateur, activation/désactivation d'un module (Doc I2), connexion/déconnexion.

### Security Logs — Nouveau, Traduction du Concept "Tentatives d'Intrusion"
Pour une application desktop sans exposition réseau publique, la notion de "tentative d'intrusion" se traduit différemment du contexte web d'origine. Table `SECURITY_LOGS` intégrée dans **Doc D1**.

**Événements à consigner** :
| Événement | Déclenchement |
|---|---|
| `echec_connexion` | Identifiant/mot de passe incorrect (Doc F1 Écran 3) — après 5 échecs consécutifs pour un même identifiant sur une courte période, envisager un verrouillage temporaire du compte |
| `acces_route_non_autorise` | Navigation directe vers une route hors permission RBAC (Doc I1) — signal qu'un utilisateur tente de contourner la navigation normale |
| `tentative_modification_verrouillee` | Tentative d'écriture sur une écriture comptable verrouillée (BR-CPT-001/006) en dehors du mécanisme de déclôture officiel |

**Écran de consultation** : réservé au rôle `admin` (Doc I1 §3), accessible depuis Paramètres Généraux (Doc F8) ou un écran dédié si le volume le justifie — `DataTable` standard (Doc E4), filtrable par type d'événement et par date.

---

## Récapitulatif — Portée de Chaque Mesure

| Mesure de sécurité | Statut dans LogiALVIA Flutter |
|---|---|
| Injection SQL | ✅ S'applique — Drift typé |
| XSS | ⚠️ Largement N/A — 1 zone de vigilance (PDF) |
| CSRF | ❌ N/A structurel |
| Validation des données | ✅ S'applique — Doc E6 |
| Envoi de fichiers | ✅ S'applique — spécification ci-dessus |
| Build Release / suppression des logs de debug | ✅ S'applique — `kDebugMode`/build release |
| Secrets applicatifs | ✅ S'applique conditionnellement — `flutter_secure_storage` si secrets futurs |
| Connexions chiffrées (TLS/HTTPS) | ⚠️ N/A par défaut, conditionnel si réseau futur |
| Cookies sécurisés | ❌ N/A structurel |
| En-têtes HTTP (CSP, etc.) | ❌ N/A structurel |
| SEO | ❌ Entièrement N/A |
| Architecture Clean/DDD | ✅ Déjà couvert — Doc C1 |
| RBAC | ✅ Déjà couvert — Doc I1 |
| Audit Logs | ✅ S'applique — renforcé ci-dessus |
| Security Logs | ✅ Nouveau concept traduit ci-dessus |
