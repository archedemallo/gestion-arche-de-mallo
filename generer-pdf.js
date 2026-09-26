// ============================================================
// GÉNÉRATION DU PDF CÔTÉ NAVIGATEUR — nouveau système (remplace la
// génération faite jusqu'ici par l'Apps Script côté serveur)
// ============================================================
// Réutilise EXACTEMENT le rendu déjà en place et déjà utilisé au
// quotidien : buildHtmlWithData() (voir formulaires-arche-mallo.js),
// c'est-à-dire le même contenu que celui envoyé à l'Apps Script, et
// les mêmes règles CSS que celles utilisées par le bouton "Imprimer".
//
// Contrairement au chantier précédent (pdf-lib + gabarit PDF figé aux
// coordonnées fixes), on ne redessine aucune mise en page : on capture
// tel quel ce qui s'affiche déjà à l'écran/à l'impression. Aucun
// nouveau gabarit à valider, fonctionne à l'identique pour les 12
// formulaires sans travail supplémentaire par formulaire.
//
// Nécessite html2pdf.js, chargé à la demande (inutile d'ajouter un
// <script> dans chaque page).
// ============================================================

let _html2pdfChargement = null;
function _chargerHtml2Pdf() {
    if (window.html2pdf) return Promise.resolve();
    if (_html2pdfChargement) return _html2pdfChargement;
    _html2pdfChargement = new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = 'https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js';
        s.onload = resolve;
        s.onerror = () => reject(new Error('Impossible de charger la bibliothèque de génération PDF (vérifiez la connexion internet).'));
        document.head.appendChild(s);
    });
    return _html2pdfChargement;
}

/**
 * Récupère TOUT le CSS de la page courante (règles normales + celles de
 * "@media print", ces dernières sans leur condition) et le renvoie comme
 * un unique bloc de règles normales, les règles d'impression en dernier
 * (donc prioritaires à spécificité égale, comme le ferait le mode
 * impression du navigateur).
 *
 * Le rendu hors-écran (iframe isolé, voir plus bas) ne recharge pas de
 * façon fiable les feuilles de style externes (ex: formulaires-arche-
 * mallo.css) : la résolution d'URL relative dans un iframe "srcdoc" est
 * inconstante selon les navigateurs. Sans tout ce CSS réinjecté en
 * clair, la mise en forme de base disparaît (largeurs de champs,
 * position des boutons flottants...) et le PDF ne ressemble plus du
 * tout à ce qui s'affiche à l'écran — d'où l'inlining complet plutôt
 * que de compter sur le chargement de la feuille externe.
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
    return base + '\n' + impression;
}

/**
 * Génère le PDF du formulaire actuellement rempli.
 * @returns {Promise<Uint8Array>} le PDF, prêt à passer à envoyerMailFormulaire().
 */
async function genererPdfFormulaire() {
    await _chargerHtml2Pdf();

    let htmlComplet = buildHtmlWithData();
    htmlComplet = htmlComplet.replace('<head>', '<head><style>' + _reglesCompletesEnClair() + '</style>');

    // Rendu hors-écran, dans un iframe isolé — n'affecte jamais la page en cours.
    const iframe = document.createElement('iframe');
    iframe.style.cssText = 'position:fixed;top:-10000px;left:-10000px;width:900px;height:0;border:0;';
    document.body.appendChild(iframe);

    try {
        await new Promise((resolve) => { iframe.onload = resolve; iframe.srcdoc = htmlComplet; });
        // Laisse le temps aux images (signature, photo de l'animal) de se poser.
        await new Promise((r) => setTimeout(r, 300));

        // Filet de sécurité : même si le CSS d'impression échouait à masquer
        // les boutons flottants et autres éléments "no-print", on les
        // retire physiquement du DOM avant la capture — ils ne peuvent
        // alors plus apparaître dans le PDF, quelle que soit la raison
        // pour laquelle le display:none n'aurait pas été appliqué.
        const doc = iframe.contentDocument;
        doc.querySelectorAll('.buttons, .no-print, .signature-pad-wrap, .signature-controls, button').forEach(function(el) {
            el.remove();
        });

        const worker = window.html2pdf().set({
            margin: 8,
            filename: 'formulaire.pdf',
            html2canvas: { scale: 2, useCORS: true, windowWidth: 900, backgroundColor: '#ffffff' },
            jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' },
            pagebreak: { mode: ['css', 'legacy'] }
        }).from(doc.body);

        const arrayBuffer = await worker.outputPdf('arraybuffer');
        return new Uint8Array(arrayBuffer);
    } finally {
        document.body.removeChild(iframe);
    }
}
