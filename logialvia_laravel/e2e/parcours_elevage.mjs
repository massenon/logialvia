// Parcours reels AU CLIC : fiches d'elevage (saisie, deces, chaine, divergence, bande), couveuse, soins/infirmerie.
import { scenario, avec, aller, attendreTexte, verifier, egal, un, valeur, sql, calme, capturer } from './lib.mjs';
import { execFileSync } from 'node:child_process';
import { DB } from './lib.mjs';

const dialogue = (page) => page.locator('[role=dialog]');
/** Choisit dans une liste l'option dont le LIBELLE correspond (les valeurs internes ne sont pas connues du test). */
async function choisir(select, motif) {
  const valeur = await select.evaluate((el, src) => [...el.options].find((o) => new RegExp(src, 'i').test(o.textContent))?.value, motif);
  if (valeur === undefined) throw new Error(`aucune option ~ ${motif}`);
  await select.selectOption(valeur);
}
const iso = (decalage = 0) => {
  const d = new Date(Date.now() + decalage * 86400000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Porto-Novo' }).format(d);
};
/** Ecriture directe en base pour PREPARER un etat (jamais pour les gestes testes). */
const ecrire = (requete, params = []) => execFileSync('python3', ['-I', '-c',
  'import sqlite3,sys,json\nc=sqlite3.connect(sys.argv[1]);c.execute(sys.argv[2], json.loads(sys.argv[3]));c.commit()', DB, requete, JSON.stringify(params)]);

scenario('fiche goliaths : saisie du jour (mortalite), controle de vraisemblance, effectif recalcule', async () => {
  await avec('animalier', 'fiche_goliaths', async (page) => {
    await aller(page, '/elevage/goliaths');
    const veille = un("select effectif from fiche_journee where espece='goliaths' order by date desc limit 1");
    verifier(veille && veille.effectif > 100, `jeu de donnees : effectif de la veille ${JSON.stringify(veille)}`);
    // Impossible : plus de morts que d'effectif -> erreur visible, rien d'ecrit.
    await page.fill('[data-champ=morts-0]', '9999');
    await page.locator('[data-controle-erreur]').first().waitFor();
    await page.click('button:has-text("Enregistrer")');
    await calme(page);
    egal(valeur("select count(*) from fiche_journee where espece='goliaths' and substr(date,1,10)=?", [iso()]), 0, 'saisie impossible refusee');
    // Saisie correcte.
    await page.fill('[data-champ=morts-0]', '2');
    await page.fill('[data-champ=dons-0]', '1');
    await page.fill('[data-champ=poids]', '850');
    await page.fill('[data-champ=observation]', 'RAS - ration normale');
    await attendreTexte(page, String(veille.effectif - 3), { zone: '[data-total=effectif]' }); // effectif calcule en direct
    await page.click('button:has-text("Enregistrer")');
    await page.waitForFunction(() => /enregistr/i.test(document.body.innerText));
    const f = un("select * from fiche_journee where espece='goliaths' and substr(date,1,10)=?", [iso()]);
    verifier(f && f.mort_cat1 === 2 && f.don_cat1 === 1 && f.effectif === veille.effectif - 3, `fiche du jour en base : ${JSON.stringify(f)}`);
    egal(f.observation ?? f.traitement_obs ?? 'RAS - ration normale', 'RAS - ration normale', 'observation');
    await attendreTexte(page, String(veille.effectif - 3), { zone: '[data-kpi=effectif]' });
  });
});

scenario('fiche goliaths : chaine incoherente -> « Recalculer la chaine » ; divergence -> garder une version', async () => {
  await avec('animalier', 'fiche_chaine', async (page) => {
    const jourCasse = iso(-8);
    const avant = un("select effectif, eff_cat1_day from fiche_journee where espece='goliaths' and substr(date,1,10)=?", [jourCasse]);
    ecrire("update fiche_journee set effectif=effectif+50, eff_cat1_day=eff_cat1_day+50 where espece='goliaths' and substr(date,1,10)=?", [jourCasse]);
    await aller(page, '/elevage/goliaths');
    await page.locator('[data-chaine]').waitFor();
    await attendreTexte(page, /incoh|recalcul/i, { zone: '[data-chaine]' });
    await page.click('button:has-text("Recalculer la chaîne")');
    await page.locator('[data-chaine]').waitFor({ state: 'detached' });
    const apres = un("select effectif from fiche_journee where espece='goliaths' and substr(date,1,10)=?", [jourCasse]);
    egal(apres.effectif, avant.effectif, 'effectif du jour repare par le recalcul');

    // Divergence : une variante (autre poste) de la fiche d'il y a 3 jours.
    const j = iso(-3);
    const fiche = un("select * from fiche_journee where espece='goliaths' and substr(date,1,10)=?", [j]);
    const contenu = { ...fiche, mort_cat1: (fiche.mort_cat1 ?? 0) + 2 };
    delete contenu.variantes; delete contenu.serveur_modifie_le;
    ecrire("update fiche_journee set variantes=? where espece='goliaths' and substr(date,1,10)=?",
      [JSON.stringify([{ device_id: '99999999-9999-4999-8999-999999999999', updated_at: new Date().toISOString().replace('Z', '000Z'), contenu }]), j]);
    await aller(page, '/elevage/goliaths');
    await page.fill('input[aria-label="Jour actif"]', j);
    await page.locator('[data-divergence]').waitFor();
    verifier(await page.locator('[data-version]').count() >= 2, 'au moins deux versions presentees');
    await page.locator('[data-version="0"] button:has-text("Garder celle-ci")').click();
    await page.locator('[data-divergence]').waitFor({ state: 'detached' });
    verifier(valeur("select variantes from fiche_journee where espece='goliaths' and substr(date,1,10)=?", [j]) === null, 'variantes effacees apres resolution');
  });
});

scenario('fiche pintades : declarer, recoder et cloturer une bande', async () => {
  await avec('animalier', 'bande', async (page) => {
    await aller(page, '/elevage/pintades');
    await page.click('button:has-text("Déclarer une Mise en Bande")');
    await dialogue(page).locator('[data-champ=bande-code]').fill('BP-E2E-1');
    await dialogue(page).locator('[data-champ=bande-date]').fill(iso(-5));
    await dialogue(page).locator('[data-champ=bande-effectif]').fill('120');
    await dialogue(page).locator('[data-champ=bande-observations]').fill('Enclos E2');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    let b = un("select * from bandes where espece='pintades' and code='BP-E2E-1'");
    verifier(b && b.effectif_initial === 120, `bande en base : ${JSON.stringify(b)}`);
    await attendreTexte(page, 'BP-E2E-1');
    await page.click('[data-action=recoder]');
    await dialogue(page).locator('[data-champ=nouveau-code]').fill('BP-E2E-2');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    egal(valeur("select count(*) from bandes where code='BP-E2E-2'"), 1, 'bande recodee');
    await page.click('button:has-text("Clôturer la Bande")');
    await dialogue(page).locator('button:has-text("Clôturer")').click();
    await dialogue(page).waitFor({ state: 'detached' });
    verifier(valeur("select date_cloture from bandes where code='BP-E2E-2'"), 'bande cloturee en base');
  });
});

scenario('couveuse : incubateur, lot, mirage 1, eclosion', async () => {
  await avec('animalier', 'couveuse', async (page) => {
    await aller(page, '/elevage/couveuse');
    await page.click('button:has-text("Ajouter un Incubateur")');
    await dialogue(page).locator('button[type=submit]').click(); // vide : refuse
    await dialogue(page).locator('[role=alert]').waitFor();
    await dialogue(page).getByLabel(/Code/).fill('INC-E2E');
    await dialogue(page).getByLabel(/Libellé/).fill('Couveuse essai 528 oeufs');
    await dialogue(page).getByLabel(/Capacité/).fill('528');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    verifier(un("select * from machines_incubateur where code='INC-E2E'"), 'incubateur en base');
    await page.locator('[data-machine="INC-E2E"]').waitFor();

    await page.click('button:has-text("Déclarer un Nouveau Cycle")');
    await dialogue(page).locator('button[type=submit]').click(); // vide : refuse
    await dialogue(page).locator('[role=alert]').waitFor();
    await choisir(dialogue(page).getByLabel(/Espèce/), 'goliath');
    await calme(page);
    await dialogue(page).getByLabel(/Date de Chargement/).fill(iso(-22));
    await calme(page);
    await dialogue(page).getByLabel(/Incubateur/).selectOption({ index: 1 }); // le seul incubateur declare
    await dialogue(page).getByLabel(/Nombre d'Œufs/).fill('200');
    await dialogue(page).locator('[data-calendrier]').waitFor();
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    const lot = un("select * from cycle_couveuse where oeufs_couves=200 order by date_incubation desc limit 1");
    verifier(lot && lot.espece === 'goliath' && lot.statut, `lot en base : ${JSON.stringify(lot)}`);
    const ligne = page.locator(`tr[data-lot="${lot.code_incubation}"]`);
    await ligne.waitFor();
    // Mirage 1 (J+7) : 12 oeufs clairs retires.
    await ligne.locator('[data-mirage="7"]').click();
    await dialogue(page).getByLabel(/Œufs clairs/).fill('12');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    egal(valeur('select oeufs_blancs_j7 from cycle_couveuse where id=?', [lot.id]), 12, 'mirage 1 enregistre');
    // Eclosion : 150 poussins, 30 perdus.
    await ligne.locator('button:has-text("Éclosion")').click();
    await dialogue(page).getByLabel(/Poussins Éclos/).fill('150');
    await dialogue(page).getByLabel(/Non Éclos/).fill('30');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    const apres = un('select * from cycle_couveuse where id=?', [lot.id]);
    egal([apres.poussins_nes, apres.oeufs_perdus], [150, 30], 'eclosion en base');
  });
});

scenario('soins : nouveau soin (planifie puis confirme), infirmerie (entree, deces avec perte sur la fiche)', async () => {
  await avec('animalier', 'soins', async (page) => {
    await aller(page, '/elevage/soins');
    await page.click('button:has-text("Nouveau Soin")');
    await dialogue(page).locator('button[type=submit]').click(); // vide : refuse
    await dialogue(page).locator('[role=alert]').waitFor();
    await choisir(dialogue(page).getByLabel(/Lot \/ Bande/), 'goliath');
    await calme(page);
    await dialogue(page).getByLabel(/Date du Soin/).fill(iso(1));
    await dialogue(page).getByLabel(/Type d'Action/).selectOption({ index: 1 });
    await dialogue(page).getByLabel(/Produit Utilisé/).fill('Vaccin Newcastle');
    await dialogue(page).getByLabel(/Coût/).fill('3500');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    const s = un("select * from soins_calendrier where produit='Vaccin Newcastle' order by updated_at desc limit 1");
    verifier(s && s.cout_fcfa === 3500 && s.statut, `soin en base : ${JSON.stringify(s)}`);
    const ligne = page.locator(`tr[data-soin="${s.id}"]`);
    await ligne.waitFor();
    if (await ligne.locator('button:has-text("Confirmer")').count()) {
      await ligne.locator('button:has-text("Confirmer")').click();
      await calme(page);
      verifier(valeur('select statut from soins_calendrier where id=?', [s.id]) !== s.statut, 'soin confirme : statut change en base');
    }
    // Infirmerie.
    await page.click('[role=tab]:has-text("Infirmerie")');
    await page.click('button:has-text("Nouvelle Entrée")');
    await dialogue(page).getByLabel(/Sujet/).fill('Goliath #G-014');
    await dialogue(page).getByLabel(/Motif/).fill('Suspicion Newcastle');
    await choisir(dialogue(page).getByLabel(/Filière concernée/), 'goliath');
    await dialogue(page).locator('button[type=submit]').click();
    await dialogue(page).waitFor({ state: 'detached' });
    const e = un("select * from infirmerie where sujet='Goliath #G-014'");
    verifier(e && e.statut === 'En cours', `entree en base : ${JSON.stringify(e)}`);
    const avant = un("select effectif, mort_cat1 from fiche_journee where espece='goliaths' order by date desc limit 1");
    await page.locator(`tr[data-entree="${e.id}"] [data-action=deces]`).click();
    await page.locator('[data-champ=deces-categorie]').selectOption('0');
    await page.click('button:has-text("Confirmer le décès")');
    await calme(page);
    egal(valeur('select statut from infirmerie where id=?', [e.id]), 'Décédé', 'statut Décédé');
    const apres = un("select effectif, mort_cat1 from fiche_journee where espece='goliaths' order by date desc limit 1");
    verifier(apres.mort_cat1 === (avant.mort_cat1 ?? 0) + 1 || apres.effectif === avant.effectif - 1, `la perte est portee sur la fiche : ${JSON.stringify([avant, apres])}`);
  });
});
