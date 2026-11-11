/*
 * PWA (47x_) : enregistrement du service worker et fenetre d'installation. Charge A LA DEMANDE (import dynamique
 * depuis app.js, apres l'evenement `load`) : ni l'un ni l'autre ne retarde l'affichage de la page.
 *
 * Le service worker est VOLONTAIREMENT etroit (voir ServiceWorkerController) : il accelere le rechargement des
 * fichiers statiques et affiche une page d'attente quand le reseau tombe ; il ne rend PAS le site utilisable hors
 * ligne (le travail hors ligne est celui du poste Windows, via /api/sync).
 */
if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => {});
}

const CLE_REFUS = 'logialvia_installation_refusee';
let invite = null;

function refuse() {
    try { return localStorage.getItem(CLE_REFUS) === '1'; } catch { return false; }
}

window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    if (refuse() || document.getElementById('pwa-installer')) return;
    invite = e;
    const boite = document.createElement('div');
    boite.id = 'pwa-installer';
    boite.setAttribute('role', 'dialog');
    boite.setAttribute('aria-label', "Installer l'application");
    boite.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:60;max-width:22rem;padding:12px 16px;border-radius:8px;'
        + 'background:#1F3864;color:#fff;font-size:14px;box-shadow:0 4px 16px rgba(0,0,0,.3);display:flex;gap:12px;align-items:center';
    boite.innerHTML = '<span style="flex:1">Installer LogiALVIA sur cet appareil ?</span>'
        + '<button type="button" data-pwa="installer" style="background:#B58B2A;color:#1F3864;font-weight:700;padding:6px 12px;border-radius:999px">Installer</button>'
        + '<button type="button" data-pwa="plus-tard" aria-label="Plus tard" style="color:#fff;opacity:.8;padding:4px 8px">✕</button>';
    boite.querySelector('[data-pwa=installer]').addEventListener('click', async () => {
        boite.remove();
        invite.prompt();
        await invite.userChoice;
        invite = null;
    });
    boite.querySelector('[data-pwa=plus-tard]').addEventListener('click', () => {
        boite.remove();
        try { localStorage.setItem(CLE_REFUS, '1'); } catch { /* navigation privee : tant pis */ }
    });
    // Affichee a la premiere interaction (ou apres 8 s) : un bandeau de texte pose pendant le chargement pouvait devenir
    // le « plus grand element » de la page et retarder le LCP mesure (rapports mobile > 2 s).
    const montrer = () => {
        ['pointerdown', 'keydown', 'scroll'].forEach((t) => window.removeEventListener(t, montrer, true));
        if (!document.getElementById('pwa-installer') && invite) document.body.appendChild(boite);
    };
    ['pointerdown', 'keydown', 'scroll'].forEach((t) => window.addEventListener(t, montrer, { capture: true, once: true, passive: true }));
    setTimeout(montrer, 8000);
});

window.addEventListener('appinstalled', () => document.getElementById('pwa-installer')?.remove());
