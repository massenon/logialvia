import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';

export default defineConfig({
    plugins: [
        laravel({
            input: ['resources/css/app.css', 'resources/js/app.js'],
            refresh: true,
        }),
    ],
    build: {
        rollupOptions: {
            output: {
                // 47x_ : Livewire + Alpine (~150 Ko) dans leur propre fichier, hache a part : il ne change qu'a la mise a jour
                // de Livewire, donc reste en cache (navigateur + service worker) quand le code de l'application change.
                manualChunks(id) {
                    if (id.includes('livewire/livewire') || id.includes('node_modules/alpinejs') || id.includes('node_modules/@alpinejs')) {
                        return 'vendor-livewire';
                    }
                },
            },
        },
    },
    server: {
        watch: {
            ignored: ['**/storage/framework/views/**'],
        },
    },
});
