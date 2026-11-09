import 'dart:async';

/// Événement de domaine — Doc C1 §4.
///
/// Formalise le `window.dispatchEvent(new CustomEvent('logialvia:update'))` du
/// prototype : une vente (contexte Commercial) doit notifier l'Élevage sans que
/// les deux contextes soient couplés dans le code.
abstract class DomainEvent {
  DomainEvent() : occurredAt = DateTime.now();

  final DateTime occurredAt;
}

/// Ligne concernée par un mouvement de vente.
class LigneVenteInfo {
  const LigneVenteInfo({
    required this.produitId,
    required this.quantite,
    this.espece,
  });

  final String produitId;
  final double quantite;

  /// Renseignée si le produit est un animal vivant — déclenche la répercussion
  /// sur la fiche d'élevage (BR-ELV-010).
  final String? espece;
}

class VenteValideeEvent extends DomainEvent {
  VenteValideeEvent({required this.venteRef, required this.lignes});

  final String venteRef;
  final List<LigneVenteInfo> lignes;
}

class VenteAnnuleeEvent extends DomainEvent {
  VenteAnnuleeEvent({required this.venteRef, required this.lignes});

  final String venteRef;
  final List<LigneVenteInfo> lignes;
}

class ExerciceClotureEvent extends DomainEvent {
  ExerciceClotureEvent({required this.exerciceAnneeCloturee});

  final int exerciceAnneeCloturee;
}

/// Bus d'événements de domaine — Doc C1 §4.
///
/// ## Portée exacte, et ce qu'il ne fait PAS
///
/// Doc C1 §4 prescrit que la communication inter-contextes passe par ces
/// événements. **Ce bus sert à la notification, pas à la cohérence des
/// données.**
///
/// La raison est une règle métier qui prime : BR-VTE-002 impose que
/// l'enregistrement d'une vente soit **atomique** (Doc D1 §4 — « transaction
/// Drift explicite »). Décrémenter le stock puis publier un événement qui
/// mettrait à jour la fiche d'élevage de façon asynchrone romprait cette
/// atomicité : un plantage entre les deux laisserait un stock décrémenté sans
/// vente répercutée, exactement le genre d'incohérence silencieuse que ce
/// projet a déjà connue.
///
/// **Choix retenu, assumé** : toutes les écritures d'une vente — vente, lignes,
/// stock, compteur de la fiche d'élevage — se font dans **une seule transaction
/// Drift**. Le bus est ensuite utilisé pour prévenir les ViewModels ouverts
/// qu'ils doivent se rafraîchir. Le découplage visé par C1 §4 est préservé là
/// où il compte (aucun `usecase` n'appelle le ViewModel d'un autre contexte),
/// sans sacrifier une règle métier à un principe d'architecture.
class EventBus {
  EventBus();

  final StreamController<DomainEvent> _controleur =
      StreamController<DomainEvent>.broadcast();

  Stream<T> on<T extends DomainEvent>() =>
      _controleur.stream.where((e) => e is T).cast<T>();

  void publier(DomainEvent evenement) {
    if (_controleur.isClosed) return;
    _controleur.add(evenement);
  }

  void dispose() => _controleur.close();
}
