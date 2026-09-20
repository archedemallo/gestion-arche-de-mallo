// ============================================================
// SUGGESTION DE NOM ALÉATOIRE POUR UN NOUVEAU CHAT
// ============================================================
// Fichier additif, à charger uniquement là où un bouton
// "🎲 Nom aléatoire" est utilisé (statuts_animaux.html — Déclarer
// une arrivée). Ne verrouille jamais le champ concerné : ce n'est
// qu'une proposition, librement modifiable ou remplaçable.
//
// Nécessite : un client Supabase déjà créé (variable `supabaseClient`)
// et la fonction RPC noms_animaux_presents() (voir
// 033_nom_chat_aleatoire.sql).
// ============================================================

const BANQUE_NOMS_CHATS = [
  'Minou','Félix','Simba','Nala','Tigrou','Choupette','Câline','Réglisse',
  'Praline','Biscotte','Cannelle','Noisette','Caramel','Chocolat','Vanille',
  'Muscade','Pimprenelle','Griotte','Cookie','Pépette','Pompon','Filou',
  'Malice','Câlin','Ombre','Nuage','Perle','Opale','Jade','Saphir',
  'Émeraude','Ambre','Étoile','Comète','Lune','Soleil','Éclipse','Nova',
  'Orage','Brume','Rosée','Iris','Pétale','Fleur','Trèfle','Mimosa',
  'Câlinou','Doudou','Pilou','Moka','Truffe','Gribouille','Pixel','Salem',
  'Loki','Merlin','Gandalf','Yoda','Pixie','Gizmo','Ninja','Bandit',
  'Zorro','Sultan','Rajah','Pacha','Sheba','Cléo','Isis','Néfertiti',
  'Cheyenne','Kiara','Sasha','Chamallow','Guimauve','Bonbon','Sucrette',
  'Câpre','Olive','Basilic','Romarin','Safran','Curry','Gingembre',
  'Cardamone','Poivron','Piment','Réséda','Coquelicot','Bleuet',
  'Jonquille','Tulipe','Violette','Pâquerette','Frimousse','Mistigri',
  'Grisou','Grispoil','Fumée','Cendre','Ébène','Onyx','Charbon','Suie',
  'Corbeau','Plume','Duvet','Cotonnet','Coton','Frimas','Flocon','Givre',
  'Cristal','Diamant','Rubis','Topaze','Grenat','Corail','Mistral',
  'Zéphyr','Câpucine','Câlinette','Guimauve','Chipie','Fripouille','Farfelu',
  'Titou','Ficelle','Bobine','Câramel','Câjou','Nougat','Speculoos',
  'Chantilly','Éclair','Meringue','Sablé','Financier','Pudding'
];

let _cacheNomsAnimauxPresents = null;

/** Récupère (avec cache) les noms actuellement portés par des chats présents. */
async function _nomsAnimauxPresentsActuels() {
  if (_cacheNomsAnimauxPresents) return _cacheNomsAnimauxPresents;
  try {
    const { data, error } = await supabaseClient.rpc('noms_animaux_presents');
    if (error) throw error;
    _cacheNomsAnimauxPresents = new Set((data || []).map(r => String(r.nom || '').trim().toUpperCase()).filter(Boolean));
  } catch (e) {
    console.error('[Nom aléatoire] Erreur récupération des noms déjà utilisés :', e.message);
    _cacheNomsAnimauxPresents = new Set(); // en cas d'erreur, on ne bloque pas la suggestion
  }
  return _cacheNomsAnimauxPresents;
}

/**
 * Invalide le cache des noms déjà pris — à appeler juste après avoir
 * enregistré une nouvelle arrivée, pour que le nom qui vient d'être
 * utilisé ne soit plus jamais reproposé pendant la session en cours.
 */
function invaliderCacheNomsAnimauxPresents() { _cacheNomsAnimauxPresents = null; }

/**
 * Tire un nom au hasard dans la banque, en excluant les noms déjà
 * portés par un chat actuellement présent à l'association. Un nom
 * ayant déjà existé par le passé (chat parti) reste proposable.
 * @param {string} [dernierNomPropose] évite si possible de reproposer
 *                                      deux fois de suite le même nom.
 * @returns {Promise<string|null>} le nom proposé, ou null si la banque
 *                                  est entièrement épuisée (cas très
 *                                  improbable).
 */
async function proposerNomAleatoireChat(dernierNomPropose) {
  const pris = await _nomsAnimauxPresentsActuels();
  let candidats = BANQUE_NOMS_CHATS.filter(n => !pris.has(n.toUpperCase()));
  if (dernierNomPropose && candidats.length > 1) {
    candidats = candidats.filter(n => n.toUpperCase() !== String(dernierNomPropose).trim().toUpperCase());
  }
  if (!candidats.length) return null;
  return candidats[Math.floor(Math.random() * candidats.length)];
}
