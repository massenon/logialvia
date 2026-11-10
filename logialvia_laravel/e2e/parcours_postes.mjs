// Parcours reel AU CLIC : Postes & Appairage (revocation) et journal d'audit.
import { scenario, avec, aller, attendreTexte, verifier, egal, valeur, calme } from './lib.mjs';

scenario('postes : revoquer l\'appairage (annuler puis confirmer) ; la revocation est tracee dans le journal d\'audit', async () => {
  await avec('admin', 'postes', async (page) => {
    await aller(page, '/parametres/postes');
    const ligne = page.locator('tr[data-poste="P1"]');
    await ligne.waitFor();
    await ligne.locator('button:has-text("Révoquer")').click();
    await page.locator('[role=dialog] button:has-text("Annuler")').click();
    await page.locator('[role=dialog]').waitFor({ state: 'detached' });
    egal(valeur("select revoque_le from postes where code='P1'"), null, 'annuler ne revoque pas');
    await ligne.locator('button:has-text("Révoquer")').click();
    await page.locator('[role=dialog] button:has-text("Révoquer l\'appairage")').click();
    await page.locator('[role=dialog]').waitFor({ state: 'detached' });
    verifier(valeur("select revoque_le from postes where code='P1'"), 'poste revoque en base');
    await aller(page, '/parametres/audit');
    await attendreTexte(page, /révoqué/i, { zone: 'main' });
    verifier(valeur("select count(*) from audit_logs where action like '%revoq%'") >= 1, 'ligne d\'audit en base');
  });
});
