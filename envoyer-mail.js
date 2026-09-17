// ============================================================
// Appel générique de l'Edge Function "envoyer-mail-formulaire".
// À utiliser par n'importe quel formulaire Suivi une fois son PDF
// (pdf-lib) prêt : construire sujet/corps, convertir le PDF en base64,
// puis appeler envoyerMailFormulaire(). Contrairement à l'ancien appel
// Apps Script en mode:'no-cors', celui-ci répond normalement — en cas
// d'échec, on le sait et on peut prévenir la personne qui saisit.
// ============================================================

async function envoyerMailFormulaire({ sujet, corps, pdfBytes, pdfNomFichier, emailClient, nomClient }) {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) throw new Error("Session expirée — reconnectez-vous puis réessayez.");

    const url = SUPABASE_URL + '/functions/v1/envoyer-mail-formulaire';
    const pdfBase64 = arrayBufferToBase64(pdfBytes);

    const resp = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + session.access_token,
            'apikey': SUPABASE_ANON_KEY,
        },
        body: JSON.stringify({ sujet, corps, pdfBase64, pdfNomFichier, emailClient, nomClient }),
    });

    let result = {};
    try { result = await resp.json(); } catch (e) { /* réponse non-JSON, traité ci-dessous */ }

    if (!resp.ok || !result.ok) {
        throw new Error(result.error || ('Échec de l\'envoi (HTTP ' + resp.status + ')'));
    }
    return result; // { ok: true, destinataires: [...] }
}

function arrayBufferToBase64(bytesOrBuffer) {
    const bytes = bytesOrBuffer instanceof Uint8Array ? bytesOrBuffer : new Uint8Array(bytesOrBuffer);
    let binary = '';
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(binary);
}
