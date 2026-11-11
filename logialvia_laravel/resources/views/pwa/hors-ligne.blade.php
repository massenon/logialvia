<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="theme-color" content="#1F3864">
    <title>Hors ligne — LogiALVIA</title>
    {{-- Page AUTONOME (precachee par le service worker) : aucun fichier externe, elle doit s'afficher sans reseau. --}}
    <style>
        body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#152847;color:#fff;font-family:system-ui,sans-serif;padding:24px}
        main{max-width:28rem;text-align:center}
        h1{font-size:22px;margin:0 0 12px}
        p{font-size:14px;line-height:1.5;opacity:.9;margin:0 0 16px}
        button{background:#B58B2A;color:#1F3864;font-weight:700;border:0;border-radius:999px;padding:10px 20px;font-size:14px;cursor:pointer}
    </style>
</head>
<body>
    <main>
        <h1>Vous êtes hors ligne</h1>
        <p>LogiALVIA a besoin du réseau pour afficher vos données : rien n'est perdu, rien n'a été envoyé à moitié. Vérifiez votre connexion puis réessayez.</p>
        <p>Pour vendre ou saisir sans réseau, utilisez le logiciel LogiALVIA du poste Windows : il se synchronise tout seul au retour de la connexion.</p>
        <button type="button" onclick="location.reload()">Réessayer</button>
    </main>
</body>
</html>
