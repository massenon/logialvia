// Transversaux navigateur (1/2) : pages imprimables, exports XLSX (ouverts avec openpyxl), impression (media print + PDF).
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import { scenario, avec, aller, verifier, egal, un, valeur, calme, capturer, sansProbleme, ouvrir, TELECHARGEMENTS, ICI, attendreTexte } from './lib.mjs';

const ids = () => ({
  vente: valeur("select id from ventes where status='Payée' order by date_vente limit 1"),
  achat: valeur('select id from achats limit 1'),
  fournisseur: valeur('select id from fournisseurs where supprime_le is null limit 1'),
  facture: valeur('select id from factures limit 1'),
  devis: valeur('select id from devis where supprime_le is null limit 1'),
  venteCredit: valeur("select id from ventes where status='Avance' limit 1"),
});

scenario('impressions : toutes les vues imprimables (200, pas d\'erreur, menus absents, contenu), interdites aux autres roles', async () => {
  const i = ids();
  const routes = [
    '/achats/impression', `/achats/${i.achat}/bon`, '/fournisseurs/impression', `/fournisseurs/${i.fournisseur}/releve`, '/stocks/impression',
    '/depenses/impression', `/factures-mecef/${i.facture}/imprimer`, `/ventes/devis/${i.devis}/imprimer`, '/impression/ventes/historique',
    `/impression/ventes/${i.vente}/facture`, '/impression/clients/creances', `/impression/clients/relance/${i.venteCredit}`,
  ];
  await avec('admin', 'impressions', async (page) => {
    for (const r of routes) {
      verifier(!/undefined|null/.test(r), `identifiant manquant pour ${r}`);
      const rep = await page.goto(r);
      await page.waitForLoadState('networkidle').catch(() => {});
      egal(rep.status(), 200, `impression ${r}`);
      sansProbleme(page, r);
      const texte = (await page.locator('body').innerText()).replace(/\s+/g, ' ');
      verifier(texte.length > 80, `${r} : page quasi vide`);
      verifier(!/Exception|SQLSTATE|Undefined/.test(texte), `${r} : trace visible`);
      verifier(await page.locator('aside[aria-label=Navigation]').count() === 0, `${r} : la barre laterale ne doit pas figurer dans une vue imprimable`);
      await capturer(page, `impression__${r.replace(/[^a-z0-9]+/gi, '_').slice(0, 60)}`);
    }
  });
  // Un role sans le droit : 403.
  await avec('animalier', 'impressions_interdites', async (page) => {
    for (const r of ['/achats/impression', '/depenses/impression', '/impression/ventes/historique', `/factures-mecef/${i.facture}/imprimer`]) {
      egal((await page.goto(r)).status(), 403, `animalier ${r}`);
    }
    page.problemes.length = 0;
  });
});

const EXPORTS = [
  ['/ventes', async (p) => { await p.click('[data-onglet=historique]'); await p.waitForSelector('[data-action=exporter-historique]'); }, '[data-action=exporter-historique]', 'ventes'],
  ['/clients', async (p) => { await p.click('[data-onglet-client=dettes]'); }, 'button[wire\\:click=exporterCreances]', 'creances'],
  ['/ventes/devis', null, 'button[wire\\:click=exporter]', 'devis'],
  ['/factures-mecef', null, 'button[wire\\:click=exporter]', 'factures'],
  ['/achats', null, 'button[wire\\:click=exporter]', 'achats'],
  ['/fournisseurs', null, 'button[wire\\:click=exporter]', 'fournisseurs'],
  ['/depenses', null, 'button[wire\\:click=exporter]', 'depenses'],
  ['/stocks', null, 'button[wire\\:click^=exporter]', 'stocks'],
  ['/comptabilite/plan', null, 'button[wire\\:click=exporter]', 'plan'],
  ['/comptabilite/journal', null, 'button[wire\\:click^=exporter]', 'journal'],
  ['/comptabilite/grand-livre', null, 'button[wire\\:click^=exporter]', 'grand-livre'],
  ['/comptabilite/balance', null, 'button[wire\\:click^=exporter]', 'balance'],
  ['/elevage/goliaths', null, 'button[wire\\:click=exporter]', 'fiche-goliaths'],
  ['/parametres/audit', null, 'button[wire\\:click=exporter]', 'audit'],
  ['/rapports', null, 'button[wire\\:click^=exporter]', 'rapports'],
];

scenario(`exports XLSX : ${EXPORTS.length} ecrans, fichier ouvert avec openpyxl (titre, en-tete, nombres types, colonnes)`, async () => {
  await avec('admin', 'exports', async (page) => {
    const rapport = [];
    for (const [route, avant, selecteur, nom] of EXPORTS) {
      await aller(page, route);
      if (avant) await avant(page);
      const bouton = page.locator(selecteur).first();
      verifier(await bouton.count() > 0, `${route} : pas de bouton d'export (${selecteur})`);
      const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 15000 }), bouton.click()]);
      const fichier = path.join(TELECHARGEMENTS, `${nom}.xlsx`);
      await dl.saveAs(fichier);
      verifier(/\.xlsx$/i.test(dl.suggestedFilename()), `${route} : nom de fichier « ${dl.suggestedFilename()} »`);
      const r = JSON.parse(execFileSync('python3', ['-I', path.join(ICI, 'verifier_xlsx.py'), fichier], { encoding: 'utf8' }));
      const f = r.details[0];
      verifier(f.lignes >= 1 && f.colonnes >= 2, `${route} : classeur vide ou a une colonne ${JSON.stringify(f)}`);
      verifier(!f.entete_vide, `${route} : en-tete avec cellule vide ${JSON.stringify(f.entete)}`);
      verifier(f.titre && f.titre !== 'Worksheet', `${route} : feuille sans titre (« ${f.titre} »)`);
      verifier(f.textes_numeriques.length === 0, `${route} : nombres ranges en TEXTE ${JSON.stringify(f.textes_numeriques)}`);
      rapport.push(`${nom}: ${f.lignes} l. x ${f.colonnes} c., ${f.numeriques} nombres typés, feuille « ${f.titre} »`);
      sansProbleme(page, route);
    }
    fs.writeFileSync(path.join(TELECHARGEMENTS, 'rapport-exports.txt'), rapport.join('\n'));
  });
});

scenario('impression navigateur : media print + PDF (menus masques, tableaux entiers, pas de debordement)', async () => {
  const routes = ['/ventes', '/clients', '/achats', '/fournisseurs', '/depenses', '/comptabilite/journal', '/comptabilite/balance', '/comptabilite/plan',
    '/elevage/goliaths', '/rapports', '/stocks', '/catalogue', '/factures-mecef'];
  await avec('admin', 'impression_media', async (page) => {
    for (const r of routes) {
      await aller(page, r);
      await page.emulateMedia({ media: 'print' });
      const etat = await page.evaluate(() => {
        const visible = (el) => el && getComputedStyle(el).display !== 'none' && el.getBoundingClientRect().width > 0;
        const tables = [...document.querySelectorAll('table')].filter(visible);
        return {
          aside: visible(document.querySelector('aside[aria-label=Navigation]')),
          header: visible(document.querySelector('body > div > div > header')),
          boutons: [...document.querySelectorAll('main button')].filter(visible).length,
          debordePage: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          tableauxCoupes: tables.filter((t) => t.getBoundingClientRect().right > document.documentElement.clientWidth + 1).length,
          conteneursCaches: [...document.querySelectorAll('.overflow-x-auto')].filter((c) => visible(c) && c.scrollWidth > c.clientWidth + 1).length,
        };
      });
      verifier(!etat.aside, `${r} (print) : barre laterale visible`);
      verifier(!etat.header, `${r} (print) : barre du haut visible`);
      egal(etat.boutons, 0, `${r} (print) : boutons visibles`);
      verifier(etat.debordePage <= 1, `${r} (print) : debordement horizontal de ${etat.debordePage}px`);
      egal(etat.tableauxCoupes, 0, `${r} (print) : tableaux coupes a droite`);
      egal(etat.conteneursCaches, 0, `${r} (print) : tableau a defilement cache`);
      const pdf = await page.pdf({ format: 'A4', printBackground: true });
      verifier(pdf.length > 3000, `${r} : PDF trop petit (${pdf.length} o)`);
      fs.writeFileSync(path.join(TELECHARGEMENTS, `print${r.replace(/\//g, '_')}.pdf`), pdf);
      await page.emulateMedia({ media: 'screen' });
    }
  });
});
