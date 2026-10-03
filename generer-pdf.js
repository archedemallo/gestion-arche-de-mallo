// ============================================================
// GÉNÉRATION DU PDF — rendu par un vrai navigateur côté serveur
// ============================================================

const FACTEUR_TAILLE_PDF = 0.50;

/**
 * Récupère TOUT le CSS de la page courante (règles normales + celles de
 * "@media print", ces dernières sans leur condition) et le renvoie comme
 * un unique bloc de règles normales, les règles d'impression en dernier
 * (donc prioritaires à spécificité égale, comme le ferait le mode
 * impression du navigateur).
 *
 * Indispensable ici aussi : le Chromium serveur reçoit du HTML brut,
 * sans URL de page d'origine, donc il ne peut pas résoudre l'URL
 * relative de formulaires-arche-mallo.css. Sans ce CSS réinjecté en
 * clair, la mise en forme de base disparaît (largeurs de champs,
 * positionnement...).
 */
function _reglesCompletesEnClair() {
    let base = '';
    let impression = '';
    for (const feuille of document.styleSheets) {
        let regles;
        try { regles = feuille.cssRules; } catch (e) { continue; } // feuille externe/CORS, ignorée
        for (const regle of regles) {
            if (regle instanceof CSSMediaRule && /print/i.test(regle.media.mediaText)) {
                for (const interieure of regle.cssRules) impression += interieure.cssText + '\n';
            } else {
                base += regle.cssText + '\n';
            }
        }
    }
        const reduction =
        'body { zoom: ' + FACTEUR_TAILLE_PDF + '; }\n' +
        '.content { max-width: calc(21cm / ' + FACTEUR_TAILLE_PDF + ') !important; }\n' +
        // En-tête en 3 colonnes : logo à gauche, texte de l'association
        // réellement centré sur la page, date / "Saisi par" à droite.
        '.header-adoption { display: grid !important; grid-template-columns: 1fr auto 1fr; align-items: center !important; }\n' +
        '.header-adoption > div:first-child { display: contents !important; }\n' +
        '.header-adoption .logo-box { justify-self: start; margin: 0 !important; }\n' +
        '.header-adoption .header-info { justify-self: center; margin: 0 !important; }\n' +
        '.header-adoption .header-adoption-right { justify-self: end; }\n';
    return base + '\n' + impression + '\n' + reduction;
}

/**
 * Remplace toutes les occurrences de "logo_arche.png" (favicon +
 * logo affiché) par une image encodée en base64, chargée depuis la
 * page actuelle. Sans ça, le Chromium serveur — qui ne connaît pas
 * l'URL de la page d'origine — ne pourrait pas afficher le logo.
 * En cas d'échec (page hors-ligne, fichier renommé...), le PDF part
 * quand même, simplement sans logo, plutôt que d'échouer entièrement.
 */
async function _logoEnBase64DansHtml(html) {
    if (html.indexOf('logo_arche.png') === -1) return html;
    try {
        const reponse = await fetch('logo_arche.png');
        if (!reponse.ok) return html;
        const blob = await reponse.blob();
        const dataUrl = await new Promise((resolve, reject) => {
            const lecteur = new FileReader();
            lecteur.onload = () => resolve(lecteur.result);
            lecteur.onerror = reject;
            lecteur.readAsDataURL(blob);
        });
        return html.split('logo_arche.png').join(dataUrl);
    } catch (e) {
        console.warn('[PDF] Logo non intégré (chargement échoué) :', e);
        return html;
    }
}

/**
 * Retire du HTML sérialisé les éléments qui ne doivent jamais
 * apparaître dans le PDF (boutons, zone de signature interactive...).
 * Le CSS d'impression les masque déjà normalement ; ceci est un
 * filet de sécurité qui les supprime physiquement, au cas où — le
 * même principe que l'ancien code appliquait sur l'iframe avant
 * capture. On en profite aussi pour retirer les <script>, désormais
 * inutiles côté serveur (JS désactivé) et inutiles à envoyer.
 */
function _retirerElementsNonImprimables(html) {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    doc.querySelectorAll(
        '.buttons, .no-print, .signature-pad-wrap, .signature-controls, button, script'
    ).forEach(function(el) { el.remove(); });
    return '<!DOCTYPE html>' + doc.documentElement.outerHTML;
}

function _base64VersUint8Array(base64) {
    const binaire = atob(base64);
    const octets = new Uint8Array(binaire.length);
    for (let i = 0; i < binaire.length; i++) octets[i] = binaire.charCodeAt(i);
    return octets;
}

/**
 * Génère le PDF du formulaire actuellement rempli.
 * @returns {Promise<Uint8Array>} le PDF, prêt à passer à envoyerMailFormulaire()
 *          et à enregistrerPdfDrive() — signature inchangée par rapport à
 *          l'ancienne version, aucun appelant n'a besoin d'être modifié.
 */
async function genererPdfFormulaire() {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) throw new Error("Session expirée — reconnectez-vous puis réessayez.");

    let htmlComplet = buildHtmlWithData();
    htmlComplet = htmlComplet.replace('<head>', '<head><style>' + _reglesCompletesEnClair() + '</style>');
    htmlComplet = await _logoEnBase64DansHtml(htmlComplet);
    htmlComplet = _retirerElementsNonImprimables(htmlComplet);
    return await genererPdfDepuisHtml(htmlComplet);
}

/**
 * Envoie un HTML complet (déjà autonome : CSS en ligne, images en base64)
 * à la fonction Edge et renvoie le PDF. Utilisé directement par les pages
 * qui ne sont pas un formulaire imprimable (ex. arrivee_animal.html).
 */
async function genererPdfDepuisHtml(htmlComplet) {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) throw new Error("Session expirée — reconnectez-vous puis réessayez.");

    const url = SUPABASE_URL + '/functions/v1/generer-pdf-formulaire';
    const resp = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + session.access_token,
            'apikey': SUPABASE_ANON_KEY,
        },
        body: JSON.stringify({ html: htmlComplet }),
    });

    let result = {};
    try { result = await resp.json(); } catch (e) { /* réponse non-JSON, traité ci-dessous */ }

    if (!resp.ok || !result.ok) {
        throw new Error(result.error || ('Échec de la génération du PDF (HTTP ' + resp.status + ')'));
    }

    const pdfBytes = _base64VersUint8Array(result.pdfBase64);

    // Garde-fou : un PDF anormalement petit trahit presque toujours un
    // rendu raté (page blanche) plutôt qu'un vrai formulaire — mieux
    // vaut échouer bruyamment que d'envoyer ça par mail comme si de
    // rien n'était.
    if (pdfBytes.length < 2000) {
        throw new Error('Le PDF généré semble anormalement petit — envoi annulé par précaution.');
    }

    return pdfBytes;
}
