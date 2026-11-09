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
