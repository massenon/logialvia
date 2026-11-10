// Parcours reels AU CLIC : devis de prestations et factures normalisees MeCeF.
import { scenario, avec, aller, verifier, egal, un, valeur, calme } from './lib.mjs';

const dialogue = (page) => page.locator('[role=dialog]');

scenario('devis : creer, statut, imprimer (page imprimable), dupliquer, supprimer', async () => {
  await avec('caissier', 'devis', async (page, contexte) => {
    await aller(page, '/ventes/devis');
    await page.click('button:has-text("Générer un Devis")');
    await dialogue(page).locator('button[type=submit]').click(); // vide : refuse
    await dialogue(page).locator('[role=alert]').waitFor();
    await dialogue(page).getByLabel(/Client/).fill('Mairie de Ouidah');
    await dialogue(page).getByLabel(/Objet/).fill('Fourniture de 50 poulets de chair');
    await dialogue(page).getByLabel(/Montant Estimé/).fill('175000');
    await dialogue(page).getByLabel(/Validité/).fill('30');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    const d = un("select * from devis where client='Mairie de Ouidah'");
    verifier(d && d.montant_estime === 175000 && d.validite_jours === 30 && d.statut === 'emis', `devis en base : ${JSON.stringify(d)}`);
    await page.locator(`tr[data-devis="${d.reference}"]`).waitFor();
    // Statut -> accepte.
    await page.locator(`tr[data-devis="${d.reference}"] [data-action=statut-accepte]`).click();
    await calme(page);
    egal(valeur('select statut from devis where id=?', [d.id]), 'accepte', 'devis accepte en base');
    // Imprimer : ouvre la page imprimable dans un nouvel onglet.
    const [onglet] = await Promise.all([contexte.waitForEvent('page'), page.locator(`tr[data-devis="${d.reference}"] [data-action=imprimer]`).click()]);
    await onglet.waitForLoadState();
    verifier((await onglet.locator('body').innerText()).includes('Mairie de Ouidah'), 'page imprimable du devis');
    await onglet.close();
    // Dupliquer.
    await page.locator(`tr[data-devis="${d.reference}"] [data-action=dupliquer]`).click();
    await calme(page);
    egal(valeur("select count(*) from devis where client='Mairie de Ouidah'"), 2, 'devis duplique');
    // Supprimer la copie (« emis ») : modale de confirmation.
    const copie = un("select * from devis where client='Mairie de Ouidah' and statut='emis'");
    await page.locator(`tr[data-devis="${copie.reference}"] [data-action=supprimer]`).click();
    await dialogue(page).locator('button:has-text("Supprimer")').click();
    await dialogue(page).waitFor({ state: 'detached' });
    verifier(valeur('select supprime_le from devis where id=?', [copie.id]), 'devis supprime (corbeille) en base');
  });
});

scenario('factures MeCeF : emission depuis une vente, impression, avoir', async () => {
  await avec('comptable', 'factures', async (page, contexte) => {
    await aller(page, '/factures-mecef');
    await page.click('[data-action=emettre]');
    const f = page.locator('[data-form=emission]');
    await f.waitFor();
    await f.locator('button[type=submit]').click(); // aucune vente choisie : refuse
    await f.locator('[role=alert]').waitFor();
    const venteId = valeur("select id from ventes where client='Amina Bako' and status='Payée' limit 1");
    await f.locator('select').selectOption(venteId);
    await f.getByLabel(/IFU du client/).fill('3201234567890');
    await f.locator('button[type=submit]').click();
    await f.waitFor({ state: 'detached' });
    const fac = un("select * from factures where vente_ref=(select reference from ventes where id=?) and type='FV'", [venteId]);
    verifier(fac && fac.total_ttc > 0 && fac.client_ifu === '3201234567890', `facture en base : ${JSON.stringify(fac)}`);
    // Detail puis impression.
    // L'emission ouvre deja le detail de la facture ; sinon on l'ouvre par la ligne.
    if (!(await page.locator(`[data-detail="${fac.reference}"]`).count())) await page.locator(`tr[data-facture="${fac.reference}"]`).click();
    const detail = page.locator(`[data-detail="${fac.reference}"]`);
    await detail.waitFor();
    const [onglet] = await Promise.all([contexte.waitForEvent('page'), detail.locator('[data-action=imprimer]').click()]);
    await onglet.waitForLoadState();
    verifier((await onglet.locator('body').innerText()).includes(fac.reference), 'facture imprimable');
    await onglet.close();
    // Avoir total.
    await detail.locator('[data-action=avoir]').click();
    const a = page.locator('[data-form=avoir]');
    await a.waitFor();
    await a.locator('button[type=submit]').click(); // motif vide : refuse
    await a.locator('[role=alert]').waitFor();
    await a.getByLabel(/Motif de l'avoir/).fill('Retour marchandise');
    await a.locator('button[type=submit]').click();
    await a.waitFor({ state: 'detached' });
    const avoir = un("select * from factures where type='FA' and origine_ref=?", [fac.reference]);
    verifier(avoir && Math.abs(avoir.total_ttc - fac.total_ttc) < 0.01, `avoir en base : ${JSON.stringify(avoir)}`);
  });
});
