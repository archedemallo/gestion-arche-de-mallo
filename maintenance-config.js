const MAINTENANCE = {
  active: true, // true = redirige tout le monde vers maintenance.html
  jour: "dimanche 23 août", // Changer la date ICI
  debut: "14h30", // Changer l'heure ICI
  fin: "15h00" // Changer l'heure ICI
};

// --- Pop-up MISE A JOUR ---
// S'affiche automatiquement pendant `dureeJours` jours à partir de
// `dateDebut`, puis disparaît toute seule (rien à désactiver après coup).
// Pour une nouvelle annonce : changer dateDebut (+ texte).
const MAJ = {
  active: false, // true = pop-up active / false = désactivée
  dateDebut: "2026-10-05", // date de mise en ligne, format AAAA-MM-JJ
  dureeJours: 7, // nombre de jours d'affichage à partir de dateDebut
  titre: "Mise à jour",
  // Texte libre. Utiliser <br> pour un retour à la ligne.
  texte: "Une mise à jour a été effectuée.<br>Possibilité d'enregistrer un don directement depuis Un Contrat de Cession à Charge.<br>Le formulaire se complète automatiquement."
};
