/* ============================================================
   ARCHE DE MALLO — Comptabilité
   compta-commun.js — Fonctions partagées par toutes les pages Compta

   1) PÉRIODES
      La liste des périodes vit dans config_compta (cle='periodes').
      La PÉRIODE PAR DÉFAUT vit dans parametres (cle='periode_courante')
      et se règle uniquement depuis Configuration. Toutes les pages
      lisent cette valeur au chargement : plus de "dernière période de
      la liste" codée en dur dans chaque fichier.

   2) PUCES COLORÉES (chips)
      Une couleur stable par valeur de "Type de mouvement" et une par
      valeur de "Description". Les types connus ont une couleur fixe ;
      toute nouvelle valeur ajoutée dans Configuration reçoit
      automatiquement une couleur stable (hash du libellé), donc
      identique d'une page à l'autre et d'une session à l'autre.
   ============================================================ */

// ============================================================
// 1. PÉRIODES
// ============================================================

function periodesParDefaut() {
  const y = new Date().getFullYear(), m = new Date().getMonth() + 1;
  const start = m >= 11 ? y : y - 1;
  const out = [];
  for (let i = 2024; i <= start; i++) out.push(`${i} - ${i + 1}`);
  return out;
}

/**
 * Lit la liste des périodes + la période par défaut définie en Configuration.
 * @returns {Promise<{periodes: string[], courante: string}>}
 */
function periodeNormaliser(p) { return String(p || '').trim().replace(/\s*[-–]\s*/, ' - '); }

async function chargerContextePeriodes(client) {
  let periodes = null;
  try {
    const { data } = await client.from('config_compta').select('valeur').eq('cle', 'periodes').maybeSingle();
    if (data && Array.isArray(data.valeur) && data.valeur.length) periodes = data.valeur;
  } catch (e) { console.warn('[compta] lecture config_compta.periodes impossible :', e); }
  if (!periodes || !periodes.length) periodes = periodesParDefaut();

  let courante = null;
  try {
    const { data, error } = await client.from('parametres').select('valeur').eq('cle', 'periode_courante').maybeSingle();
    if (error) {
      // Erreur explicite (le plus souvent une RLS qui bloque la lecture,
      // par ex. si 028_rls_config_compta_manquantes.sql n'a pas été
      // exécuté) : on le signale en console plutôt que de retomber
      // silencieusement sur la dernière période, pour rester diagnosticable.
      console.warn('[compta] lecture parametres.periode_courante refusée (RLS ?) :', error);
    } else if (data && data.valeur) {
      const norm = periodeNormaliser(data.valeur);
      const trouvee = periodes.find(p => periodeNormaliser(p) === norm);
      if (trouvee) courante = trouvee;
      else console.warn('[compta] periode_courante="' + data.valeur + '" ne correspond à aucune période de la liste :', periodes);
    } else {
      console.warn('[compta] aucune valeur enregistrée pour parametres.periode_courante — définissez-la dans Configuration.');
    }
  } catch (e) { console.warn('[compta] lecture parametres.periode_courante impossible :', e); }
  if (!courante) courante = periodes[periodes.length - 1];

  return { periodes, courante };
}

/** Remplit un ou plusieurs <select> avec les périodes et sélectionne la période par défaut. */
function remplirSelectsPeriodes(ids, periodes, courante) {
  (Array.isArray(ids) ? ids : [ids]).forEach(id => {
    const s = document.getElementById(id);
    if (!s) return;
    s.innerHTML = '';
    periodes.forEach(p => {
      const o = document.createElement('option');
      o.value = p; o.textContent = p;
      if (p === courante) o.selected = true;
      s.appendChild(o);
    });
    s.value = courante;
  });
}

/** Raccourci : charge le contexte et remplit les selects. Renvoie {periodes, courante}. */
async function initPeriodes(client, ids) {
  const ctx = await chargerContextePeriodes(client);
  remplirSelectsPeriodes(ids, ctx.periodes, ctx.courante);
  return ctx;
}

// ============================================================
// 2. PUCES COLORÉES
// ============================================================

// Palette "Type de mouvement" — teintes soutenues
const CHIP_PALETTE_TYPE = [
  { bg: '#E6F1FB', fg: '#185FA5', bd: '#B4D3EE' }, //  0 bleu
  { bg: '#EAF3DE', fg: '#3B6D11', bd: '#C4DEA4' }, //  1 vert
  { bg: '#FAECE7', fg: '#993C1D', bd: '#EFC6B6' }, //  2 brique
  { bg: '#FAEEDA', fg: '#854F0B', bd: '#EDD2A2' }, //  3 ambre
  { bg: '#EEEDFE', fg: '#3C3489', bd: '#CDCAF3' }, //  4 violet
  { bg: '#FDEDE2', fg: '#C96B2A', bd: '#F2C9A8' }, //  5 orange
  { bg: '#E1F3F0', fg: '#0E6E63', bd: '#B2E0D9' }, //  6 turquoise
  { bg: '#FBE9F1', fg: '#98306A', bd: '#F0C2D8' }, //  7 rose
  { bg: '#EDEFE3', fg: '#5A6B23', bd: '#D0D7B3' }, //  8 olive
  { bg: '#E9EDF3', fg: '#3F5670', bd: '#C4CEDC' }, //  9 ardoise
  { bg: '#F4EAF8', fg: '#6B3C8C', bd: '#DBC4E9' }, // 10 mauve
  { bg: '#FDF1DB', fg: '#8A6A12', bd: '#EDD9A4' }, // 11 moutarde
  { bg: '#E4F0E7', fg: '#20613F', bd: '#BADAC6' }, // 12 sapin
  { bg: '#F7E9E3', fg: '#8A4B3A', bd: '#E6C6BA' }, // 13 terre cuite
];

// Palette "Description" — mêmes familles, teintes plus douces, pour
// distinguer d'un coup d'œil la colonne Description de la colonne Type.
const CHIP_PALETTE_DESC = [
  { bg: '#F2F7FC', fg: '#2E6FA8', bd: '#D5E5F3' },
  { bg: '#F3F8EC', fg: '#4C7A26', bd: '#DCEBC9' },
  { bg: '#FCF3F0', fg: '#A75434', bd: '#F1DACF' },
  { bg: '#FDF6EC', fg: '#8F6423', bd: '#F0E2C6' },
  { bg: '#F5F5FE', fg: '#4F4796', bd: '#E0DEF8' },
  { bg: '#FEF5EE', fg: '#C97B43', bd: '#F5DCC7' },
  { bg: '#EFF8F6', fg: '#2A7B71', bd: '#CDE8E3' },
  { bg: '#FDF3F7', fg: '#A24A79', bd: '#F3D8E6' },
  { bg: '#F5F7EE', fg: '#6B7936', bd: '#E0E5CB' },
  { bg: '#F3F5F8', fg: '#526880', bd: '#DCE3EB' },
  { bg: '#F9F3FB', fg: '#7B5099', bd: '#E9DCF1' },
  { bg: '#FEF8EA', fg: '#947726', bd: '#F2E6C3' },
  { bg: '#EFF6F1', fg: '#31714F', bd: '#D3E6DA' },
  { bg: '#FBF3EF', fg: '#985C4B', bd: '#EFDBD2' },
];

// Couleurs fixes pour les types connus (indices dans les palettes ci-dessus).
// Clé normalisée : minuscules, sans accent.
const CHIP_TYPES_FIXES = {
  'adoption': 0,
  'dons': 1, 'don': 1,
  'veterinaire': 2,
  'evenement': 3,
  'adhesion': 4,
  'equipement': 5, 'plusieurs factures amazon': 5,
  'subvention': 6,
  'vente diverse': 7,
  'formation': 8,
  'frais de compte': 9, 'commission': 9,
  'assurance': 10, 'internet': 10,
  'cheque': 11, 'remise cheque': 11,
  'depot en banque': 12, 'versement caisse': 12,
  'transfert entre caisse': 13,
  '???': 9,
};

function chipNormaliser(s) {
  return String(s || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().trim();
}

function chipHash(s) {
  let h = 0;
  const t = chipNormaliser(s);
  for (let i = 0; i < t.length; i++) h = (h * 31 + t.charCodeAt(i)) >>> 0;
  return h;
}

/** Couleur d'un type de mouvement (fixe si connu, sinon stable par hash). */
function couleurType(valeur) {
  const k = chipNormaliser(valeur);
  const i = Object.prototype.hasOwnProperty.call(CHIP_TYPES_FIXES, k)
    ? CHIP_TYPES_FIXES[k]
    : chipHash(k) % CHIP_PALETTE_TYPE.length;
  return CHIP_PALETTE_TYPE[i];
}

/** Couleur d'une description (stable par hash). */
function couleurDescription(valeur) {
  return CHIP_PALETTE_DESC[chipHash(valeur) % CHIP_PALETTE_DESC.length];
}

function chipEscape(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/'/g, '&#39;').replace(/"/g, '&quot;');
}

function chipHTML(valeur, couleur, vide) {
  const v = (valeur == null ? '' : String(valeur)).trim();
  if (!v) return vide === undefined ? '' : vide;
  return '<span class="chip" style="display:inline-block;font-size:9px;font-weight:500;padding:2px 7px;'
       + 'border-radius:20px;white-space:nowrap;background:' + couleur.bg + ';color:' + couleur.fg
       + ';border:0.5px solid ' + couleur.bd + ';">' + chipEscape(v) + '</span>';
}

/** Puce colorée "Type de mouvement". */
function puceType(valeur, vide) { return chipHTML(valeur, couleurType(valeur), vide); }

/** Puce colorée "Description". */
function puceDescription(valeur, vide) { return chipHTML(valeur, couleurDescription(valeur), vide); }

// ============================================================
// 3. COLONNES REDIMENSIONNABLES
// ============================================================
// S'applique automatiquement à TOUS les tableaux de toutes les pages qui
// chargent ce fichier — même ceux reconstruits dynamiquement à chaque
// rendu (innerHTML). Les largeurs choisies sont mémorisées par page +
// position de colonne (localStorage) et réappliquées aux rendus suivants.
(function () {
  const LS_PREFIX = 'colw::';

  function widthKey(container, index) {
    const cid = (container && (container.id || container.className)) || 'tbl';
    return LS_PREFIX + location.pathname + '::' + cid + '::' + index;
  }

  function applyStoredWidths(table, container) {
    const ths = table.querySelectorAll(':scope > thead > tr > th');
    let any = false;
    ths.forEach((th, i) => {
      let saved;
      try { saved = localStorage.getItem(widthKey(container, i)); } catch (e) {}
      if (saved) { th.style.width = saved + 'px'; any = true; }
    });
    if (any) table.style.tableLayout = 'fixed';
  }

  function makeResizable(table, container) {
    if (!table || table.dataset.colResizeInit) return;
    table.dataset.colResizeInit = '1';
    // Permet le défilement horizontal si les colonnes élargies dépassent le conteneur.
    if (container && container.style && !container.style.overflowX) {
      const cs = getComputedStyle(container);
      if (cs.overflowX === 'visible') container.style.overflowX = 'auto';
    }
    applyStoredWidths(table, container);
    const ths = table.querySelectorAll(':scope > thead > tr > th');
    ths.forEach((th, i) => {
      if (th.querySelector('.col-resizer')) return;
      const handle = document.createElement('div');
      handle.className = 'col-resizer';
      th.appendChild(handle);
      handle.addEventListener('mousedown', function (e) {
        e.preventDefault(); e.stopPropagation();
        if (table.style.tableLayout !== 'fixed') {
          ths.forEach(t => { t.style.width = t.offsetWidth + 'px'; });
          table.style.tableLayout = 'fixed';
        }
        const startX = e.pageX, startW = th.offsetWidth;
        handle.classList.add('resizing');
        function onMove(ev) {
          th.style.width = Math.max(36, startW + (ev.pageX - startX)) + 'px';
        }
        function onUp() {
          handle.classList.remove('resizing');
          document.removeEventListener('mousemove', onMove);
          document.removeEventListener('mouseup', onUp);
          try { localStorage.setItem(widthKey(container, i), Math.round(th.offsetWidth)); } catch (e) {}
        }
        document.addEventListener('mousemove', onMove);
        document.addEventListener('mouseup', onUp);
      });
    });
  }

  function scan(root) {
    if (!root || !root.querySelectorAll) return;
    root.querySelectorAll('table').forEach(table => {
      const container = table.closest('[id]') || table.parentElement;
      makeResizable(table, container);
    });
  }

  function boot() {
    scan(document);
    const mo = new MutationObserver(muts => {
      muts.forEach(m => m.addedNodes.forEach(node => {
        if (node.nodeType !== 1) return;
        if (node.tagName === 'TABLE') makeResizable(node, node.closest('[id]') || node.parentElement);
        else scan(node);
      }));
    });
    mo.observe(document.body, { childList: true, subtree: true });
  }
  if (document.body) boot(); else document.addEventListener('DOMContentLoaded', boot);
})();
