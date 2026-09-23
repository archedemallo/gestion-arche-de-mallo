// ============================================================
// CONFIGURATION SUPABASE — un seul fichier à modifier pour tout le site
// (Suivi ET Compta). Toutes les pages chargent ce fichier avant de
// créer leur supabaseClient.
// ============================================================
const SUPABASE_URL = 'https://tjefuqqceazdxyhcjupt.supabase.co';       // <-- à remplacer
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqZWZ1cXFjZWF6ZHh5aGNqdXB0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4MDAzMDEsImV4cCI6MjEwNDM3NjMwMX0.d-IEnu_A4Fb0xECYax0JZy8CI6OzfHMVkSJ9Cvay0uM'

// ============================================================
// CRÉATION DU CLIENT + GESTION DES ÉCHECS DE CHARGEMENT — le SDK est
// chargé depuis un CDN (voir la balise <script src="...supabase-js@..."
// dans chaque page) ; si le CDN est lent/indisponible au chargement,
// window.supabase peut être indéfini au moment où on l'utilise, ce qui
// cassait silencieusement toute la page (l'écran de connexion restait
// affiché indéfiniment, sans message). Toutes les pages doivent créer
// leur client via creerClientSupabase() (jamais directement
// window.supabase.createClient(...)) pour bénéficier du garde-fou.
// ============================================================
function creerClientSupabase() {
    if (typeof window.supabase === 'undefined') {
        afficherErreurChargement();
        throw new Error('SDK Supabase non chargé (window.supabase indéfini) — vérifiez la connexion internet.');
    }
    return window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}

// Affiche un message explicite + un lien "Réessayer" dans la zone
// #login-err (présente sur toutes les pages Suivi et Compta), au lieu
// de laisser l'écran de connexion bloqué sans explication.
function afficherErreurChargement(err) {
    if (err) console.error('[Connexion]', err);
    var el = document.getElementById('login-err');
    if (el) el.innerHTML = 'Le chargement a échoué. <a href="#" onclick="location.reload();return false;" style="font-weight:bold;">Réessayer</a>';
}

