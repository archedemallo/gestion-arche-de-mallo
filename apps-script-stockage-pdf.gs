// ============================================================
// À AJOUTER AU PROJET APPS SCRIPT EXISTANT (celui dont l'URL est
// APPS_SCRIPT_URL dans config.js — le même qui reçoit déjà les
// photos, action:'photo').
//
// 1) Coller ce fichier tel quel dans le projet (Fichier > Nouveau >
//    Fichier script), par exemple sous le nom "StockagePdf.gs".
// 2) Remplacer DOSSIER_RACINE_ID ci-dessous par l'ID du dossier Drive
//    partagé de l'équipe où les PDF doivent être rangés (l'ID est la
//    partie après /folders/ dans l'URL du dossier Drive).
// 3) Dans la fonction doPost(e) existante, ajouter une branche pour
//    la nouvelle action — repérer le bloc qui gère déjà
//    `if (data.action === 'photo') { ... }` et ajouter juste à côté :
//
//      } else if (data.action === 'pdf') {
//        return enregistrerPdfDrive(data);
//
// 4) Redéployer le Web App (Déployer > Gérer les déploiements >
//    modifier > Nouvelle version) — sans ça, le code déjà en ligne
//    ne changera pas, même après avoir sauvegardé le script.
// ============================================================

var DOSSIER_RACINE_ID = 'COLLER_ICI_ID_DU_DOSSIER_DRIVE_EQUIPE';

function enregistrerPdfDrive(data) {
  try {
    var racine = DriveApp.getFolderById(DOSSIER_RACINE_ID);
    var dossierOnglet = obtenirOuCreerSousDossier(racine, data.onglet || 'Divers');
    var dossierDate = obtenirOuCreerSousDossier(dossierOnglet, data.dateDossier || Utilities.formatDate(new Date(), 'Europe/Paris', 'yyyy-MM-dd'));

    var pdfBlob = Utilities.newBlob(
      Utilities.base64Decode(data.pdfBase64),
      'application/pdf',
      (data.filename || 'document') + '.pdf'
    );
    var fichier = dossierDate.createFile(pdfBlob);
    fichier.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);

    return ContentService.createTextOutput(JSON.stringify({ ok: true, url: fichier.getUrl() }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ ok: false, error: String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function obtenirOuCreerSousDossier(parent, nom) {
  var existants = parent.getFoldersByName(nom);
  if (existants.hasNext()) return existants.next();
  return parent.createFolder(nom);
}
