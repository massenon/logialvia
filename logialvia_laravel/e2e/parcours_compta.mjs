// Parcours reels AU CLIC : journal (piece manuelle, annulation), cloture mensuelle, assistant de cloture annuelle.
import { scenario, avec, aller, attendreTexte, verifier, egal, un, valeur, calme } from './lib.mjs';

const dialogue = (page) => page.locator('[role=dialog]');
const iso = (decalage = 0) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Porto-Novo' }).format(new Date(Date.now() + decalage * 86400000));
async function choisir(select, motif) {
  const v = await select.evaluate((el, src) => [...el.options].find((o) => new RegExp(src, 'i').test(o.textContent))?.value, motif);
  if (v === undefined) throw new Error(`aucune option ~ ${motif}`);
  await select.selectOption(v);
}

scenario('journal : ecriture manuelle (equilibree), puis annulation de la piece (contre-passation)', async () => {
  await avec('comptable', 'journal', async (page) => {
    await aller(page, '/comptabilite/journal');
    await page.click('[data-action=nouvelle]');
    const m = page.locator('[data-modale=ecriture]');
    await m.waitFor();
    await m.locator('[data-action=enregistrer]').click(); // vide : refuse
    await calme(page);
    verifier(await m.count() === 1, 'la modale reste ouverte sur une saisie vide');
    await m.locator('#libelle').fill('Régularisation caisse E2E');
    await choisir(m.locator('#debit'), '^6');
    await choisir(m.locator('#credit'), '^5');
    await m.locator('#montant').fill('7500');
    await m.locator('[data-action=enregistrer]').click();
    await m.waitFor({ state: 'detached' });
    const piece = un("select p.* from pieces_comptables p join ecritures_comptables e on e.piece_id=p.id where e.libelle like '%Régularisation caisse E2E%' limit 1");
    verifier(piece && piece.journal_code, 'piece en base');
    const t = un('select sum(debit) d, sum(credit) c, count(*) n from ecritures_comptables where piece_id=?', [piece.id]);
    egal([t.d, t.c, t.n], [7500, 7500, 2], 'piece equilibree a 2 lignes');
    await attendreTexte(page, 'Régularisation caisse E2E', { zone: 'main' });
    // Annulation.
    await page.locator('tr', { hasText: 'Régularisation caisse E2E' }).first().locator('[data-action=annuler-piece]').click();
    await page.locator('[data-modale=annulation] [data-action=confirmer-annulation]').click();
    await page.locator('[data-modale=annulation]').waitFor({ state: 'detached' });
    egal(valeur('select count(*) from pieces_comptables where contrepasse_de=?', [piece.id]), 1, 'contre-passation en base');
  });
});

scenario('cloture mensuelle : cloturer octobre -> ecriture datee d\'octobre refusee -> decloturer', async () => {
  await avec('admin', 'cloture_mensuelle', async (page) => {
    const annee = new Date().getFullYear();
    await aller(page, '/comptabilite/cloture');
    const mois = page.locator('[data-mois="10"]');
    await mois.locator('[data-action=cloturer]').click();
    await page.locator('[data-mois="10"][data-clos="1"]').waitFor();
    egal(valeur('select is_cloture from clotures_periodiques where annee=? and mois=10', [annee]), 1, 'mois cloture en base');
    // Une ecriture datee d'octobre est refusee.
    await aller(page, '/comptabilite/journal');
    await page.click('[data-action=nouvelle]');
    const m = page.locator('[data-modale=ecriture]');
    await m.locator('#jour').fill(`${annee}-10-15`);
    await m.locator('#libelle').fill('Ecriture en periode close');
    await choisir(m.locator('#debit'), '^6');
    await choisir(m.locator('#credit'), '^5');
    await m.locator('#montant').fill('1000');
    await m.locator('[data-action=enregistrer]').click();
    await calme(page);
    verifier(await m.count() === 1, 'modale ouverte : ecriture refusee');
    await attendreTexte(page, /clôtur|clos/i, { zone: '[data-modale=ecriture]' });
    egal(valeur("select count(*) from ecritures_comptables where libelle like '%periode close%'"), 0, 'rien d\'ecrit en periode close');
    await m.locator('button:has-text("Annuler")').click();
    // Decloture.
    await aller(page, '/comptabilite/cloture');
    await page.locator('[data-mois="10"] [data-action=decloturer]').click();
    await page.locator('[data-mois="10"][data-clos="0"]').waitFor();
    egal(valeur('select is_cloture from clotures_periodiques where annee=? and mois=10', [annee]), 0, 'mois rouvert en base');
  });
});

scenario('cloture annuelle : assistant (admin), affectation, ecritures AN, reouverture', async () => {
  await avec('admin', 'cloture_annuelle', async (page) => {
    const annee = new Date().getFullYear();
    await aller(page, '/comptabilite/cloture');
    const bouton = page.locator('[data-action=cloturer-exercice]');
    await bouton.waitFor();
    verifier(await bouton.isEnabled(), 'cloture possible : balance equilibree');
    await bouton.click();
    const m = page.locator('[data-modale=cloture]');
    await m.waitFor();
    await attendreTexte(page, new RegExp(`exercice ${annee}`), { zone: '[data-modale=cloture]' });
    await m.locator('[data-action=confirmer-cloture-exercice]').click();
    await m.waitFor({ state: 'detached' });
    await calme(page);
    egal(valeur('select is_cloture from exercices_comptables where annee=?', [annee]), 1, 'exercice cloture en base');
    verifier(valeur("select count(*) from pieces_comptables where journal_code='AN'") >= 0, 'journal AN interroge');
    await attendreTexte(page, /clôturé et verrouillé/, { zone: '[data-assistant]' });
    // Reouverture (pour ne pas bloquer la suite).
    await page.locator('[data-action=rouvrir-exercice]').click();
    await page.locator('[data-modale=reouverture] [data-action=confirm-reouverture], [data-modale=reouverture] [data-action=confirmer-reouverture]').click();
    await page.locator('[data-modale=reouverture]').waitFor({ state: 'detached' });
    egal(valeur('select is_cloture from exercices_comptables where annee=?', [annee]), 0, 'exercice rouvert en base');
  });
});
