// Point d'entree : `node e2e/executer.mjs [filtre]` (via `e2e/lancer.sh`, qui prepare serveur et base jetables).
import fs from 'node:fs';
import path from 'node:path';
import { lancerNavigateur, fermerNavigateur, executerScenarios, DOSSIER } from './lib.mjs';

const filtre = process.argv[2] ?? '';
await lancerNavigateur();
// L'ordre des fichiers est celui de la suite : fumee -> parcours -> transversaux.
for (const f of ['fumee', 'parcours_commerce', 'parcours_documents', 'parcours_achats', 'parcours_elevage', 'parcours_compta', 'parcours_admin', 'transversaux']) {
  if (fs.existsSync(new URL(`./${f}.mjs`, import.meta.url))) await import(`./${f}.mjs`);
}
console.log(`\nSuite navigateur LogiALVIA${filtre ? ` (filtre « ${filtre} »)` : ''}\n`);
const resultats = await executerScenarios(filtre);
await fermerNavigateur();

const ko = resultats.filter((r) => !r.ok);
fs.writeFileSync(path.join(DOSSIER, 'resultats.json'), JSON.stringify(resultats.map((r) => ({ nom: r.nom, ok: r.ok, ms: r.ms, erreur: r.erreur?.message })), null, 2));
console.log(`\n${resultats.length - ko.length}/${resultats.length} scenarios reussis.`);
process.exit(ko.length ? 1 : 0);
