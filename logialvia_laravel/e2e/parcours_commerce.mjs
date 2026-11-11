// Parcours reels AU CLIC : connexion, catalogue, clients, caisse, historique, annulation, devis, factures.
import { scenario, avec, visiteur, connecter, aller, attendreTexte, verifier, egal, sql, un, valeur, calme, capturer, MDP } from './lib.mjs';

const dialogue = (page) => page.locator('[role=dialog]');

// ------------------------------------------------------------------------------------------ connexion

scenario('connexion : identifiants faux refuses, bons acceptes (clic), deconnexion', async () => {
  const { contexte, page } = await visiteur();
  try {
    await aller(page, '/login');
    await page.fill('#identifiant', 'admin1');
    await page.fill('#password', 'FauxMotDePasse1');
    await page.click('button[type=submit]');
    await attendreTexte(page, /incorrect|invalide|erron/i);
    verifier(new URL(page.url()).pathname === '/login', 'reste sur /login apres un echec');
    await page.fill('#password', MDP);
    await Promise.all([page.waitForURL('**/dashboard'), page.click('button[type=submit]')]);
    await attendreTexte(page, 'Bienvenue, Admin Test');
    // Deconnexion par le menu du compte.
    await page.click('details[data-menu=compte] summary');
    await Promise.all([page.waitForURL('**/login'), page.click('text=Déconnexion')]);
    await aller(page, '/dashboard');
    verifier(new URL(page.url()).pathname === '/login', 'apres deconnexion /dashboard renvoie a /login');
    page.problemes.length = 0;
  } finally { await contexte.close(); }
});

scenario('connexion : mot de passe temporaire -> seul le changement est ouvert, puis acces libre', async () => {
  const { contexte, page } = await visiteur();
  try {
    await connecter(page, 'temporaire1');
    verifier(new URL(page.url()).pathname === '/mot-de-passe', `redirige vers /mot-de-passe (${page.url()})`);
    await page.goto('/ventes');
    verifier(new URL(page.url()).pathname === '/mot-de-passe', 'un ecran metier reste ferme tant que le mot de passe est temporaire');
    // Trop faible : refuse.
    await page.fill('#actuel', MDP);
    await page.fill('#nouveau', 'faible');
    await page.fill('#confirmation', 'faible');
    await page.click('button[type=submit]');
    await attendreTexte(page, /caract|majuscule|chiffre/i);
    // Confirmation differente : refuse.
    await page.fill('#nouveau', 'NouveauMdp-2026');
    await page.fill('#confirmation', 'Autre-2026Mdp');
    await page.click('button[type=submit]');
    await attendreTexte(page, /confirmation|identique|correspond/i);
    // Bon changement.
    await page.fill('#confirmation', 'NouveauMdp-2026');
    await Promise.all([page.waitForURL((u) => !u.pathname.startsWith('/mot-de-passe')), page.click('button[type=submit]')]);
    await aller(page, '/ventes');
    verifier(new URL(page.url()).pathname === '/ventes', 'ecran ouvert apres changement');
    egal(valeur("select must_change_password from users where username='temporaire1'"), 0, 'drapeau must_change_password en base');
    // Reconnexion avec le nouveau mot de passe.
    await page.click('details[data-menu=compte] summary');
    await Promise.all([page.waitForURL('**/login'), page.click('text=Déconnexion')]);
    await connecter(page, 'temporaire1', 'NouveauMdp-2026');
    verifier(new URL(page.url()).pathname !== '/login', 'connexion avec le nouveau mot de passe');
    page.problemes.length = 0;
  } finally { await contexte.close(); }
});

// ------------------------------------------------------------------------------------------ catalogue

scenario('catalogue : ajouter, modifier, supprimer un produit (modale) + verification en base', async () => {
  await avec('admin', 'catalogue', async (page) => {
    await aller(page, '/catalogue');
    await page.click('button:has-text("Ajouter un Produit")');
    await dialogue(page).waitFor();
    // Validation : formulaire vide refuse, modale reste ouverte avec un message.
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).locator('[role=alert]').waitFor();
    await dialogue(page).getByLabel('Désignation').fill('Canard de Barbarie');
    await dialogue(page).getByLabel('Catégorie').selectOption('Avicole');
    await dialogue(page).getByLabel('Tarif indicatif (F)').fill('4800');
    await dialogue(page).getByLabel('Unité').fill('pièce');
    await dialogue(page).getByLabel("Seuil d'alerte").fill('4');
    await dialogue(page).locator('button[type=submit]').click();
    await attendreTexte(page, 'Produit « Canard de Barbarie » ajouté.');
    await dialogue(page).waitFor({ state: 'detached' });
    let p = un("select * from produits_vendables where name='Canard de Barbarie'");
    verifier(p && p.price === 4800 && p.cat === 'Avicole' && p.threshold === 4 && p.unit === 'pièce', `produit en base : ${JSON.stringify(p)}`);
    // Recherche en direct (wire:model.live).
    await page.fill('input[type=search]', 'Canard');
    await page.waitForFunction(() => [...document.querySelectorAll('tr[data-produit]')].length === 1);
    verifier(await page.locator('tr[data-produit]:visible').count() === 1, 'la recherche filtre a un produit');
    // Modifier.
    await page.locator('tr[data-produit] button:has-text("Modifier")').click();
    await dialogue(page).getByLabel('Tarif indicatif (F)').fill('5200');
    await dialogue(page).locator('button[type=submit]').click();
    await attendreTexte(page, 'Produit « Canard de Barbarie » modifié.');
    egal(valeur("select price from produits_vendables where name='Canard de Barbarie'"), 5200, 'prix modifie en base');
    // Supprimer : annuler d'abord, puis confirmer.
    await page.locator('tr[data-produit] button:has-text("Supprimer")').click();
    await dialogue(page).locator('button:has-text("Annuler")').click();
    await dialogue(page).waitFor({ state: 'detached' });
    egal(valeur("select count(*) from produits_vendables where name='Canard de Barbarie' and archive_le is null"), 1, 'annuler ne supprime pas');
    await page.locator('tr[data-produit] button:has-text("Supprimer")').click();
    await dialogue(page).locator('button:has-text("Supprimer")').click();
    await attendreTexte(page, 'supprimé du catalogue');
    p = un("select archive_le from produits_vendables where name='Canard de Barbarie'");
    verifier(p && p.archive_le, 'produit archive en base');
  });
});

scenario('catalogue : le caissier consulte sans bouton d\'ajout si droit absent', async () => {
  await avec('comptable', 'catalogue_comptable', async (page) => {
    const r = await page.goto('/catalogue');
    egal(r.status(), 403, 'comptable sans view-stocks');
    page.problemes.length = 0;
  });
});

// ------------------------------------------------------------------------------------------ clients et recouvrement

scenario('clients : ajouter, modifier, supprimer + recouvrement d\'une creance', async () => {
  await avec('admin', 'clients', async (page) => {
    await aller(page, '/clients');
    await page.click('button:has-text("Ajouter un Client")');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).locator('[role=alert]').waitFor();
    await dialogue(page).getByLabel('Nom').fill('Ferme du Plateau');
    await dialogue(page).getByLabel('Téléphone').fill('+229 90 12 34 56');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    let c = un("select * from clients where nom='Ferme du Plateau'");
    verifier(c && c.telephone === '+229 90 12 34 56' && !c.supprime_le, `client en base : ${JSON.stringify(c)}`);
    await page.fill('input[type=search]', 'Plateau');
    await attendreTexte(page, 'Ferme du Plateau');
    await page.locator('tr[data-client="Ferme du Plateau"] button:has-text("Modifier")').click();
    await dialogue(page).getByLabel('Téléphone').fill('+229 90 99 99 99');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    egal(valeur("select telephone from clients where nom='Ferme du Plateau'"), '+229 90 99 99 99', 'telephone modifie');
    await page.locator('tr[data-client="Ferme du Plateau"] button:has-text("Supprimer")').click();
    await dialogue(page).locator('button:has-text("Supprimer")').click();
    await dialogue(page).waitFor({ state: 'detached' });
    verifier(valeur("select supprime_le from clients where nom='Ferme du Plateau'"), 'client en corbeille (supprime_le)');

    // Recouvrement : la creance du Restaurant Le Palmier (65 000 - 20 000 = 45 000).
    await page.fill('input[type=search]', '');
    await aller(page, '/clients');
    await page.click('[data-onglet-client=dettes]');
    const ligne = page.locator('tr[data-creance]').first();
    await ligne.waitFor();
    const ref = await ligne.getAttribute('data-creance');
    await ligne.locator('[data-action=recouvrer]').click();
    const modale = page.locator('[data-modale=recouvrement]');
    await modale.waitFor();
    await modale.getByLabel(/Montant recouvré/).fill('99999999');
    await modale.locator('button[type=submit]').click();
    await modale.locator('[data-erreur=recouvrement]').waitFor(); // trop eleve : refuse
    await modale.getByLabel(/Montant recouvré/).fill('15000');
    await modale.locator('button[type=submit]').click();
    await modale.waitFor({ state: 'detached' });
    const v = un('select total, paye, status from ventes where reference=?', [ref]);
    egal([v.total, v.paye], [65000, 35000], 'creance apres recouvrement partiel');
    const solde = valeur("select solde_creance from clients where nom='Restaurant Le Palmier'");
    egal(solde, 30000, 'solde_creance du client');
    await attendreTexte(page, '30 000', { zone: 'main' });
    await capturer(page, 'clients_apres_recouvrement');
  });
});

// ------------------------------------------------------------------------------------------ caisse

scenario('caisse : panier -> encaissement -> historique -> detail -> annulation (motif)', async () => {
  await avec('caissier', 'caisse', async (page) => {
    await aller(page, '/ventes');
    // Panier : deux produits, la modale « vente a la piece » demande quantite et montant GLOBAL.
    await page.locator('[data-produit="Poulet de chair"]').click();
    const m = page.locator('[data-modale=vente-a-la-piece]');
    await m.waitFor();
    await m.locator('button[type=submit]').click(); // vide : refuse
    await m.locator('[role=alert]').waitFor();
    await m.getByLabel(/Quantité/).fill('3');
    await m.getByLabel(/Montant global/).fill('10000');
    await m.locator('button[type=submit]').click();
    await m.waitFor({ state: 'detached' });
    await page.locator('[data-produit="Lapin"]').click();
    await m.getByLabel(/Quantité/).fill('1');
    await m.getByLabel(/Montant global/).fill('5000');
    await m.locator('button[type=submit]').click();
    await m.waitFor({ state: 'detached' });
    await attendreTexte(page, '15 000 FCFA', { zone: '[data-section=panier]' });
    // Retirer une ligne puis remettre : le total suit.
    await page.locator('[data-ligne-panier="Lapin"] button:has-text("Retirer")').click();
    await attendreTexte(page, '10 000 FCFA', { zone: '[data-section=panier]' });
    await page.locator('[data-produit="Lapin"]').click();
    await m.getByLabel(/Quantité/).fill('1');
    await m.getByLabel(/Montant global/).fill('5000');
    await m.locator('button[type=submit]').click();
    await m.waitFor({ state: 'detached' });
    // Client choisi dans les suggestions (saisie live).
    await page.fill('[data-section=panier] input[placeholder="Client Comptant"]', 'Koffi');
    await page.locator('[data-suggestion="Koffi Mensah"]').click();
    // Montant recu insuffisant -> refus a l'ecran.
    await page.fill('[data-section=panier] input[inputmode=numeric]', '1000');
    await page.click('button:has-text("Valider la Vente")');
    await page.locator('[data-erreur=caisse]').waitFor();
    // Montant recu correct : monnaie a rendre, encaissement.
    await page.fill('[data-section=panier] input[inputmode=numeric]', '20000');
    await attendreTexte(page, 'Monnaie à rendre : 5 000', { zone: '[data-section=panier]' });
    await page.click('button:has-text("Valider la Vente")');
    await attendreTexte(page, 'Panier vide', { zone: '[data-section=panier]' });
    const v = un("select * from ventes where client='Koffi Mensah' order by date_vente desc");
    verifier(v && v.total === 15000 && v.paye === 15000 && v.status === 'Payée', `vente en base : ${JSON.stringify(v)}`);
    egal(valeur('select count(*) from lignes_vente where vente_id=?', [v.id]), 2, 'deux lignes de vente');
    verifier(valeur('select count(*) from pieces_comptables where vente_ref=?', [v.reference]) >= 1, 'ecritures comptables de la vente');
    // Historique : la vente est listee, le detail s'ouvre.
    await page.click('[data-onglet=historique]');
    await page.locator(`[data-vente="${v.reference}"]`).first().waitFor();
    await page.fill('input[aria-label="Rechercher une vente"]', 'Koffi');
    await page.waitForFunction(() => document.querySelectorAll('tr[data-vente]').length === 1);
    egal(await page.locator('tr[data-vente]:visible').count(), 1, 'recherche dans l\'historique');
    await page.locator(`tr[data-vente="${v.reference}"] td`).first().click();
    const detail = page.locator(`[data-detail="${v.reference}"]`);
    await detail.waitFor();
    await attendreTexte(page, 'Poulet de chair', { zone: `[data-detail="${v.reference}"]` });
    await detail.locator('button:has-text("Fermer")').click();
    await detail.waitFor({ state: 'detached' });
    // Annulation : motif obligatoire, puis statut en base et contre-passation.
    await page.locator(`tr[data-vente="${v.reference}"] [data-action=annuler-vente]`).click();
    const a = page.locator('[data-modale=annulation]');
    await a.waitFor();
    await a.locator('button:has-text("Confirmer l\'Annulation")').click();
    await a.locator('[data-erreur=historique]').waitFor(); // motif vide refuse
    await a.locator('select').selectOption({ index: 1 });
    const motifChoisi = await a.locator('select').inputValue();
    await a.locator('button:has-text("Confirmer l\'Annulation")').click();
    await a.waitFor({ state: 'detached' });
    const apres = un('select status, motif_annulation from ventes where id=?', [v.id]);
    verifier(apres.status === 'Annulée' && apres.motif_annulation === motifChoisi, `annulation en base : ${JSON.stringify(apres)}`);
    verifier(valeur('select count(*) from pieces_comptables where numero_piece = ?', ['ANN-' + v.reference]) >= 1, 'contre-passation comptable');
  });
});

scenario('caisse : vente a credit (avance) -> creance visible dans Clients', async () => {
  await avec('caissier', 'caisse_credit', async (page) => {
    await aller(page, '/ventes');
    await page.locator('[data-produit="Pintade adulte"]').click();
    const m = page.locator('[data-modale=vente-a-la-piece]');
    await m.getByLabel(/Quantité/).fill('4');
    await m.getByLabel(/Montant global/).fill('18000');
    await m.locator('button[type=submit]').click();
    await m.waitFor({ state: 'detached' });
    await page.fill('[data-section=panier] input[placeholder="Client Comptant"]', 'Hôtel');
    await page.locator('[data-suggestion="Hôtel Bénin Royal"]').click();
    await page.selectOption('[data-section=panier] select[wire\\:model\\.live="condition"]', { label: 'Avance (Solde Restant Dû)' });
    await calme(page);
    // REGRESSION (47n_) : clic immediat apres la frappe (< 300 ms de debounce) -> le montant recu doit partir avec l'action.
    await page.fill('[data-section=panier] input[inputmode=numeric]', '8000');
    await page.click('button:has-text("Valider la Vente")');
    await attendreTexte(page, 'Panier vide', { zone: '[data-section=panier]' });
    const v = un("select * from ventes where client='Hôtel Bénin Royal'");
    egal([v.total, v.paye, v.status], [18000, 8000, 'Avance'], 'vente a credit en base');
    egal(valeur("select solde_creance from clients where nom='Hôtel Bénin Royal'"), 10000, 'creance du client');
  });
});
