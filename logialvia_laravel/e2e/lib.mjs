// Outils de la suite navigateur : cadre de scenarios, surveillance des erreurs, connexion, lecture de la base.
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// ESM ignore NODE_PATH : on passe par `require` pour trouver `playwright` (installation globale, sans reseau).
const { chromium } = createRequire(import.meta.url)('playwright');

export const ICI = path.dirname(fileURLToPath(import.meta.url));
export const URL_BASE = process.env.LV_URL ?? 'http://127.0.0.1:8799';
export const MDP = process.env.LV_MDP ?? 'EssaiPoste-2026!';
export const DB = process.env.LV_DB;
export const DOSSIER = process.env.LV_DOSSIER ?? '/tmp/lv-e2e';
export const CAPTURES = path.join(ICI, 'captures');
export const TELECHARGEMENTS = path.join(DOSSIER, 'telechargements');
fs.mkdirSync(CAPTURES, { recursive: true });
fs.mkdirSync(TELECHARGEMENTS, { recursive: true });

export const COMPTES = { admin: 'admin1', comptable: 'comptable1', caissier: 'caissier1', animalier: 'animalier1' };

// ------------------------------------------------------------------------------------------ assertions

export class Echec extends Error {}
export function verifier(condition, message) {
  if (!condition) throw new Echec(message);
}
export function egal(obtenu, attendu, message) {
  if (JSON.stringify(obtenu) !== JSON.stringify(attendu)) {
    throw new Echec(`${message} : obtenu ${JSON.stringify(obtenu)}, attendu ${JSON.stringify(attendu)}`);
  }
}

// ------------------------------------------------------------------------------------------ base de donnees

/** Interroge la base SQLite jetable (Python, sans dependance) : retourne un tableau d'objets. */
export function sql(requete, params = []) {
  const prog = 'import sqlite3,sys,json\nc=sqlite3.connect(sys.argv[1]);c.row_factory=sqlite3.Row\n'
    + 'r=[dict(x) for x in c.execute(sys.argv[2], json.loads(sys.argv[3]))]\nprint(json.dumps(r))';
  return JSON.parse(execFileSync('python3', ['-I', '-c', prog, DB, requete, JSON.stringify(params)], { encoding: 'utf8' }));
}
export const un = (requete, params) => sql(requete, params)[0] ?? null;
export const valeur = (requete, params) => { const l = un(requete, params); return l ? Object.values(l)[0] : null; };

// ------------------------------------------------------------------------------------------ surveillance d'une page

/** Ecoute une page : tout ce qui est anormal est range dans `page.problemes` (verifie par `sansProbleme`). */
export function surveiller(page, { tolerer = [] } = {}) {
  page.problemes = [];
  const tolere = (txt) => tolerer.some((t) => (t instanceof RegExp ? t.test(txt) : txt.includes(t)));
  const noter = (txt) => { if (!tolere(txt)) page.problemes.push(txt); };
  page.on('console', (m) => { if (m.type() === 'error') noter(`console.error : ${m.text()} (${m.location().url})`); });
  page.on('pageerror', (e) => noter(`pageerror : ${e.message}`));
  page.on('requestfailed', (r) => {
    const f = r.failure()?.errorText ?? '';
    if (f.includes('ERR_ABORTED')) return; // navigation interrompue par la suivante : normal
    noter(`requete echouee : ${r.method()} ${r.url()} ${f}`);
  });
  page.on('response', (r) => {
    if (!r.url().startsWith(URL_BASE) || r.status() < 400) return;
    noter(`HTTP ${r.status()} : ${r.request().method()} ${r.url()}`);
  });
}
export function sansProbleme(page, contexte = '') {
  const p = page.problemes.splice(0);
  verifier(p.length === 0, `${contexte} problemes navigateur :\n  - ${p.join('\n  - ')}`);
}

// ------------------------------------------------------------------------------------------ navigateur et sessions

let navigateur;
export async function lancerNavigateur() {
  const options = { args: ['--no-sandbox'] };
  try { navigateur = await chromium.launch(options); } catch {
    navigateur = await chromium.launch({ ...options, executablePath: '/opt/pw-browsers/chromium' });
  }
  return navigateur;
}
export const fermerNavigateur = () => navigateur?.close();

const etats = {};

/** Se connecte AU CLIC sur /login. */
export async function connecter(page, identifiant, mdp = MDP) {
  await page.goto('/login');
  await page.fill('#identifiant', identifiant);
  await page.fill('#password', mdp);
  await Promise.all([page.waitForURL((u) => !u.pathname.startsWith('/login')), page.click('button[type=submit]')]);
}

/** Contexte neuf, deja connecte (la connexion est faite UNE fois par role puis reutilisee). */
export async function ouvrir(role, options = {}) {
  const identifiant = COMPTES[role] ?? role;
  if (!etats[identifiant]) {
    const c = await navigateur.newContext({ baseURL: URL_BASE, deviceScaleFactor: 1 });
    const p = await c.newPage();
    await connecter(p, identifiant);
    etats[identifiant] = await c.storageState();
    await c.close();
  }
  const contexte = await navigateur.newContext({
    baseURL: URL_BASE, deviceScaleFactor: 1, viewport: { width: 1280, height: 800 }, locale: 'fr-FR', timezoneId: 'Africa/Porto-Novo',
    acceptDownloads: true, storageState: etats[identifiant], ...options,
  });
  const page = await contexte.newPage();
  surveiller(page, options.surveillance);
  page.setDefaultTimeout(10000);
  return { contexte, page };
}
export const oublierSessions = () => { for (const k of Object.keys(etats)) delete etats[k]; };

export async function visiteur(options = {}) {
  const contexte = await navigateur.newContext({ baseURL: URL_BASE, deviceScaleFactor: 1, viewport: { width: 1280, height: 800 }, locale: 'fr-FR', timezoneId: 'Africa/Porto-Novo', acceptDownloads: true, ...options });
  const page = await contexte.newPage();
  surveiller(page, options.surveillance);
  page.setDefaultTimeout(10000);
  return { contexte, page };
}

// ------------------------------------------------------------------------------------------ gestes Livewire

/** Attend que Livewire n'ait plus de requete en cours (`wire:loading` termine) : file d'attente vide + reseau calme. */
export async function calme(page, ms = 150) {
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.waitForTimeout(ms);
}

export async function aller(page, route) {
  const r = await page.goto(route);
  await page.waitForLoadState('networkidle').catch(() => {});
  return r;
}

/** Texte visible normalise de la zone principale. */
export const texteMain = async (page) => (await page.locator('main').innerText()).replace(/\s+/g, ' ');

/** Attend (sondage) qu'un texte apparaisse dans la zone voulue ; echec lisible avec le texte reel sinon. */
export async function attendreTexte(page, texte, { zone = 'body', delai = 8000 } = {}) {
  const motif = texte instanceof RegExp ? texte : new RegExp(texte.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  try {
    await page.waitForFunction(([z, src, fl]) => new RegExp(src, fl).test(document.querySelector(z)?.innerText.replace(/\s+/g, ' ') ?? ''), [zone, motif.source, motif.flags], { timeout: delai });
  } catch {
    const reel = (await page.locator(zone).first().innerText()).replace(/\s+/g, ' ').slice(0, 600);
    throw new Echec(`texte ${motif} absent de « ${zone} » ; vu : ${reel}`);
  }
}

export async function capturer(page, nom, { pleinePage = true } = {}) {
  const f = path.join(CAPTURES, `${nom.replace(/[^a-z0-9_.-]+/gi, '_')}.png`);
  await page.screenshot({ path: f, fullPage: pleinePage });
  return f;
}

/** Defilement horizontal de la PAGE (pas d'un tableau a defilement interne) ? */
export const debordeEnLargeur = (page) => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);

/** Execute `fn(page, contexte)` dans un contexte connecte ; sur echec : capture `echec__<nom>.png` et problemes navigateur. */
export async function avec(role, nom, fn, options = {}) {
  const { contexte, page } = await ouvrir(role, options);
  try {
    await fn(page, contexte);
    sansProbleme(page, nom);
  } catch (e) {
    await capturer(page, `echec__${nom}`).catch(() => {});
    if (page.problemes?.length) e.message += `\n  [navigateur] ${page.problemes.join('\n  [navigateur] ')}`;
    throw e;
  } finally {
    await contexte.close();
  }
}

// ------------------------------------------------------------------------------------------ cadre de scenarios

const scenarios = [];
export function scenario(nom, fn) { scenarios.push({ nom, fn }); }

export async function executerScenarios(filtre = '') {
  const resultats = [];
  for (const s of scenarios) {
    if (filtre && !new RegExp(filtre, 'i').test(s.nom)) continue;
    const t0 = Date.now();
    try {
      await s.fn();
      resultats.push({ nom: s.nom, ok: true, ms: Date.now() - t0 });
      console.log(`  OK   ${s.nom} (${Date.now() - t0} ms)`);
    } catch (e) {
      resultats.push({ nom: s.nom, ok: false, ms: Date.now() - t0, erreur: e });
      console.log(`  ECHEC ${s.nom}\n        ${String(e.message ?? e).split('\n').join('\n        ')}`);
    }
  }
  return resultats;
}
