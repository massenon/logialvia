// Transversaux (3/3) : on clique tous les onglets/filtres de chaque ecran ; les modales sur telephone.
import fs from 'node:fs';
import path from 'node:path';
import { scenario, avec, aller, verifier, calme, capturer, sansProbleme, DOSSIER } from './lib.mjs';

const matrice = JSON.parse(fs.readFileSync(path.join(DOSSIER, 'matrice.json'), 'utf8'));
const routesAdmin = [...Object.keys(matrice.routes), '/parametres/postes', '/parametres/audit', '/ventes/devis'];
const dialogue = (page) => page.locator('[role=dialog]');

scenario('onglets et filtres : on clique TOUS les onglets, boutons de filtre et options de listes de chaque ecran (aucune erreur)', async () => {
  await avec('admin', 'onglets_filtres', async (page) => {
    let gestes = 0;
    for (const r of routesAdmin) {
      await aller(page, r);
      const n = await page.locator('[role=tab]:visible').count();
      for (let i = 0; i < n; i++) {
        await page.locator('[role=tab]:visible').nth(i).click();
        await calme(page, 120);
        gestes++;
        const t = (await page.locator('main').innerText()).slice(0, 4000);
        verifier(!/SQLSTATE|Undefined (variable|array)|Exception|Stack trace/.test(t), `${r} onglet ${i} : trace d'erreur visible`);
        sansProbleme(page, `${r} onglet ${i}`);
      }
      const filtres = await page.locator('main [data-filtre]:visible').count();
      for (let i = 0; i < filtres; i++) { await page.locator('main [data-filtre]:visible').nth(i).click(); await calme(page, 120); gestes++; }
      const listes = await page.locator('main select[wire\\:model\\.live]:visible').count();
      for (let i = 0; i < listes; i++) {
        const liste = page.locator('main select[wire\\:model\\.live]:visible').nth(i);
        const options = await liste.locator('option').count();
        for (let o = 0; o < Math.min(options, 4); o++) { await liste.selectOption({ index: o }); await calme(page, 120); gestes++; }
      }
      sansProbleme(page, `${r} filtres`);
    }
    verifier(gestes > 50, `trop peu de gestes (${gestes})`);
  });
});

scenario('telephone : les modales tiennent dans l\'ecran (largeur) et se defilent (hauteur)', async () => {
  await avec('admin', 'modales_telephone', async (page) => {
    const fautes = [];
    for (const [route, ouvrirSel] of [['/catalogue', 'button:has-text("Ajouter un Produit")'], ['/achats', '[data-action=nouvelle-commande]'],
      ['/elevage/soins', 'button:has-text("Nouveau Soin")'], ['/elevage/couveuse', 'button:has-text("Déclarer un Nouveau Cycle")'],
      ['/comptabilite/journal', '[data-action=nouvelle]'], ['/factures-mecef', '[data-action=emettre]']]) {
      await aller(page, route);
      await page.click(ouvrirSel);
      const d = dialogue(page).first();
      await d.waitFor();
      const g = await page.evaluate(() => {
        const f = document.querySelector('[role=dialog]');
        const carte = f.firstElementChild?.getBoundingClientRect();
        return { gauche: Math.round(carte.left), droite: Math.round(carte.right), largeur: innerWidth, defile: getComputedStyle(f).overflowY, hauteurCarte: Math.round(carte.height), hauteur: innerHeight };
      });
      if (g.gauche < 0 || g.droite > g.largeur + 1) fautes.push(`${route} : modale hors ecran (${g.gauche}..${g.droite} / ${g.largeur})`);
      if (g.hauteurCarte > g.hauteur && !/auto|scroll/.test(g.defile)) fautes.push(`${route} : modale plus haute que l'ecran (${g.hauteurCarte} > ${g.hauteur}) sans defilement`);
      if (route === '/catalogue' || route === '/achats') await capturer(page, `telephone_modale_${route.replace(/\//g, '')}`, { pleinePage: false });
      await page.keyboard.press('Escape');
      await d.waitFor({ state: 'detached' }).catch(() => {});
    }
    verifier(fautes.length === 0, fautes.join('\n        '));
  }, { viewport: { width: 390, height: 700 } });
});
