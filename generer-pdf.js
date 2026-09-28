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
 * true si le canevas est (quasi) entièrement blanc : on échantillonne une
 * version réduite et on compte les pixels non blancs. Un vrai formulaire
 * (texte, cadres, logo) en contient nettement plus de 1 %.
 */
function _canvasQuasiVide(canvas) {
    const petit = document.createElement('canvas');
    petit.width  = 120;
    petit.height = Math.max(1, Math.round(120 * canvas.height / canvas.width));
    const ctx = petit.getContext('2d');
    ctx.drawImage(canvas, 0, 0, petit.width, petit.height);
    const px = ctx.getImageData(0, 0, petit.width, petit.height).data;
    let nonBlancs = 0;
    for (let i = 0; i < px.length; i += 4) {
        if (px[i] < 235 || px[i + 1] < 235 || px[i + 2] < 235) nonBlancs++;
    }
    return nonBlancs / (px.length / 4) < 0.01;
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
    // ← MODIFIÉ : l'iframe était placé à left/top:-10000px avec height:0.
    // html2canvas calcule la zone à dessiner à partir de la fenêtre de
    // l'iframe : hors écran et de hauteur nulle, il ne rendait qu'une
    // mince bande du document (le PDF ne contenait que des fragments de
    // texte sur la gauche de la page). L'iframe reste donc DANS la zone
    // visible (coin 0,0), derrière la page (z-index négatif, invisible,
    // non cliquable) et sa hauteur est ajustée au contenu avant capture.
    iframe.style.cssText = 'position:fixed;top:0;left:0;width:900px;height:1200px;border:0;' +
                           'z-index:-1;visibility:hidden;pointer-events:none;';
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

        const MARGE_MM          = 8;
        const PAGE_LARGEUR_MM   = 210;   // A4 portrait
        const PAGE_HAUTEUR_MM   = 297;
        const LARGEUR_UTILE_MM  = PAGE_LARGEUR_MM - 2 * MARGE_MM;
        const HAUTEUR_UTILE_MM  = PAGE_HAUTEUR_MM - 2 * MARGE_MM;

        // html2pdf.js bundle les deux librairies dont il dépend ; selon les
        // versions du CDN elles sont exposées soit sous window.jspdf.jsPDF
        // (UMD récent), soit directement sous window.jsPDF (plus ancien).
        const jsPDFCtor = (window.jspdf && window.jspdf.jsPDF) || window.jsPDF;

        // ← AJOUTÉ : pagination manuelle, à la place du découpeur interne
        // de html2pdf.js (pagebreak mode 'css'/'legacy'). Ce découpeur est
        // connu pour être instable quand le contenu dépasse une page de
        // peu (petite tranche de reliquat sur la dernière page) : selon
        // les essais, il duplique la même image sur 2 pages, ou plante
        // (RangeError: Maximum call stack size exceeded) — observé en
        // reproduisant le pipeline en local avec la vraie version 0.10.1.
        // Ici, on capture UNE SEULE FOIS le rendu complet avec html2canvas,
        // puis on découpe NOUS-MÊMES ce canevas en tranches de la hauteur
        // exacte d'une page A4, collées une par une dans le PDF avec
        // jsPDF — un mécanisme simple et entièrement déterministe.
        if (window.html2canvas && jsPDFCtor) {
            // Hauteur réelle du document rendu : l'iframe et la "fenêtre"
            // de html2canvas doivent l'englober entièrement.
            const hauteurDoc = Math.max(doc.documentElement.scrollHeight, doc.body.scrollHeight);
            iframe.style.height = hauteurDoc + 'px';
            await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));

            const canvas = await window.html2canvas(doc.body, {
                scale: 2, useCORS: true, backgroundColor: '#ffffff',
                windowWidth: 900, windowHeight: hauteurDoc,
                x: 0, y: 0, scrollX: 0, scrollY: 0
            });

            // Garde-fou : un rendu quasi vide (capture ratée) ne doit
            // jamais partir par mail comme s'il s'agissait du vrai document.
            if (_canvasQuasiVide(canvas)) {
                throw new Error('La capture du formulaire est vide — PDF non généré.');
            }

            const largeurCanvasPx = canvas.width;
            const hauteurCanvasPx = canvas.height;
            const mmParPx         = LARGEUR_UTILE_MM / largeurCanvasPx;
            const hauteurPageEnPx = Math.floor(HAUTEUR_UTILE_MM / mmParPx);

            const pdf = new jsPDFCtor({ unit: 'mm', format: 'a4', orientation: 'portrait' });

            let positionY    = 0;
            let premierePage = true;
            while (positionY < hauteurCanvasPx) {
                const hauteurTrancheEnPx = Math.min(hauteurPageEnPx, hauteurCanvasPx - positionY);

                const trancheCanvas = document.createElement('canvas');
                trancheCanvas.width  = largeurCanvasPx;
                trancheCanvas.height = hauteurTrancheEnPx;
                trancheCanvas.getContext('2d').drawImage(
                    canvas,
                    0, positionY, largeurCanvasPx, hauteurTrancheEnPx,
                    0, 0, largeurCanvasPx, hauteurTrancheEnPx
                );

                if (!premierePage) pdf.addPage();
                pdf.addImage(
                    trancheCanvas.toDataURL('image/jpeg', 0.95), 'JPEG',
                    MARGE_MM, MARGE_MM,
                    LARGEUR_UTILE_MM, hauteurTrancheEnPx * mmParPx
                );

                positionY   += hauteurTrancheEnPx;
                premierePage = false;
            }

            return new Uint8Array(pdf.output('arraybuffer'));
        }

        // ← Filet de sécurité : si ce build de html2pdf.js n'expose pas
        // html2canvas/jsPDF globalement (ça peut changer selon les
        // versions livrées par le CDN), on retombe sur l'ancien
        // comportement plutôt que de tout casser.
        const worker = window.html2pdf().set({
            margin: MARGE_MM,
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
