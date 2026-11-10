// Transversaux navigateur (2/2) : responsive, clavier, double clic, reseau, session, deux onglets, rafraichissement, accessibilite.
import fs from 'node:fs';
import path from 'node:path';
import { scenario, avec, ouvrir, visiteur, aller, verifier, egal, valeur, calme, capturer, debordeEnLargeur, attendreTexte, connecter, MDP, DOSSIER, URL_BASE } from './lib.mjs';

const matrice = JSON.parse(fs.readFileSync(path.join(DOSSIER, 'matrice.json'), 'utf8'));
const routesAdmin = [...Object.keys(matrice.routes), '/parametres/postes', '/parametres/audit', '/ventes/devis'];
const dialogue = (page) => page.locator('[role=dialog]');

// ------------------------------------------------------------------------------------------ responsive

for (const [nom, largeur, hauteur] of [['telephone', 390, 800], ['tablette', 768, 1024], ['bureau', 1280, 800]]) {
  scenario(`responsive ${nom} (${largeur}px) : aucune route ne deborde, menu utilisable, tableaux non tronques`, async () => {
    await avec('admin', `responsive_${nom}`, async (page) => {
      const fautes = [];
      for (const r of routesAdmin) {
        await aller(page, r);
        const d = await debordeEnLargeur(page);
        if (d > 1) fautes.push(`${r} : la page deborde de ${d}px`);
        // Un tableau dans un conteneur a defilement qui cache des colonnes (actions inaccessibles a premiere vue).
        const caches = await page.evaluate(() => [...document.querySelectorAll('.overflow-x-auto')]
          .filter((c) => c.offsetParent !== null && c.scrollWidth > c.clientWidth + 2).map((c) => `${c.scrollWidth}>${c.clientWidth}`));
        if (caches.length && largeur >= 1280) fautes.push(`${r} : tableau tronque (${caches.join(', ')})`);
        if (largeur <= 768) await capturer(page, `${nom}__${r.replace(/\//g, '_').replace(/^_/, '')}`, { pleinePage: false });
      }
      verifier(fautes.length === 0, fautes.join('\n        '));
    }, { viewport: { width: largeur, height: hauteur } });
  });
}

scenario('responsive telephone : le menu est replie, s\'ouvre au clic (aria-expanded), un lien navigue', async () => {
  await avec('admin', 'menu_telephone', async (page) => {
    await aller(page, '/dashboard');
    const bouton = page.locator('[data-menu-bascule]');
    verifier(await bouton.isVisible(), 'bouton Menu visible sur telephone');
    verifier(!(await page.locator('#menu-principal').isVisible()), 'menu replie au chargement');
    const hautMain = await page.evaluate(() => document.querySelector('main').getBoundingClientRect().top);
    verifier(hautMain < 250, `le contenu commence a ${Math.round(hautMain)}px (menu replie) : il doit rester dans le premier ecran`);
    await bouton.click();
    egal(await bouton.getAttribute('aria-expanded'), 'true', 'aria-expanded apres ouverture');
    await page.locator('#menu-principal a[href$="/clients"]').click();
    await page.waitForURL('**/clients');
  }, { viewport: { width: 390, height: 800 } });
});

scenario('responsive bureau : le bouton Menu est masque et la navigation toujours visible', async () => {
  await avec('admin', 'menu_bureau', async (page) => {
    await aller(page, '/dashboard');
    verifier(!(await page.locator('[data-menu-bascule]').isVisible()), 'pas de bouton Menu sur bureau');
    verifier(await page.locator('#menu-principal').isVisible(), 'navigation visible sur bureau');
  });
});

// ------------------------------------------------------------------------------------------ clavier

scenario('clavier : connexion Tab/Entree ; modale : focus dedans, Tab y reste, Echap la ferme', async () => {
  const { contexte, page } = await visiteur();
  try {
    await aller(page, '/login');
    await page.keyboard.type('admin1');
    await page.keyboard.press('Tab');
    await page.keyboard.type(MDP);
    await Promise.all([page.waitForURL('**/dashboard'), page.keyboard.press('Enter')]);
    await aller(page, '/catalogue');
    await page.click('button:has-text("Ajouter un Produit")');
    await dialogue(page).waitFor();
    verifier(await page.evaluate(() => !!document.activeElement.closest('[role=dialog]')), 'le focus entre dans la modale a l\'ouverture');
    for (let i = 0; i < 14; i++) {
      await page.keyboard.press('Tab');
      verifier(await page.evaluate(() => !!document.activeElement.closest('[role=dialog]')), `Tab ${i + 1} : le focus est sorti de la modale`);
    }
    await page.keyboard.press('Shift+Tab');
    verifier(await page.evaluate(() => !!document.activeElement.closest('[role=dialog]')), 'Maj+Tab reste dans la modale');
    await page.keyboard.press('Escape');
    await dialogue(page).waitFor({ state: 'detached' });
    // Le focus revient sur le bouton d'ouverture.
    verifier(await page.evaluate(() => /Ajouter un Produit/.test(document.activeElement.textContent)), 'le focus revient au bouton d\'ouverture');
    // Entree dans un champ valide le formulaire (champ requis vide : message, pas de fermeture).
    await page.click('button:has-text("Ajouter un Produit")');
    await dialogue(page).waitFor();
    await page.waitForFunction(() => !!document.activeElement.closest('[role=dialog]')); // le focus est entre dans la modale
    await page.keyboard.press('Enter');
    await dialogue(page).locator('[role=alert]').waitFor();
    page.problemes.length = 0;
  } finally { await contexte.close(); }
});

// ------------------------------------------------------------------------------------------ double clic

const DOUBLES = [
  ['catalogue', '/catalogue', 'button:has-text("Ajouter un Produit")', async (d) => {
    await d.getByLabel('Désignation').fill('Doublon Catalogue');
    await d.getByLabel('Catégorie').selectOption('Avicole');
    await d.getByLabel('Tarif indicatif (F)').fill('1000');
    await d.getByLabel('Unité').fill('pièce');
  }, "select count(*) from produits_vendables where name='Doublon Catalogue' and archive_le is null", 'button[type=submit]'],
  ['clients', '/clients', 'button:has-text("Ajouter un Client")', async (d) => { await d.getByLabel('Nom').fill('Doublon Client'); },
    "select count(*) from clients where nom='Doublon Client'", 'button[type=submit]'],
  ['fournisseurs', '/fournisseurs', 'button:has-text("Ajouter un Fournisseur")', async (d) => { await d.getByLabel(/Nom/).fill('Doublon Fournisseur'); },
    "select count(*) from fournisseurs where nom='Doublon Fournisseur'", 'button[type=submit]'],
  ['devis', '/ventes/devis', 'button:has-text("Générer un Devis")', async (d) => {
    await d.getByLabel(/Client/).fill('Doublon Devis'); await d.getByLabel(/Objet/).fill('Prestation'); await d.getByLabel(/Montant Estimé/).fill('1000');
  }, "select count(*) from devis where client='Doublon Devis'", 'button[type=submit]'],
];
scenario('double clic sur « Enregistrer » : catalogue, clients, fournisseurs, devis -> un seul enregistrement', async () => {
  await avec('admin', 'double_clic', async (page) => {
    for (const [nom, route, ouvrirSel, remplir, comptage, soumettre] of DOUBLES) {
      await aller(page, route);
      await page.click(ouvrirSel);
      await dialogue(page).waitFor();
      await remplir(dialogue(page));
      await dialogue(page).locator(soumettre).dblclick();
      await calme(page, 600);
      egal(valeur(comptage), 1, `double clic sur « Enregistrer » (${nom}) : nombre d'enregistrements`);
    }
  });
});

scenario('double clic sur « Encaisser la Vente » : une seule vente', async () => {
  await avec('caissier', 'double_clic_caisse', async (page) => {
    await aller(page, '/ventes');
    const avant = valeur('select count(*) from ventes');
    await page.locator('[data-produit="Lapin"]').click();
    const m = page.locator('[data-modale=vente-a-la-piece]');
    await m.getByLabel(/Quantité/).fill('1');
    await m.getByLabel(/Montant global/).fill('5000');
    await m.locator('button[type=submit]').click();
    await m.waitFor({ state: 'detached' });
    await page.fill('[data-section=panier] input[inputmode=numeric]', '5000');
    await page.locator('button:has-text("Encaisser la Vente")').dblclick();
    await calme(page, 800);
    egal(valeur('select count(*) from ventes') - avant, 1, 'ventes creees par un double clic');
  });
});

// ------------------------------------------------------------------------------------------ reseau, session, onglets

scenario('perte de connexion pendant une action Livewire : message clair, puis reprise', async () => {
  await avec('admin', 'hors_ligne', async (page, contexte) => {
    await aller(page, '/clients');
    await contexte.setOffline(true);
    await page.click('button:has-text("Ajouter un Client")');
    await page.locator('#alerte-reseau:not([hidden])').waitFor({ timeout: 8000 });
    await attendreTexte(page, /Connexion au serveur perdue|hors connexion/, { zone: '#alerte-reseau' });
    await contexte.setOffline(false);
    await page.click('button:has-text("Ajouter un Client")');
    await dialogue(page).waitFor();
    verifier(!(await page.locator('#alerte-reseau').isVisible()), 'le bandeau disparait quand le reseau revient');
    page.problemes.length = 0; // net::ERR_INTERNET_DISCONNECTED attendu
  });
});

scenario('session expiree (cookies perdus -> 419) : message en francais et retour a /login, sans confirm() anglais', async () => {
  await avec('admin', 'session_expiree', async (page, contexte) => {
    await aller(page, '/clients');
    let dialogues = 0;
    page.on('dialog', async (d) => { dialogues++; await d.dismiss(); });
    await contexte.clearCookies();
    await page.click('button:has-text("Ajouter un Client")');
    await page.waitForURL('**/login', { timeout: 10000 });
    egal(dialogues, 0, 'aucun confirm() natif (« This page has expired »)');
    page.problemes.length = 0; // 419 attendu
  });
});

scenario('deux onglets : l\'autre onglet agit sur un element deja supprime -> pas d\'erreur 500', async () => {
  await avec('admin', 'deux_onglets', async (page, contexte) => {
    const autre = await contexte.newPage();
    const erreurs = [];
    autre.on('response', (r) => { if (r.status() >= 500) erreurs.push(`${r.status()} ${r.url()}`); });
    autre.on('pageerror', (e) => erreurs.push(e.message));
    await aller(page, '/clients');
    await aller(autre, '/clients');
    // Onglet 1 : supprime « Marie Dossou ». Onglet 2 (page perimee) : demande la meme suppression.
    await page.locator('tr[data-client="Marie Dossou"] button:has-text("Supprimer")').click();
    await dialogue(page).locator('button:has-text("Supprimer")').click();
    await dialogue(page).waitFor({ state: 'detached' });
    verifier(valeur("select supprime_le from clients where nom='Marie Dossou'"), 'supprime dans l\'onglet 1');
    await autre.locator('tr[data-client="Marie Dossou"] button:has-text("Supprimer")').click();
    await autre.locator('[role=dialog] button:has-text("Supprimer")').click().catch(() => {});
    await calme(autre, 500);
    verifier(erreurs.length === 0, `onglet perime : ${erreurs.join(' | ')}`);
    // Recharger l'onglet 2 : l'element n'y est plus.
    await autre.reload();
    verifier(await autre.locator('tr[data-client="Marie Dossou"]').count() === 0, 'l\'onglet recharge ne montre plus l\'element');
    await autre.close();
    page.problemes.length = 0;
  });
});

scenario('rafraichissement en cours de saisie : la page revient propre (panier et modale remis a zero)', async () => {
  await avec('caissier', 'rafraichissement', async (page) => {
    await aller(page, '/ventes');
    await page.locator('[data-produit="Lapin"]').click();
    const m = page.locator('[data-modale=vente-a-la-piece]');
    await m.getByLabel(/Quantité/).fill('2');
    await page.reload();
    await page.waitForLoadState('networkidle');
    verifier(await page.locator('[data-modale=vente-a-la-piece]').count() === 0, 'la modale ne reste pas figee');
    await attendreTexte(page, 'Panier vide', { zone: '[data-section=panier]' });
    verifier(await page.locator('[data-produit]').count() > 0, 'les produits sont de nouveau cliquables');
  });
});

// ------------------------------------------------------------------------------------------ accessibilite

scenario('accessibilite : tous les champs ont un nom accessible, boutons nommes, langue, titre h1', async () => {
  await avec('admin', 'a11y_champs', async (page) => {
    const fautes = [];
    for (const r of routesAdmin) {
      await aller(page, r);
      const f = await page.evaluate(() => {
        const nom = (el) => {
          if (el.getAttribute('aria-label') || el.getAttribute('aria-labelledby') || el.getAttribute('title')) return true;
          if (el.id && document.querySelector(`label[for="${CSS.escape(el.id)}"]`)) return true;
          if (el.closest('label')) return true;
          return false;
        };
        const visible = (el) => el.offsetParent !== null || getComputedStyle(el).position === 'fixed';
        const champs = [...document.querySelectorAll('main input, main select, main textarea')]
          .filter((e) => e.type !== 'hidden' && visible(e) && !nom(e)).map((e) => `${e.tagName.toLowerCase()}[${e.getAttribute('wire:model') ?? e.getAttribute('wire:model.live') ?? e.name ?? e.type}]`);
        const boutons = [...document.querySelectorAll('main button, main a')].filter((b) => visible(b) && !b.textContent.trim() && !b.getAttribute('aria-label') && !b.getAttribute('title')).length;
        return { champs, boutons, lang: document.documentElement.lang, h1: document.querySelectorAll('h1').length };
      });
      if (f.champs.length) fautes.push(`${r} : champs sans nom accessible : ${f.champs.join(', ')}`);
      if (f.boutons) fautes.push(`${r} : ${f.boutons} bouton(s)/lien(s) sans texte`);
      if (f.lang !== 'fr') fautes.push(`${r} : lang="${f.lang}"`);
      if (f.h1 !== 1) fautes.push(`${r} : ${f.h1} titre(s) h1`);
    }
    verifier(fautes.length === 0, fautes.join('\n        '));
  });
});

const MODALES = [
  ['/catalogue', 'button:has-text("Ajouter un Produit")'], ['/clients', 'button:has-text("Ajouter un Client")'],
  ['/fournisseurs', 'button:has-text("Ajouter un Fournisseur")'], ['/ventes/devis', 'button:has-text("Générer un Devis")'],
  ['/achats', '[data-action=nouvelle-commande]'], ['/comptabilite/journal', '[data-action=nouvelle]'],
  ['/factures-mecef', '[data-action=emettre]'], ['/elevage/couveuse', 'button:has-text("Déclarer un Nouveau Cycle")'],
  ['/elevage/soins', 'button:has-text("Nouveau Soin")'], ['/elevage/lapins', 'button:has-text("Déclarer une Mise en Bande")'],
  ['/comptabilite/plan', '[data-action=nouveau]'],
];
scenario(`accessibilite : ${MODALES.length} modales (role=dialog, aria-modal, nom par aria-labelledby, champs nommes, Echap)`, async () => {
  await avec('admin', 'a11y_modales', async (page) => {
    const fautes = [];
    for (const [route, ouvrirSel] of MODALES) {
      await aller(page, route);
      await page.click(ouvrirSel);
      const d = dialogue(page).first();
      await d.waitFor();
      const f = await d.evaluate((el) => {
        const titre = document.getElementById(el.getAttribute('aria-labelledby') ?? '');
        const sansNom = [...el.querySelectorAll('input, select, textarea')].filter((e) => e.type !== 'hidden' && !e.closest('label')
          && !(e.id && el.querySelector(`label[for="${CSS.escape(e.id)}"]`)) && !e.getAttribute('aria-label')).length;
        return { modal: el.getAttribute('aria-modal'), titre: titre?.textContent.trim() ?? null, sansNom };
      });
      if (f.modal !== 'true') fautes.push(`${route} : aria-modal absent`);
      if (!f.titre) fautes.push(`${route} : aria-labelledby ne designe aucun titre`);
      if (f.sansNom) fautes.push(`${route} : ${f.sansNom} champ(s) de modale sans nom`);
      await page.keyboard.press('Escape');
      try { await d.waitFor({ state: 'detached', timeout: 3000 }); } catch { fautes.push(`${route} : Echap ne ferme pas la modale`); await page.reload(); }
    }
    verifier(fautes.length === 0, fautes.join('\n        '));
  });
});
