# 05 — Logique de Calcul des Formulaires de Saisie Journalière

**Document le plus critique de cette documentation.** Ces formules ont déjà été débogées, corrigées et validées numériquement côté HTML/JS dans ce projet — les traduire fidèlement en Dart est le point de plus haut risque de régression silencieuse (un écran qui "a l'air" correct visuellement mais calcule faux).

---

## 1. Principe général — vrai suivi par catégorie (les 5 fiches)

### Le bug historique à ne JAMAIS réintroduire

Toutes les fiches utilisaient initialement une **répartition en pourcentage fixe**, déconnectée des saisies réelles :

```dart
// ❌ NE JAMAIS FAIRE CECI — bug corrige et documente
final effCat1 = (effectifFinal * 0.35).round();
final effCat2 = (effectifFinal * 0.35).round();
final effCat3 = effectifFinal - effCat1 - effCat2;
```

Ce pattern casse le lien entre une mortalité saisie sur une catégorie précise et son effet réel — une mort sur "Reproducteur" faisait bouger toutes les catégories proportionnellement, jamais uniquement Reproducteur.

### La règle correcte — 3 mouvements, chacun sur SA catégorie

Pour chaque fiche, il existe 3 sous-effectifs réels (`effCat1Day`, `effCat2Day`, `effCat3Day` — 4 pour Pondeuses), calculés ainsi **chaque jour** :

```dart
class CalculEffectifParCategorie {
  /// [prevCatX] = sous-effectif de la categorie X au jour precedent
  /// (ou repartition initiale au jour 1 — voir section 2)
  static int categorieJeune({
    required int prevCat,
    required int achat,
    required int ne,
    required int mortCat,
    required int donCat,
  }) {
    // Achat et Naissances alimentent TOUJOURS la categorie la plus jeune.
    return (prevCat + achat + ne - mortCat - donCat).clamp(0, 999999);
  }

  static int categorieCommercialisee({
    required int prevCat,
    required int vente,
    required int mortCat,
    required int donCat,
  }) {
    // La Vente est TOUJOURS deduite de la categorie commercialisee
    // (Lapin de Chair, Poulet, Porc Marchand, Pondeuse selon l'espece).
    return (prevCat - vente - mortCat - donCat).clamp(0, 999999);
  }

  static int categorieIntermediaireOuAdulte({
    required int prevCat,
    required int mortCat,
    required int donCat,
  }) {
    // Categorie qui ne recoit ni achat/ne, ni vente directement
    // (ex: Reproducteur pour Lapins/Goliaths/Pintades).
    return (prevCat - mortCat - donCat).clamp(0, 999999);
  }
}
```

**Règle absolue** : chaque catégorie ne perd QUE ses propres `mort`/`don` saisis pour cette catégorie précise — jamais une part proportionnelle des morts/dons d'une autre catégorie.

---

## 2. Répartition Initiale (Jour 1 du mois / première ouverture)

Avant tout historique, la répartition initiale suit un ratio de départ (35% / 35% / reste, sauf Pondeuses — voir section 4) :

```dart
int effReproInitial(int baseEffectif) => (baseEffectif * 0.35).round();
int effCommercialiseInitial(int baseEffectif) => (baseEffectif * 0.35).round();
int effJeuneInitial(int baseEffectif) =>
    baseEffectif - effReproInitial(baseEffectif) - effCommercialiseInitial(baseEffectif);
```

> Ce ratio 35/35/30 est arbitraire (donnée de démonstration), **pas une règle métier réelle de la ferme** — à confirmer/ajuster si des données réelles d'inventaire par catégorie existent, sans quoi le conserver tel quel pour rester fidèle au prototype de référence.

---

## 3. Détail par Fiche

| Fiche | Cat. Jeune (reçoit achat+né) | Cat. Commercialisée (déduite de vente) | Cat. Intermédiaire/Adulte |
|---|---|---|---|
| Goliaths | Poussin | Goliathau | Mature |
| Pintades | Poussin | Pintadau | Mature |
| Lapins | Lapereau | Chair | Reproducteur |
| Poulets (onglet) | Poussin | Poulette | Adulte |
| Poissons-Chats | Alevin | Juvenile | Mature |

Pour ces 5 cas (à 3 catégories), le calcul journalier complet est :

```dart
class FicheJournaliereCalculator {
  ({int effJeune, int effCommercialise, int effAdulte}) calculerJour({
    required int prevJeune, required int prevCommercialise, required int prevAdulte,
    required int achat, required int ne, required int vente,
    required int mortJeune, required int mortCommercialise, required int mortAdulte,
    required int donJeune, required int donCommercialise, required int donAdulte,
  }) {
    final effJeune = (prevJeune + achat + ne - mortJeune - donJeune).clamp(0, 999999);
    final effCommercialise = (prevCommercialise - vente - mortCommercialise - donCommercialise).clamp(0, 999999);
    final effAdulte = (prevAdulte - mortAdulte - donAdulte).clamp(0, 999999);
    return (effJeune: effJeune, effCommercialise: effCommercialise, effAdulte: effAdulte);
  }

  /// Effectif total du jour = simple somme, verification de coherence uniquement
  int effectifTotal({required int achat, required int ne, required int vente,
      required int totalMorts, required int totalDons, required int prevEffectifTotal}) {
    return (prevEffectifTotal + achat + ne - totalMorts - vente - totalDons).clamp(0, 999999);
  }
}
```

**Taux de mortalité du jour** (identique sur les 5 fiches) :
```dart
double tauxMortaliteJour(int totalMorts, int prevEffectifTotal) =>
    prevEffectifTotal > 0 ? (totalMorts / prevEffectifTotal) * 100 : 0.0;
```

---

## 4. Cas Particulier — Pondeuses (4 catégories + suivi Stock d'Œufs)

La fiche Pondeuses (2ᵉ onglet de `fiche-poulets-pondeuses.html`) a **4 catégories réelles**, alignées sur les 4 lignes du tableau de Rationnement — pas 3 :

| Catégorie | Reçoit achat | Déduite de vente |
|---|---|---|
| Poussin Ponte | ✅ | — |
| Poussin Croissance | — | — |
| Poulette | — | — |
| Pondeuse | — | ✅ |

```dart
({int poussinPonte, int croissance, int poulette, int pondeuse}) calculerJourPondeuses({
  required int prevPoussinPonte, required int prevCroissance,
  required int prevPoulette, required int prevPondeuse,
  required int achat, required int vente,
  required int mortPoussinPonte, required int mortCroissance,
  required int mortPoulette, required int mortPondeuse,
  required int donPoussinPonte, required int donCroissance,
  required int donPoulette, required int donPondeuse,
}) {
  return (
    poussinPonte: (prevPoussinPonte + achat - mortPoussinPonte - donPoussinPonte).clamp(0, 999999),
    croissance: (prevCroissance - mortCroissance - donCroissance).clamp(0, 999999),
    poulette: (prevPoulette - mortPoulette - donPoulette).clamp(0, 999999),
    pondeuse: (prevPondeuse - vente - mortPondeuse - donPondeuse).clamp(0, 999999),
  );
}
```

### Rationnement Pondeuses — le total DOIT sommer les 4 catégories

Bug historique corrigé : le total "Provende Servie du Jour" ne sommait autrefois que la catégorie Pondeuse. Règle correcte :

```dart
int provendeTotal({
  required int effPoussinPonte, required int effCroissance,
  required int effPoulette, required int effPondeuse,
}) {
  const g30 = 30, g60 = 60, g80 = 80, g110 = 110; // grammes/jour par stade
  return effPoussinPonte * g30 + effCroissance * g60 +
         effPoulette * g80 + effPondeuse * g110;
}
```

### Stock d'Œufs — SRH / TS / Stock Final (le bug le plus grave trouvé sur ce projet)

**Règle exacte, vérifiée numériquement sur 9 jours avec sorties variables** :
> Stock Hier (SRH) du jour J+1 = Stock Final du jour J — **pas** Total Stock (TS) du jour J. Ces deux valeurs ne coïncident que les jours sans sortie de plateaux (`OS = 0`).

```dart
class StockOeufsCalculator {
  /// A appeler pour CHAQUE jour, dans l'ordre chronologique.
  /// Le piege historique : reassigner l'accumulateur AVANT de l'avoir stocke
  /// comme "ouverture" du jour — corrige ici en capturant explicitement.
  ({int srh, int ts, int osOeufs, int stockFinal}) calculerJour({
    required int srhOuverture,      // = stockFinal du jour precedent (ou seed initial)
    required int oeufsPondus,
    required int oeufsCasses,
    required int osPlateaux,        // sorties ventes, en plateaux de 30
  }) {
    final comm = (oeufsPondus - oeufsCasses).clamp(0, 999999);
    final ts = comm + srhOuverture;
    final osOeufs = osPlateaux * 30;
    final stockFinal = (ts - osOeufs).clamp(0, 999999);
    return (srh: srhOuverture, ts: ts, osOeufs: osOeufs, stockFinal: stockFinal);
  }
}
```

⚠️ **Point de vigilance n°1** : dans l'implémentation JS originale, un premier bug faisait que `srhAcc` était réassigné à sa nouvelle valeur AVANT d'être stocké comme `srh` du jour — chaque jour affichait donc son propre stock final au lieu du stock hérité de la veille. Le code Dart ci-dessus évite structurellement ce piège en nommant explicitement `srhOuverture` comme paramètre séparé, capturé avant tout calcul.

⚠️ **Point de vigilance n°2**, plus grave : la sauvegarde manuelle d'un jour doit **toujours** recalculer et persister `srh`/`ts`/`stockFinal`, jamais seulement l'effectif — sans quoi l'affichage retombe sur une valeur de repli arbitraire qui efface silencieusement l'historique réel du stock. La cascade vers les jours suivants déjà saisis doit elle aussi recalculer ces 3 champs, pas seulement l'effectif.

---

## 5. Cascade — Modification d'un Jour Passé

Quand l'utilisateur modifie/sauvegarde un jour `J` déjà saisi, **tous les jours suivants déjà enregistrés** (`isRecorded == true`) doivent être recalculés en cascade, car leur base de départ (`J-1`) a changé :

```dart
Future<void> recalculerCascade({
  required String espece,
  required DateTime jourModifie,
  required FicheRepository repo,
}) async {
  var jourCourant = jourModifie.add(const Duration(days: 1));
  while (true) {
    final jour = await repo.getJour(espece, jourCourant);
    if (jour == null || !jour.isRecorded) break; // s'arrete au premier jour non saisi

    final precedent = await repo.getJour(espece, jourCourant.subtract(const Duration(days: 1)));
    final nouveauCalcul = FicheJournaliereCalculator().calculerJour(
      prevJeune: precedent!.effCat1Day, /* ... */
      achat: jour.achat, ne: jour.ne, vente: jour.vente,
      mortJeune: jour.mortCat1, /* ... */
    );
    await repo.mettreAJourJour(jour.copyWith(/* nouveauCalcul */));

    jourCourant = jourCourant.add(const Duration(days: 1));
  }
}
```

Pour Pondeuses, cette même cascade doit **en plus** recalculer SRH/TS/Stock Final (section 4), pas seulement les 4 sous-effectifs.

---

## 6. Champ Effectif — toujours en lecture seule

Dans les 5 fiches, le champ Effectif (formulaire journalier **et** tableau des 31 jours) n'est **jamais** une saisie manuelle — c'est systématiquement une valeur calculée et affichée en lecture seule (`readOnly: true` / `enabled: false` sur le `TextField` Flutter équivalent). Toute tentative de le rendre éditable réintroduit un risque d'incohérence avec les Morts/Dons/Achats saisis.

---

## 7. Ventes (POS) réelles — répercussion sur les fiches

Le champ "Ventes (POS)" du formulaire journalier de chaque fiche doit refléter **la somme** de :
1. La valeur de démonstration déjà modélisée pour ce jour (données historiques du prototype)
2. Les ventes réelles enregistrées via l'écran `ventes.html`/`ventes_screen.dart` pour cette espèce et cette date exacte (`FicheVentesJour`, Doc 04)

```dart
Future<int> venteDuJourAffichee({
  required String espece, required DateTime date,
  required int venteDemoModelisee, required FicheRepository repo,
}) async {
  final venteReelle = await repo.getVenteDuJour(espece, date);
  return venteDemoModelisee + venteReelle;
}
```
