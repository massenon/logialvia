// Parcours reels AU CLIC : utilisateurs, corbeille, parametres (modules, entreprise), profil (mot de passe), contact.
import { scenario, avec, aller, attendreTexte, verifier, egal, un, valeur, calme, ouvrir, connecter, MDP } from './lib.mjs';

const dialogue = (page) => page.locator('[role=dialog]');
async function choisir(select, motif) {
  const v = await select.evaluate((el, src) => [...el.options].find((o) => new RegExp(src, 'i').test(o.textContent))?.value, motif);
  if (v === undefined) throw new Error(`aucune option ~ ${motif}`);
  await select.selectOption(v);
}
const onglet = (page, nom) => page.locator('[role=tab]', { hasText: nom }).click();

scenario('utilisateurs : creer, desactiver, reactiver, supprimer -> corbeille -> restaurer', async () => {
  await avec('admin', 'utilisateurs', async (page) => {
    await aller(page, '/parametres/generaux');
    await onglet(page, 'Gestion Utilisateurs');
    await page.click('button:has-text("Ajouter un Utilisateur")');
    await dialogue(page).locator('button[type=submit]').click(); // vide : refuse
    await dialogue(page).locator('[data-erreur]').waitFor();
    await dialogue(page).getByLabel(/Nom Complet/).fill('Agent Deux');
    await dialogue(page).getByLabel(/Identifiant de Connexion/).fill('agent2');
    await choisir(dialogue(page).getByLabel(/Rôle/), 'Vente');
    await dialogue(page).getByLabel(/Mot de Passe temporaire/).fill('faible');
    await dialogue(page).getByLabel(/Confirmer le Mot de Passe/).fill('faible');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).locator('[data-erreur]').waitFor(); // mot de passe trop faible
    await dialogue(page).getByLabel(/Mot de Passe temporaire/).fill('Temp-Passw0rd');
    await dialogue(page).getByLabel(/Confirmer le Mot de Passe/).fill('Temp-Passw0rd');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    const u = un("select * from users where username='agent2'");
    verifier(u && u.must_change_password === 1 && u.is_active === 1, `utilisateur en base : ${JSON.stringify(u)}`);
    egal(valeur("select r.name from roles r join model_has_roles m on m.role_id=r.id where m.model_id=?", [u.id]), 'caissier', 'role en base');
    // Desactiver puis reactiver.
    await page.locator('tr[data-compte="agent2"] button:has-text("Désactiver")').click();
    await dialogue(page).locator('button').last().click();
    await dialogue(page).waitFor({ state: 'detached' });
    egal(valeur("select is_active from users where username='agent2'"), 0, 'compte desactive');
    await page.locator('tr[data-compte="agent2"] button:has-text("Réactiver")').click();
    await calme(page);
    egal(valeur("select is_active from users where username='agent2'"), 1, 'compte reactive');
    // Supprimer -> corbeille.
    await page.locator('tr[data-compte="agent2"] button:has-text("Supprimer")').click();
    await dialogue(page).locator('button').last().click();
    await dialogue(page).waitFor({ state: 'detached' });
    verifier(valeur("select deleted_at from users where username='agent2'"), 'compte en corbeille (deleted_at)');
    await onglet(page, 'Corbeille');
    await attendreTexte(page, 'Agent Deux', { zone: '[data-onglet=corbeille]' });
    await page.locator('tr[data-element]', { hasText: 'Agent Deux' }).locator('button:has-text("Restaurer")').first().click();
    await calme(page);
    egal(valeur("select deleted_at from users where username='agent2'"), null, 'compte restaure');
  });
});

scenario('utilisateurs : un compte desactive ne peut plus se connecter', async () => {
  await avec('admin', 'utilisateur_desactive', async (page, contexte) => {
    await aller(page, '/parametres/generaux');
    await onglet(page, 'Gestion Utilisateurs');
    await page.locator('tr[data-compte="caissier1"] button:has-text("Désactiver")').click();
    await dialogue(page).locator('button').last().click();
    await dialogue(page).waitFor({ state: 'detached' });
    const autre = await contexte.browser().newContext({ baseURL: process.env.LV_URL, locale: 'fr-FR' });
    const p = await autre.newPage();
    await p.goto('/login');
    await p.fill('#identifiant', 'caissier1');
    await p.fill('#password', MDP);
    await p.click('button[type=submit]');
    await p.waitForSelector('[role=alert]');
    verifier(new URL(p.url()).pathname === '/login', 'compte desactive reste sur /login');
    await autre.close();
    await page.locator('tr[data-compte="caissier1"] button:has-text("Réactiver")').click();
    await calme(page);
    egal(valeur("select is_active from users where username='caissier1'"), 1, 'caissier1 reactive');
  });
});

scenario('parametres : modifier l\'entreprise ; module desactive -> ecran 404 et lien retire -> reactive', async () => {
  await avec('admin', 'parametres', async (page) => {
    await aller(page, '/parametres/generaux');
    await onglet(page, "Données de l'Entreprise");
    await page.getByLabel(/Raison Sociale/).fill('ALLMANY ET COMPAGNIE SARL');
    await page.getByLabel(/Téléphone Principal/).fill('+229 01 11 22 33 44');
    await page.locator('form[data-onglet=entreprise] button[type=submit]').first().click();
    await calme(page);
    egal(valeur('select raison_sociale from parametres_entreprise limit 1'), 'ALLMANY ET COMPAGNIE SARL', 'raison sociale en base');
    // Module bovins : desactive -> la fiche disparait.
    await onglet(page, 'Modules Actifs');
    await page.locator('[data-module=bovins] button').click();
    await calme(page);
    egal(valeur("select is_actif from modules_actifs where module_id='bovins'"), 0, 'module desactive en base');
    const r = await page.goto('/elevage/bovins');
    egal(r.status(), 404, 'fiche bovins fermee');
    page.problemes.length = 0;
    await aller(page, '/dashboard');
    verifier(await page.locator('aside a[href$="/elevage/bovins"]').count() === 0, 'lien Fiche Bovins retire de la barre');
    await aller(page, '/parametres/generaux');
    await page.locator('[data-module=bovins] button').click();
    await calme(page);
    egal(valeur("select is_actif from modules_actifs where module_id='bovins'"), 1, 'module reactive');
  });
});

scenario('profil : changer son mot de passe (ancien faux refuse), puis reconnexion', async () => {
  await avec('comptable', 'profil', async (page, contexte) => {
    await aller(page, '/profil');
    await page.fill('#actuel', 'FauxAncien-1');
    await page.fill('#nouveau', 'Comptable-2027!');
    await page.fill('#confirmation', 'Comptable-2027!');
    await page.click('button:has-text("Mettre à jour le mot de passe")');
    await page.locator('[role=alert]').waitFor();
    await page.fill('#actuel', MDP);
    await page.click('button:has-text("Mettre à jour le mot de passe")');
    await page.waitForURL((u) => !u.pathname.startsWith('/profil')); // le serveur renvoie vers le tableau de bord
    await aller(page, '/profil');
    const autre = await contexte.browser().newContext({ baseURL: process.env.LV_URL, locale: 'fr-FR' });
    const p = await autre.newPage();
    await connecter(p, 'comptable1', 'Comptable-2027!');
    verifier(new URL(p.url()).pathname !== '/login', 'connexion avec le nouveau mot de passe');
    await autre.close();
    // On remet le mot de passe d'essai pour la suite de la suite.
    await page.fill('#actuel', 'Comptable-2027!');
    await page.fill('#nouveau', MDP);
    await page.fill('#confirmation', MDP);
    await page.click('button:has-text("Mettre à jour le mot de passe")');
    await calme(page, 300);
  });
});

scenario('contact : question generale et probleme technique (validation, enregistrement)', async () => {
  await avec('caissier', 'contact', async (page) => {
    await aller(page, '/contact');
    await page.locator('[data-section=formulaire] button[type=submit]').click(); // vide : refuse
    await page.locator('[data-section=formulaire] [role=alert]').first().waitFor();
    await page.getByLabel(/Objet/).fill('Question sur les avoirs');
    await page.getByLabel(/^Message/).fill('Comment annuler une facture normalisee ?');
    await page.locator('[data-section=formulaire] button[type=submit]').click();
    await calme(page);
    const m = un("select * from messages_editeur where sujet='Question sur les avoirs'");
    verifier(m && m.type === 'question', `message en base : ${JSON.stringify(m)}`);
    await page.locator('[role=tab]', { hasText: 'Problème technique' }).click();
    await choisir(page.getByLabel(/Module concerné/), '^[^-]');
    await page.getByLabel(/Description du problème/).fill('Le bouton ne repond pas');
    await page.locator('[data-section=formulaire] button[type=submit]').click();
    await calme(page);
    egal(valeur("select count(*) from messages_editeur where type='bug'"), 1, 'probleme technique en base');
  });
});
