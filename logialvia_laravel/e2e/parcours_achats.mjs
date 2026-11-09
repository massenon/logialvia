// Parcours reels AU CLIC : achats (commande -> reception -> reglement), fournisseurs, depenses.
import { scenario, avec, aller, attendreTexte, verifier, egal, un, valeur, calme } from './lib.mjs';

const dialogue = (page) => page.locator('[role=dialog]');

scenario('achats (admin) : commande -> reception -> reglement -> annulation', async () => {
  await avec('admin', 'achats', async (page) => {
    await aller(page, '/achats');
    await page.click('[data-action=nouvelle-commande]');
    const m = page.locator('[data-modale=commande]');
    await m.waitFor();
    await m.locator('[data-action=valider-commande]').click(); // vide : refuse
    await m.locator('[data-erreur-formulaire]').waitFor();
    await m.locator('[data-champ=intrant]').selectOption('PROV-CRO');
    await m.locator('[data-action=ajouter-intrant]').click();
    await m.locator('[data-ligne-panier="PROV-CRO"] input[aria-label=Quantité]').fill('200');
    await m.locator('[data-ligne-panier="PROV-CRO"] input[aria-label="Prix unitaire"]').fill('320');
    await m.locator('[data-champ=fournisseur]').selectOption({ label: 'Provenderie du Golfe' });
    await attendreTexte(page, 'TOTAL 64 000 FCFA', { zone: '[data-modale=commande]' });
    await m.getByLabel(/Livrée immédiatement/).uncheck(); // par defaut la commande est livree : on veut le cycle complet
    await m.locator('[data-action=valider-commande]').click();
    await m.waitFor({ state: 'detached' });
    const a = un("select * from achats where total=64000 and statut='Commandé'");
    verifier(a, 'commande en base');
    egal(valeur('select count(*) from lignes_achat where achat_id=?', [a.id]), 1, 'une ligne d\'achat');
    const stockAvant = valeur("select coalesce(sum(quantite),0) from mouvements_intrant where intrant_code='PROV-CRO'");
    // Reception : modale de confirmation, puis statut + mouvement de stock.
    await page.locator(`tr[data-achat="${a.reference}"] [data-action=receptionner]`).click();
    await page.locator('[data-modale=reception] [data-action=confirmer-reception]').click();
    await page.locator('[data-modale=reception]').waitFor({ state: 'detached' });
    egal(valeur('select statut from achats where id=?', [a.id]), 'Livré', 'statut apres reception');
    egal(valeur("select coalesce(sum(quantite),0) from mouvements_intrant where intrant_code='PROV-CRO'") - stockAvant, 200, 'mouvement de stock de 200');
    // Reglement : trop eleve refuse, partiel, puis solde.
    await page.locator(`tr[data-achat="${a.reference}"] [data-action=regler]`).click();
    const r = page.locator('[data-modale=reglement]');
    await r.waitFor();
    await r.getByLabel(/Montant Réglé/).fill('0');
    await r.locator('[data-action=confirmer-reglement]').click();
    await r.locator('[data-erreur-reglement]').waitFor(); // montant nul : refuse
    await r.getByLabel(/Montant Réglé/).fill('24000');
    await r.locator('[data-action=confirmer-reglement]').click();
    await r.waitFor({ state: 'detached' });
    egal(valeur('select paye from achats where id=?', [a.id]), 24000, 'paye apres reglement partiel');
    await page.locator(`tr[data-achat="${a.reference}"] [data-action=regler]`).click();
    await r.getByLabel(/Montant Réglé/).fill('99999999'); // Dart : le versement est plafonne au reste du (40 000)
    await r.locator('[data-action=confirmer-reglement]').click();
    await r.waitFor({ state: 'detached' });
    egal(valeur('select paye from achats where id=?', [a.id]), 64000, 'achat solde');
    verifier(valeur("select count(*) from pieces_comptables where achat_ref=?", [a.reference]) >= 2, 'pieces comptables de l\'achat et des reglements');

    // Annulation d'une commande « Commandé » : motif obligatoire.
    const cmd = un("select * from achats where statut='Commandé' limit 1"); // celle du jeu de donnees (desinfectant)
    await page.locator(`tr[data-achat="${cmd.reference}"] [data-action=annuler-commande]`).click();
    const an = page.locator('[data-modale=annulation]');
    await an.locator('[data-action=confirmer-annulation]').click();
    await an.locator('[data-erreur-annulation]').waitFor();
    await an.locator('[data-champ=motif]').fill('Fournisseur en rupture');
    await an.locator('[data-action=confirmer-annulation]').click();
    await an.waitFor({ state: 'detached' });
    egal(valeur('select statut from achats where id=?', [cmd.id]), 'Annulé', 'commande annulee');
  });
});

scenario('fournisseurs : ajouter, modifier, supprimer + coherence 401', async () => {
  await avec('admin', 'fournisseurs', async (page) => {
    await aller(page, '/fournisseurs');
    await page.click('button:has-text("Ajouter un Fournisseur")');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).locator('[role=alert]').waitFor();
    await dialogue(page).getByLabel(/Nom/).fill('Vétérinaire Hounkpatin');
    await dialogue(page).getByLabel('Téléphone').fill('+229 97 55 44 33');
    await dialogue(page).getByLabel('Fournit').fill('Soins et vaccins');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    const f = un("select * from fournisseurs where nom='Vétérinaire Hounkpatin'");
    verifier(f && f.fournit === 'Soins et vaccins' && !f.supprime_le, `fournisseur en base : ${JSON.stringify(f)}`);
    await page.locator('tr[data-fournisseur="Vétérinaire Hounkpatin"] button:has-text("Modifier")').click();
    await dialogue(page).getByLabel('Téléphone').fill('+229 97 00 00 00');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    egal(valeur("select telephone from fournisseurs where nom='Vétérinaire Hounkpatin'"), '+229 97 00 00 00', 'telephone modifie');
    await page.locator('tr[data-fournisseur="Vétérinaire Hounkpatin"] button:has-text("Supprimer")').click();
    await dialogue(page).locator('button:has-text("Supprimer")').click();
    await dialogue(page).waitFor({ state: 'detached' });
    verifier(valeur("select supprime_le from fournisseurs where nom='Vétérinaire Hounkpatin'"), 'fournisseur en corbeille');
    // Bloc de coherence dette/401 visible.
    await attendreTexte(page, /Compte 401/i, { zone: '[data-bloc=coherence]' });
  });
});

scenario('depenses : saisie (SYSCOHADA), validation, correction, annulation', async () => {
  await avec('comptable', 'depenses', async (page) => {
    await aller(page, '/depenses');
    const form = page.locator('[data-formulaire=depense]');
    await form.locator('[data-action=enregistrer]').click(); // vide : refuse
    await form.locator('[data-erreur-champ]').first().waitFor();
    await form.locator('#libelle').fill('Achat de seaux et abreuvoirs');
    await form.locator('#categorie').selectOption({ index: 1 });
    await form.locator('#montant').fill('18500');
    await form.locator('#reglement').selectOption({ index: 1 });
    await form.locator('[data-action=enregistrer]').click();
    await page.locator('tr[data-depense]').filter({ hasText: 'Achat de seaux et abreuvoirs' }).waitFor();
    const piece = un("select p.* from pieces_comptables p join ecritures_comptables e on e.piece_id=p.id where e.libelle like '%seaux et abreuvoirs%' limit 1");
    verifier(piece, 'piece comptable de la depense en base');
    const somme = un('select sum(debit) d, sum(credit) c from ecritures_comptables where piece_id=?', [piece.id]);
    egal([somme.d, somme.c], [18500, 18500], 'piece equilibree');
    // Correction : charge la depense dans le formulaire, change le montant.
    await page.locator(`tr[data-depense="${piece.numero_piece}"] [data-action=corriger-depense]`).click();
    await calme(page); // la reponse du serveur remplit le formulaire : on attend avant de retaper le montant
    await form.locator('#montant').fill('19000');
    await form.locator('[data-action=enregistrer]').click();
    await attendreTexte(page, '19 000', { zone: '[data-table=depenses]' });
    const nouvelle = un("select sum(debit) d from ecritures_comptables e join pieces_comptables p on p.id=e.piece_id where e.libelle like '%seaux et abreuvoirs%' and p.contrepasse_de is null");
    verifier(nouvelle.d >= 19000, `la correction cree une piece a 19 000 (vu ${JSON.stringify(nouvelle)})`);
    // Annulation d'une depense : modale puis contre-passation.
    const cible = page.locator('tr[data-depense]').filter({ hasText: 'Achat de seaux et abreuvoirs' }).first();
    await cible.locator('[data-action=annuler-depense]').click();
    await page.locator('[data-modale=annulation] [data-action=confirmer-annulation]').click();
    await page.locator('[data-modale=annulation]').waitFor({ state: 'detached' });
    verifier(valeur("select count(*) from pieces_comptables where numero_piece like 'ANN-%'") >= 1, 'contre-passation de la depense');
  });
});
