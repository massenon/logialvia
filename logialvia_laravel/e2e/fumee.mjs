// Fumee : TOUTES les routes de la matrice `config/logialvia.php`, pour chaque role.
import fs from 'node:fs';
import path from 'node:path';
import { scenario, ouvrir, visiteur, aller, sansProbleme, verifier, egal, capturer, DOSSIER } from './lib.mjs';

const matrice = JSON.parse(fs.readFileSync(path.join(DOSSIER, 'matrice.json'), 'utf8'));
const ROLES = ['admin', 'comptable', 'caissier', 'animalier'];
const droitsDe = (role) => (matrice.role_permissions[role] === '*' ? matrice.permissions : matrice.role_permissions[role]);
const autorise = (role, route) => {
  const [permission] = matrice.routes[route];
  return permission === null || droitsDe(role).includes(permission);
};
// Routes propres au web (hors matrice) : meme droit que la matrice des ecrans voisins.
const SUPPLEMENTAIRES = { '/parametres/postes': 'manage-users', '/parametres/audit': 'manage-users', '/ventes/devis': 'view-ventes' };
const autoriseSupp = (role, route) => droitsDe(role).includes(SUPPLEMENTAIRES[route]);

const toutes = [...Object.keys(matrice.routes), ...Object.keys(SUPPLEMENTAIRES)];

// Liens de la barre laterale, par role : ceux de l'administrateur filtres par les droits du role.
async function lienLateraux(page) {
  return page.$$eval('aside[aria-label="Navigation"] a[href]', (as) => as.map((a) => new URL(a.href).pathname));
}

for (const role of ROLES) {
  scenario(`fumee ${role} : ${toutes.length} routes (200/403, console, Livewire, titre, barre laterale)`, async () => {
    const { contexte, page } = await ouvrir(role);
    try {
      const ouvertes = [];
      for (const route of toutes) {
        const permis = route in SUPPLEMENTAIRES ? autoriseSupp(role, route) : autorise(role, route);
        const reponse = await page.goto(route);
        await page.waitForLoadState('networkidle').catch(() => {});
        const statut = reponse.status();
        if (!permis) {
          // Un 403 est la reponse ATTENDUE : on le retire des problemes, mais on exige qu'il soit net.
          egal(statut, 403, `${role} ${route} doit etre interdit`);
          page.problemes.length = 0;
          const corps = (await page.locator('body').innerText()).slice(0, 300);
          verifier(!/Exception|Stack trace|SQLSTATE/i.test(corps), `${role} ${route} : le 403 laisse voir une trace : ${corps}`);
          continue;
        }
        egal(statut, 200, `${role} ${route} doit s'ouvrir`);
        const titre = await page.title();
        verifier(/ — LogiALVIA$/.test(titre) && !/^ — /.test(titre) && !/undefined|null/.test(titre), `${role} ${route} : titre « ${titre} »`);
        verifier(!/Cet écran arrive bientôt/.test(await page.locator('main').innerText()), `${role} ${route} : page « à venir »`);
        sansProbleme(page, `${role} ${route}`);
        // Barre laterale : aucun lien interdit, et aucun lien sans route.
        const liens = await lienLateraux(page);
        for (const l of liens) {
          if (l === '/dashboard' || l.startsWith('/#')) continue;
          const ok = l in SUPPLEMENTAIRES ? autoriseSupp(role, l) : (l in matrice.routes ? autorise(role, l) : false);
          verifier(ok, `${role} ${route} : la barre laterale montre ${l}, interdit a ce role`);
        }
        ouvertes.push(route);
        await capturer(page, `${role}__${route.replace(/\//g, '_').replace(/^_/, '')}`);
      }
      verifier(ouvertes.length > 0, `${role} : aucune route ouverte`);
      // Chaque lien interdit n'est PAS dans la barre ; chaque route autorisee de l'admin presente dans sa barre l'est aussi ici.
      await aller(page, '/dashboard');
      const miens = new Set(await lienLateraux(page));
      for (const route of toutes) {
        const permis = route in SUPPLEMENTAIRES ? autoriseSupp(role, route) : autorise(role, route);
        if (!permis) verifier(!miens.has(route), `${role} : ${route} apparait dans la barre alors qu'il est interdit`);
      }
    } finally {
      await contexte.close();
    }
  });
}

scenario('fumee : la barre laterale de chaque role = celle de l\'admin filtree par droits', async () => {
  const lire = async (role) => {
    const { contexte, page } = await ouvrir(role);
    await aller(page, '/dashboard');
    const l = await page.$$eval('aside[aria-label="Navigation"] a[href]', (as) => as.map((a) => new URL(a.href).pathname));
    await contexte.close();
    return l;
  };
  const admin = await lire('admin');
  for (const role of ['comptable', 'caissier', 'animalier']) {
    const attendu = admin.filter((l) => (l in SUPPLEMENTAIRES ? autoriseSupp(role, l) : (l in matrice.routes ? autorise(role, l) : true)));
    egal(await lire(role), attendu, `barre laterale du role ${role}`);
  }
});

scenario('fumee visiteur : toute route redirige vers /login (les imprimables aussi)', async () => {
  const { contexte, page } = await visiteur();
  try {
    for (const route of [...toutes, '/depenses/impression', '/impression/ventes/historique', '/achats/impression']) {
      await page.goto(route);
      verifier(new URL(page.url()).pathname === '/login', `visiteur ${route} -> ${page.url()}`);
    }
    page.problemes.length = 0; // 302 -> /login : aucun 4xx attendu, mais on ne juge pas la page de connexion ici
  } finally {
    await contexte.close();
  }
});

scenario('fumee : /login (titre, champs etiquetes, capture)', async () => {
  const { contexte, page } = await visiteur();
  try {
    await aller(page, '/login');
    verifier((await page.title()).includes('LogiALVIA'), 'titre de /login');
    verifier(await page.locator('label[for=identifiant]').count() === 1 && await page.locator('label[for=password]').count() === 1, 'labels de /login');
    sansProbleme(page, '/login');
    await capturer(page, 'visiteur__login');
  } finally {
    await contexte.close();
  }
});
