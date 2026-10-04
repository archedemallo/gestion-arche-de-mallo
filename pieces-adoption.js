// ============================================================
// PIÈCES JUSTIFICATIVES D'ADOPTION — composant partagé par
// adoption.html (pièces remises le jour de l'adoption) et
// completer_dossier_adoption.html (pièces transmises plus tard).
//
// Chaque pièce est déposée comme un PDF dans le dossier Drive de
// l'adoption (même circuit que le contrat de cession : génération PDF
// -> Apps Script -> soumission_fichiers), puis marquée « reçue » dans
// adoption_pieces. Le PDF apparaît donc dans la section Adoption de la
// fiche de la personne.
//
// Nécessite : supabaseClient, generer-pdf.js (genererPdfDepuisHtml),
// stocker-pdf-drive.js (enregistrerPdfDrive), formulaires-arche-mallo.js
// (redimensionnerImage). Migration 062 exécutée.
// ============================================================

var PIECES_ADOPTION = [
    { type: 'cni_recto',    label: "Pièce d'identité — recto" },
    { type: 'cni_verso',    label: "Pièce d'identité — verso" },
    { type: 'domicile',     label: 'Justificatif de domicile' },
    { type: 'cbs',          label: 'Certificat de bonne santé' },
    { type: 'carnet_sante', label: 'Carnet de santé (pages vaccins)' }
];

function libellePieceAdoption(type) {
    var p = PIECES_ADOPTION.filter(function(x) { return x.type === type; })[0];
    return p ? p.label : type;
}

function _escPiece(x) {
    return String(x == null ? '' : x).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
}

// Marque une pièce comme reçue (ou non) pour une adoption.
async function marquerPieceAdoption(adoptionId, typePiece, recue, mode) {
    var ligne = {
        adoption_id: adoptionId,
        type_piece: typePiece,
        recue: !!recue,
        mode_reception: recue ? (mode || 'fichier') : null,
        date_reception: recue ? new Date().toISOString().split('T')[0] : null
    };
    var res = await supabaseClient.from('adoption_pieces')
        .upsert(ligne, { onConflict: 'adoption_id,type_piece' });
    if (res.error) throw new Error('Suivi de la pièce non enregistré : ' + res.error.message);
}

// Crée les 5 lignes d'une nouvelle adoption (recue = pièce fournie ce jour).
// fourniesParType : { cni_recto: true, domicile: false, ... }
async function initialiserPiecesAdoption(adoptionId, fourniesParType) {
    var today = new Date().toISOString().split('T')[0];
    var lignes = PIECES_ADOPTION.map(function(p) {
        var ok = !!(fourniesParType && fourniesParType[p.type]);
        return {
            adoption_id: adoptionId,
            type_piece: p.type,
            recue: ok,
            mode_reception: ok ? 'fichier' : null,
            date_reception: ok ? today : null
        };
    });
    var res = await supabaseClient.from('adoption_pieces')
        .upsert(lignes, { onConflict: 'adoption_id,type_piece' });
    if (res.error) throw new Error('Liste des pièces non enregistrée : ' + res.error.message);
}

// Dépose UNE pièce (une ou plusieurs images, ou un PDF) sur Drive.
// ctx : { adoptionId, onglet, prenom, nom, animal, dateDossier, titreDossier }
// files : tableau de File (images ou un PDF)
async function deposerPieceAdoption(ctx, typePiece, files) {
    files = Array.prototype.slice.call(files || []).filter(Boolean);
    if (!files.length) throw new Error('Aucun fichier sélectionné.');
    var label = libellePieceAdoption(typePiece);

    var pdfBytes;
    var unPdf = files.length === 1 && (files[0].type === 'application/pdf' || /\.pdf$/i.test(files[0].name));
    if (unPdf) {
        pdfBytes = new Uint8Array(await files[0].arrayBuffer());
    } else {
        var blocs = [];
        for (var i = 0; i < files.length; i++) {
            var b64 = await new Promise(function(resolve) { redimensionnerImage(files[i], resolve, 1400); });
            if (!b64) throw new Error('Image illisible : ' + files[i].name + ' (format non pris en charge ?)');
            blocs.push('<div style="page-break-inside:avoid;margin:0 0 22px;">' +
                '<img src="data:image/jpeg;base64,' + b64 + '" style="max-width:100%;max-height:23cm;border:1px solid #ccc;"></div>');
        }
        var html = '<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><style>' +
            'body{font-family:Arial,sans-serif;color:#3d2b1f;margin:28px;font-size:13px;} h1{font-size:17px;color:#c96b2a;margin:0 0 4px;}' +
            '.sous{color:#8a7968;margin-bottom:16px;}</style></head><body>' +
            '<h1>' + _escPiece(label) + '</h1>' +
            '<div class="sous">' + _escPiece(ctx.titreDossier || '') + '</div>' +
            blocs.join('') + '</body></html>';
        pdfBytes = await genererPdfDepuisHtml(html);
    }

    var filename = ['Piece', typePiece, ctx.nom || 'Inconnu', ctx.animal || 'Animal', ctx.dateDossier || '']
        .filter(Boolean).join('_').replace(/\s+/g, '_');
    await enregistrerPdfDrive({
        onglet: ctx.onglet || 'adoption',
        prenom: ctx.prenom,
        nom: ctx.nom,
        animal: ctx.animal,
        dateDossier: ctx.dateDossier || null,
        filename: filename,
        pdfBytes: pdfBytes,
        tableSource: 'adoptions',
        enregistrementId: ctx.adoptionId,
        typeFichier: 'Pièce : ' + label
    });
    await marquerPieceAdoption(ctx.adoptionId, typePiece, true, 'fichier');
}
