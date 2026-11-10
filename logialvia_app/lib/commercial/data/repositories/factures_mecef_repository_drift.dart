import 'package:drift/drift.dart';

import '../../../administration/data/repositories/preferences_poste_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../domain/entities/facture_mecef.dart';

/// Accès aux factures normalisées MeCeF.
///
/// ## Deux invariants tenus ici, et nulle part ailleurs
///
/// 1. **Une facture émise ne se modifie pas.** Il n'existe volontairement
///    aucune méthode de mise à jour des lignes ou des montants. Corriger une
///    facture, c'est émettre un avoir — c'est la règle fiscale, et c'est aussi
///    la seule qui laisse une trace vérifiable.
/// 2. **Le total d'un avoir est celui de la facture qu'il corrige.** Un avoir
///    partiel se saisit ligne à ligne ; un avoir total reprend l'intégralité.
///    Dans les deux cas les montants viennent de la pièce d'origine, jamais du
///    catalogue du jour.
class FacturesMecefRepositoryDrift {
  FacturesMecefRepositoryDrift(this._db);

  final AppDatabase _db;

  // ------------------------------------------------------------- lecture

  Future<List<GroupeTaxe>> groupesTaxe() async {
    final lignes = await (_db.select(
      _db.groupesTaxe,
    )..orderBy([(g) => OrderingTerm(expression: g.ordre)])).get();
    return [
      for (final g in lignes)
        GroupeTaxe(
          code: g.code,
          libelle: g.libelle,
          taux: g.taux,
          ordre: g.ordre,
        ),
    ];
  }

  Future<List<FactureMecef>> toutes() async {
    final entetes =
        await (_db.select(_db.factures)..orderBy([
              (f) => OrderingTerm(
                expression: f.dateFacture,
                mode: OrderingMode.desc,
              ),
              (f) => OrderingTerm(expression: f.ref, mode: OrderingMode.desc),
            ]))
            .get();
    if (entetes.isEmpty) return const [];

    final lignes = await _db.select(_db.lignesFacture).get();
    final parFacture = <String, List<LigneFactureRow>>{};
    for (final l in lignes) {
      parFacture.putIfAbsent(l.factureRef, () => []).add(l);
    }

    return [
      for (final e in entetes) _versEntite(e, parFacture[e.ref] ?? const []),
    ];
  }

  Future<FactureMecef?> parReference(String reference) async {
    final e = await (_db.select(
      _db.factures,
    )..where((f) => f.ref.equals(reference))).getSingleOrNull();
    if (e == null) return null;
    final lignes = await (_db.select(
      _db.lignesFacture,
    )..where((l) => l.factureRef.equals(reference))).get();
    return _versEntite(e, lignes);
  }

  /// La facture émise pour une vente, s'il y en a une.
  Future<FactureMecef?> pourVente(String venteRef) async {
    final e =
        await (_db.select(_db.factures)..where(
              (f) =>
                  f.venteRef.equals(venteRef) &
                  f.type.equals(TypeFacture.vente.code),
            ))
            .getSingleOrNull();
    if (e == null) return null;
    final lignes = await (_db.select(
      _db.lignesFacture,
    )..where((l) => l.factureRef.equals(e.ref))).get();
    return _versEntite(e, lignes);
  }

  /// Les ventes qui n'ont pas encore de facture.
  Future<List<VenteRow>> ventesSansFacture() async {
    final facturees =
        (await (_db.selectOnly(_db.factures)
                  ..addColumns([_db.factures.venteRef])
                  ..where(_db.factures.type.equals(TypeFacture.vente.code)))
                .get())
            .map((l) => l.read(_db.factures.venteRef))
            .whereType<String>()
            .toSet();

    final ventes =
        await (_db.select(_db.ventes)
              ..where((v) => v.status.isNotValue('Annulée'))
              ..orderBy([
                (v) => OrderingTerm(
                  expression: v.dateVente,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return [
      for (final v in ventes)
        if (!facturees.contains(v.ref)) v,
    ];
  }

  // ------------------------------------------------------------- écriture

  /// Émet une facture de vente à partir d'une vente encaissée.
  ///
  /// Les prix du panier sont des **montants négociés toutes taxes comprises** —
  /// c'est ainsi que la caisse fonctionne. Ils sont donc ramenés hors taxe
  /// selon le groupe du produit : facturer le montant négocié en HT puis y
  /// ajouter la taxe ferait payer au client plus que ce qu'il a réglé.
  Future<FactureMecef> emettrePourVente({
    required String venteRef,
    String? clientIfu,
    String? clientAdresse,
    DateTime? date,
  }) async {
    final vente = await (_db.select(
      _db.ventes,
    )..where((v) => v.ref.equals(venteRef))).getSingleOrNull();
    if (vente == null) {
      throw StateError('Vente $venteRef introuvable.');
    }
    if (vente.status == 'Annulée') {
      throw StateError(
        'La vente $venteRef est annulée : elle ne peut pas être facturée.',
      );
    }
    final dejaFaite = await pourVente(venteRef);
    if (dejaFaite != null) {
      throw StateError(
        'La vente $venteRef porte déjà la facture ${dejaFaite.reference}. '
        'Pour la corriger, émettez un avoir.',
      );
    }

    final lignesVente = await (_db.select(
      _db.lignesVente,
    )..where((l) => l.venteRef.equals(venteRef))).get();
    final groupes = {for (final g in await groupesTaxe()) g.code: g};

    final lignes = <LigneFacture>[];
    for (final l in lignesVente) {
      final produit = await (_db.select(
        _db.produitsVendables,
      )..where((p) => p.id.equals(l.produitId))).getSingleOrNull();
      final groupe =
          groupes[produit?.groupeTaxe ?? GroupeTaxe.parDefaut.code] ??
          GroupeTaxe.parDefaut;

      // Le montant de la ligne de vente est TTC : on le ramene en HT.
      final ttc = l.qte * l.pu;
      final ht = ttc / (1 + groupe.taux / 100);
      lignes.add(
        LigneFacture(
          designation: l.name,
          quantite: l.qte,
          unite: produit?.unit,
          prixUnitaireHt: l.qte == 0 ? 0 : ht / l.qte,
          groupeTaxe: groupe.code,
          tauxTaxe: groupe.taux,
        ),
      );
    }

    return _inserer(
      type: TypeFacture.vente,
      date: date ?? vente.dateVente,
      client: vente.client,
      clientIfu: clientIfu,
      clientAdresse: clientAdresse,
      lignes: lignes,
      venteRef: venteRef,
    );
  }

  /// Émet un avoir sur une facture existante.
  ///
  /// [lignes] vide = avoir total : toutes les lignes de la facture d'origine
  /// sont reprises telles quelles.
  Future<FactureMecef> emettreAvoir({
    required String factureOrigine,
    required String motif,
    List<LigneFacture> lignes = const [],
    DateTime? date,
  }) async {
    final origine = await parReference(factureOrigine);
    if (origine == null) {
      throw StateError('Facture $factureOrigine introuvable.');
    }
    if (origine.type != TypeFacture.vente) {
      throw StateError('Un avoir ne se fait que sur une facture de vente.');
    }
    if (motif.trim().isEmpty) {
      throw StateError('Un avoir sans motif n\'explique rien : motif requis.');
    }

    final aReprendre = lignes.isEmpty ? origine.lignes : lignes;

    // Un avoir ne dépasse jamais la facture qu'il corrige : avec les avoirs déjà
    // émis sur elle, le cumul reste dans son total TTC (tolérance d'arrondi 0,01).
    final nouveauTtc = aReprendre.fold<double>(0, (s, l) => s + l.montantTtc);
    final dejaCredite = (await toutes())
        .where(
          (f) => f.type == TypeFacture.avoir && f.origineRef == factureOrigine,
        )
        .fold<double>(0, (s, f) => s + f.totalTtc);
    if (dejaCredite + nouveauTtc > origine.totalTtc + 0.01) {
      throw StateError(
        'Les avoirs sur $factureOrigine dépasseraient la facture : '
        '${dejaCredite.round()} FCFA déjà crédités, ${nouveauTtc.round()} demandés, '
        'facture de ${origine.totalTtc.round()} FCFA.',
      );
    }
    return _inserer(
      type: TypeFacture.avoir,
      date: date ?? DateTime.now(),
      client: origine.client,
      clientIfu: origine.clientIfu,
      clientAdresse: origine.clientAdresse,
      lignes: aReprendre,
      origineRef: factureOrigine,
      motif: motif.trim(),
    );
  }

  /// Enregistre le retour de la DGI.
  Future<void> normaliser({
    required String reference,
    required String codeMecef,
    required String nim,
    String? compteur,
    String? lienVerification,
    DateTime? dateNormalisation,
  }) async {
    if (codeMecef.trim().isEmpty || nim.trim().isEmpty) {
      throw StateError(
        'Une facture ne devient normalisée qu\'avec un code et un NIM réels.',
      );
    }
    final actuelle = await (_db.select(
      _db.factures,
    )..where((f) => f.ref.equals(reference))).getSingleOrNull();
    if (actuelle == null) {
      throw StateError('Facture $reference introuvable.');
    }
    // Une facture normalisée est IMMUABLE (règle fiscale) : un second code ne
    // remplace jamais le premier, et un statut ne régresse jamais.
    if (StatutFacture.depuis(actuelle.statut) == StatutFacture.normalisee) {
      throw StateError(
        'La facture $reference est déjà normalisée : elle ne peut plus être '
        'modifiée. Pour la corriger, émettez un avoir.',
      );
    }
    if (_estDUnAutrePoste(actuelle.origine)) {
      throw StateError(_refusAutrePoste(reference));
    }
    await (_db.update(
      _db.factures,
    )..where((f) => f.ref.equals(reference))).write(
      FacturesCompanion(
        statut: Value(StatutFacture.normalisee.code),
        codeMecef: Value(codeMecef.trim()),
        nim: Value(nim.trim()),
        compteur: Value(compteur),
        lienVerification: Value(lienVerification),
        dateNormalisation: Value(dateNormalisation ?? DateTime.now()),
        erreurTransmission: const Value(null),
        // À envoyer : le serveur ne connaît pas encore cette normalisation.
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
  }

  /// Consigne l'échec d'une transmission.
  Future<void> marquerRejetee({
    required String reference,
    required String erreur,
  }) async {
    final actuelle = await (_db.select(
      _db.factures,
    )..where((f) => f.ref.equals(reference))).getSingleOrNull();
    if (actuelle == null) return;
    // Jamais de régression : une facture normalisée reste normalisée, même si
    // une transmission tardive échoue.
    if (StatutFacture.depuis(actuelle.statut) == StatutFacture.normalisee) {
      return;
    }
    if (_estDUnAutrePoste(actuelle.origine)) {
      throw StateError(_refusAutrePoste(reference));
    }
    await (_db.update(
      _db.factures,
    )..where((f) => f.ref.equals(reference))).write(
      FacturesCompanion(
        statut: Value(StatutFacture.rejetee.code),
        erreurTransmission: Value(erreur),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
  }

  /// Une facture du web (poste émetteur « web ») n'est pas celle d'un autre poste.
  static bool _estDUnAutrePoste(String? origine) =>
      origine != null && origine != identifiantPosteWeb;

  static String _refusAutrePoste(String reference) =>
      'La facture $reference a été émise sur un autre poste : elle se '
      'transmet à la DGI depuis ce poste, pour qu\'elle ne soit pas '
      'normalisée deux fois.';

  // ------------------------------------------------------------- interne

  Future<FactureMecef> _inserer({
    required TypeFacture type,
    required DateTime date,
    required String client,
    required List<LigneFacture> lignes,
    String? clientIfu,
    String? clientAdresse,
    String? venteRef,
    String? origineRef,
    String? motif,
  }) async {
    if (lignes.isEmpty) {
      throw StateError('Une facture sans ligne ne facture rien.');
    }

    final reference = await _referenceSuivante(type, date);
    final totalHt = lignes.fold<double>(0, (s, l) => s + l.montantHt);
    final totalTaxe = lignes.fold<double>(0, (s, l) => s + l.montantTaxe);

    await _db.transaction(() async {
      await _db
          .into(_db.factures)
          .insert(
            FacturesCompanion.insert(
              ref: reference,
              type: type.code,
              dateFacture: date,
              client: client,
              totalHt: totalHt,
              totalTaxe: totalTaxe,
              totalTtc: totalHt + totalTaxe,
              statut: StatutFacture.aTransmettre.code,
              venteRef: Value(venteRef),
              origineRef: Value(origineRef),
              clientIfu: Value(clientIfu),
              clientAdresse: Value(clientAdresse),
              motif: Value(motif),
            ),
          );

      for (final l in lignes) {
        await _db
            .into(_db.lignesFacture)
            .insert(
              LignesFactureCompanion.insert(
                factureRef: reference,
                designation: l.designation,
                quantite: l.quantite,
                prixUnitaireHt: l.prixUnitaireHt,
                groupeTaxe: l.groupeTaxe,
                tauxTaxe: l.tauxTaxe,
                montantHt: l.montantHt,
                montantTaxe: l.montantTaxe,
                unite: Value(l.unite),
              ),
            );
      }
    });

    return (await parReference(reference))!;
  }

  /// `FV-P2-2026-001` pour un poste appairé (DV-21), `FV-2026-001` sinon. La
  /// séquence est continue **par poste, par type et par année** ; on prend le
  /// maximum NUMÉRIQUE (le tri du texte placerait `…-1000` avant `…-999`).
  Future<String> _referenceSuivante(TypeFacture type, DateTime date) async {
    final code = await PreferencesPosteRepository(_db).codeAttribue();
    final prefixe = NumerotationFacture.prefixeDe(type, date.year, code);
    final existantes = await (_db.select(
      _db.factures,
    )..where((f) => f.ref.like('$prefixe%'))).get();

    var maximum = 0;
    for (final f in existantes) {
      final numero = int.tryParse(f.ref.substring(prefixe.length));
      if (numero != null && numero > maximum) maximum = numero;
    }
    return '$prefixe${(maximum + 1).toString().padLeft(3, '0')}';
  }

  FactureMecef _versEntite(FactureRow e, List<LigneFactureRow> lignes) {
    return FactureMecef(
      id: e.id,
      reference: e.ref,
      type: TypeFacture.depuis(e.type),
      date: e.dateFacture,
      client: e.client,
      clientIfu: e.clientIfu,
      clientAdresse: e.clientAdresse,
      statut: StatutFacture.depuis(e.statut),
      venteRef: e.venteRef,
      origineRef: e.origineRef,
      motif: e.motif,
      codeMecef: e.codeMecef,
      nim: e.nim,
      compteur: e.compteur,
      lienVerification: e.lienVerification,
      dateNormalisation: e.dateNormalisation,
      erreurTransmission: e.erreurTransmission,
      origine: e.origine,
      lignes: [
        for (final l in lignes)
          LigneFacture(
            id: l.id,
            designation: l.designation,
            quantite: l.quantite,
            unite: l.unite,
            prixUnitaireHt: l.prixUnitaireHt,
            groupeTaxe: l.groupeTaxe,
            tauxTaxe: l.tauxTaxe,
          ),
      ],
    );
  }
}
