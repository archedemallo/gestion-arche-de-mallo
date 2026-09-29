// ============================================================
// Edge Function "generer-pdf-formulaire"
// ============================================================
// Reçoit le HTML déjà rempli d'un formulaire (voir generer-pdf.js
// côté client, qui construit ce HTML à partir de buildHtmlWithData())
// et renvoie un vrai PDF, produit par un navigateur Chromium hébergé
// chez Cloudflare (Browser Rendering) — remplace l'ancien pipeline
// html2canvas + jsPDF exécuté dans le navigateur du bénévole, dont le
// rendu s'est révélé trop fragile (PDF vides ou tronqués).
//
// Même principe d'authentification que "envoyer-mail-formulaire" :
// le client envoie le jeton de session Supabase, on vérifie qu'il
// correspond à un utilisateur connecté avant d'appeler Cloudflare.
//
// Secrets à définir avant le premier déploiement
// (Dashboard Supabase → Edge Functions → Secrets, ou :
//   supabase secrets set CF_ACCOUNT_ID=... CF_API_TOKEN=...) :
//   CF_ACCOUNT_ID — identifiant du compte Cloudflare
//   CF_API_TOKEN  — jeton API avec la permission "Browser Rendering - Edit"
// (SUPABASE_URL et SUPABASE_ANON_KEY sont fournis automatiquement par
// Supabase à toutes les Edge Functions, rien à configurer pour eux.)
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const CF_ACCOUNT_ID = Deno.env.get('CF_ACCOUNT_ID');
const CF_API_TOKEN = Deno.env.get('CF_API_TOKEN');

const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
}

// Encodage base64 par blocs — un simple `String.fromCharCode(...bytes)`
// dépasse la pile d'appel sur un PDF de plusieurs centaines de Ko.
function toBase64(bytes: Uint8Array): string {
    let binaire = '';
    const taillePaquet = 0x8000;
    for (let i = 0; i < bytes.length; i += taillePaquet) {
        binaire += String.fromCharCode.apply(null, Array.from(bytes.subarray(i, i + taillePaquet)));
    }
    return btoa(binaire);
}

Deno.serve(async (req: Request) => {
    if (req.method === 'OPTIONS') {
        return new Response(null, { headers: CORS_HEADERS });
    }
    if (req.method !== 'POST') {
        return jsonResponse({ ok: false, error: 'Méthode non autorisée.' }, 405);
    }

    if (!CF_ACCOUNT_ID || !CF_API_TOKEN) {
        console.error('generer-pdf-formulaire: secrets CF_ACCOUNT_ID / CF_API_TOKEN manquants.');
        return jsonResponse({ ok: false, error: 'Génération PDF non configurée côté serveur (secrets Cloudflare manquants).' }, 500);
    }

    try {
        // Vérifie que la requête vient bien d'un utilisateur connecté.
        const authHeader = req.headers.get('Authorization') || '';
        const supabaseClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
            global: { headers: { Authorization: authHeader } },
        });
        const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
        if (authError || !user) {
            return jsonResponse({ ok: false, error: 'Session expirée — reconnectez-vous puis réessayez.' }, 401);
        }

        const { html } = await req.json();
        if (!html || typeof html !== 'string') {
            return jsonResponse({ ok: false, error: 'HTML manquant dans la requête.' }, 400);
        }

        const cfResp = await fetch(
            `https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/browser-rendering/pdf`,
            {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${CF_API_TOKEN}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    html,
                    // Le HTML envoyé porte déjà toutes les valeurs saisies
                    // (voir buildHtmlWithData() côté client) : aucun script
                    // n'est nécessaire à l'affichage, et désactiver le JS
                    // évite que les scripts de la page (client Supabase,
                    // sélecteurs...) s'exécutent côté serveur.
                    setJavaScriptEnabled: false,
                    // Applique les règles @media print si jamais certaines
                    // n'ont pas été mises à plat côté client.
                    emulateMediaType: 'print',
                    gotoOptions: { waitUntil: 'load', timeout: 30000 },
                    pdfOptions: {
                        format: 'a4',
                        printBackground: true,
                        margin: { top: '8mm', bottom: '8mm', left: '8mm', right: '8mm' },
                    },
                }),
            }
        );

        if (!cfResp.ok) {
            const detail = await cfResp.text();
            console.error('Cloudflare Browser Rendering error:', cfResp.status, detail);
            return jsonResponse(
                { ok: false, error: 'Échec de la génération du PDF (service Cloudflare, HTTP ' + cfResp.status + ').' },
                502
            );
        }

        const pdfBytes = new Uint8Array(await cfResp.arrayBuffer());
        return jsonResponse({ ok: true, pdfBase64: toBase64(pdfBytes) });
    } catch (e) {
        console.error('generer-pdf-formulaire error:', e);
        return jsonResponse({ ok: false, error: 'Erreur interne lors de la génération du PDF.' }, 500);
    }
});
