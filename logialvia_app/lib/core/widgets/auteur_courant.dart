import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../administration/domain/services/service_archivage.dart';
import '../../administration/presentation/viewmodels/auth_view_model.dart';

/// L'utilisatrice connectee, sous la forme attendue par la corbeille.
///
/// Un helper plutot que six repetitions de `context.read<AuthViewModel>()` :
/// la corbeille doit dire QUI a supprime quoi, et une seule de ces lectures
/// oubliee laisserait une colonne vide sans que rien ne le signale.
///
/// Retourne `null` hors session — ce qui n'arrive pas depuis un ecran, tous
/// etant derriere l'authentification, mais le type le dit plutot que de
/// supposer.
AuteurArchivage? auteurCourant(BuildContext context) {
  final session = context.read<AuthViewModel>().session;
  if (session == null) return null;
  return AuteurArchivage(
    id: session.utilisateur.identifiant,
    nom: session.utilisateur.nom,
  );
}
