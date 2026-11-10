import './bootstrap';

/*
 * Saisie « debounce » puis clic immediat (47n_) : `wire:model.live.debounce.300ms` ne met l'etat du composant a jour
 * qu'APRES le delai ; un clic donne dans les 300 ms qui suivent la frappe partait donc avec l'ANCIENNE valeur
 * (ex. « Encaisser la Vente » : « Veuillez saisir le montant recu »). A la perte du focus ou a la validation d'un
 * formulaire, on pousse la valeur dans l'etat local du composant (sans requete : `set(..., false)`), qui accompagne
 * alors l'action.
 */
function pousserSaisiesEnAttente(racine) {
    const champs = racine instanceof HTMLInputElement || racine instanceof HTMLTextAreaElement
        ? [racine]
        : racine.querySelectorAll('input, textarea');
    champs.forEach((champ) => {
        const attribut = [...champ.attributes].find((a) => a.name.startsWith('wire:model') && a.name.includes('debounce'));
        const composant = champ.closest('[wire\\:id]');
        if (!attribut || !composant || !window.Livewire) return;
        window.Livewire.find(composant.getAttribute('wire:id'))?.set(attribut.value, champ.value, false);
    });
}
document.addEventListener('focusout', (e) => {
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) pousserSaisiesEnAttente(e.target);
});
document.addEventListener('submit', (e) => pousserSaisiesEnAttente(e.target), true);

// Menu replie sur telephone : le bouton « Menu » montre/cache la navigation (le CSS la garde toujours visible des `md`).
document.addEventListener('click', (e) => {
    const bouton = e.target.closest('[data-menu-bascule]');
    if (!bouton) return;
    const menu = document.getElementById(bouton.getAttribute('aria-controls'));
    const ouvert = bouton.getAttribute('aria-expanded') === 'true';
    bouton.setAttribute('aria-expanded', ouvert ? 'false' : 'true');
    menu.classList.toggle('hidden', ouvert);
});

/*
 * Reseau et session (47n_). Livewire 3.1 laisse l'utilisateur sans nouvelle quand le reseau tombe (statut 503, aucun
 * message) et affiche, pour une session expiree (419), un `confirm()` en anglais. On dit les choses en francais :
 *  - reseau perdu : bandeau « action non enregistree », qui disparait des qu'une requete reussit ;
 *  - session expiree : message puis retour a la connexion.
 */
function alerte(texte, { fixe = false } = {}) {
    let b = document.getElementById('alerte-reseau');
    if (!b) {
        b = document.createElement('div');
        b.id = 'alerte-reseau';
        b.setAttribute('role', 'alert');
        b.style.cssText = 'position:fixed;left:16px;right:16px;bottom:16px;z-index:70;max-width:32rem;margin:auto;padding:12px 16px;'
            + 'border-radius:8px;background:#ba1a1a;color:#fff;font-size:14px;box-shadow:0 4px 16px rgba(0,0,0,.3)';
        document.body.appendChild(b);
    }
    b.textContent = texte;
    b.hidden = false;
    b.dataset.fixe = fixe ? '1' : '';
}
function masquerAlerte() {
    const b = document.getElementById('alerte-reseau');
    if (b && !b.dataset.fixe) b.hidden = true;
}
document.addEventListener('livewire:init', () => {
    window.Livewire.hook('request', ({ succeed, fail }) => {
        succeed(() => masquerAlerte());
        fail(({ status, content, preventDefault }) => {
            if (status === 419) {
                preventDefault();
                alerte('Votre session a expiré : retour à la page de connexion…', { fixe: true });
                setTimeout(() => window.location.assign('/login'), 1500);
            } else if (status === 503 && content === null) {
                alerte("Connexion au serveur perdue : l'action n'a pas été enregistrée. Vérifiez le réseau puis recommencez.");
            }
        });
    });
});
window.addEventListener('online', masquerAlerte);
window.addEventListener('offline', () => alerte('Vous êtes hors connexion : les actions ne seront pas enregistrées tant que le réseau ne revient pas.'));

/*
 * Modales (47n_) : a l'ouverture le focus entre dans la fenetre, Tab y reste, Echap la ferme (bouton « Annuler »/« Fermer »
 * de la modale), et le focus revient la ou il etait. Sans cela, le clavier continuait de parcourir la page cachee derriere.
 */
const FOCALISABLES = 'a[href], button:not([disabled]), input:not([disabled]):not([type=hidden]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
let avantModale = null;
function modaleOuverte() {
    const l = [...document.querySelectorAll('[role=dialog]')];
    return l[l.length - 1] ?? null;
}
new MutationObserver(() => {
    const m = modaleOuverte();
    if (m && !m.dataset.focalise) {
        m.dataset.focalise = '1';
        avantModale = avantModale ?? document.activeElement;
        const premier = m.querySelector('input:not([disabled]):not([type=hidden]):not([readonly]), select:not([disabled]), textarea:not([disabled])') ?? m.querySelector(FOCALISABLES);
        premier?.focus();
    } else if (!m && avantModale) {
        if (avantModale.isConnected) avantModale.focus();
        avantModale = null;
    }
}).observe(document.documentElement, { childList: true, subtree: true });
document.addEventListener('keydown', (e) => {
    const m = modaleOuverte();
    if (!m) return;
    if (e.key === 'Escape') {
        const sortie = [...m.querySelectorAll('button')].find((b) => /^(annuler|fermer|renoncer)/i.test(b.getAttribute('wire:click') ?? ''));
        if (sortie) { e.preventDefault(); sortie.click(); }
    } else if (e.key === 'Tab') {
        const f = [...m.querySelectorAll(FOCALISABLES)].filter((x) => x.offsetParent !== null);
        if (f.length === 0) return;
        const premier = f[0];
        const dernier = f[f.length - 1];
        if (e.shiftKey && (document.activeElement === premier || !m.contains(document.activeElement))) { e.preventDefault(); dernier.focus(); }
        else if (!e.shiftKey && (document.activeElement === dernier || !m.contains(document.activeElement))) { e.preventDefault(); premier.focus(); }
    }
});
