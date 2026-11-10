/**
 * Jetons de design de LogiALVIA — la SOURCE est le code Dart du poste
 * (`logialvia_app/lib/core/theme/*.dart`). Rien n'est reconstruit de memoire :
 * `tests/Unit/ConformiteDartTest.php` compare ce fichier au Dart et echoue au
 * moindre ecart. Modifier une valeur ici sans la modifier dans le Dart (ou
 * l'inverse) casse la conformite.
 */
import forms from '@tailwindcss/forms';

/** @type {import('tailwindcss').Config} */
export default {
    content: [
        './resources/**/*.blade.php',
        './resources/**/*.js',
        './app/Livewire/**/*.php',
        './vendor/livewire/livewire/src/**/*.php',
    ],
    theme: {
        // Breakpoints du Dart : AppBreakpoints (sm, md, lg, xl).
        screens: {
            sm: '640px',
            md: '768px',
            lg: '1024px',
            xl: '1280px',
        },
        extend: {
            colors: {
                // AppColors
                'brand-navy': '#1F3864',
                'brand-navy-dark': '#152847',
                'brand-gold': '#B58B2A',
                'brand-gold-light': '#D4A94D',
                'surface-bg': '#F2F2F2',
                'surface-card': '#FFFFFF',
                'surface-zebra': '#F7F7F8',
                'outline-variant': '#D8DCE3',
                outline: '#6B7280',
                'on-surface': '#1A1D23',
                'error-deep': '#B33A3A',
                'error-container': '#FBE3E3',
                'success-deep': '#3A7D44',
                'success-container': '#E1F0E3',
                'info-blue': '#2563EB',
            },
            // AppSpacing : xs, sm, md, lg, xl.
            spacing: {
                xs: '4px',
                sm: '8px',
                md: '16px',
                lg: '24px',
                xl: '32px',
            },
            // AppRadius : card (rounded-lg), loginCard (rounded-2xl).
            borderRadius: {
                lg: '8px',
                '2xl': '16px',
            },
            fontFamily: {
                sans: ['Roboto', 'ui-sans-serif', 'system-ui', 'sans-serif'],
            },
            // AppTypography : textXs = 13,6 px, puis les styles nommes.
            fontSize: {
                xs: ['13.6px', { lineHeight: '1.5' }],
                'page-title': ['22px', { lineHeight: '1.25' }],
                'modal-title': ['18px', { lineHeight: '1.3' }],
                'section-title': ['16px', { lineHeight: '1.35' }],
                body: ['14px', { lineHeight: '1.5' }],
                caption: ['12px', { lineHeight: '1.4' }],
                'kpi-value': ['24px', { lineHeight: '1.2' }],
                invalid: ['11px', { lineHeight: '1.4' }],
            },
        },
    },
    plugins: [forms],
};
