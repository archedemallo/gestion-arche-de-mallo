// ============================================================
// SÉLECTEUR DE PERSONNE — composant partagé, réutilisable sur tout
// formulaire ayant des champs Nom / Prénom pour une personne déjà
// connue de l'association (adoptant, réservant, emprunteur, etc.).
//
// Recherche déclenchée en tapant dans le champ Nom OU Prénom (les deux
// proposent la même liste). Contrairement au sélecteur d'animal, les
// champs remplis restent TOUJOURS librement modifiables — aucun
// verrouillage — pour gérer sans friction les cas où plusieurs
// personnes (ex : frères/soeurs) partagent une partie de leurs
// coordonnées.
//
// Fichier ADDITIF : n'importe pas sur formulaires-arche-mallo.js ni sur
// selecteur-animal.js.
//
// Nécessite : un client Supabase déjà créé (variable `supabaseClient`),
// et la fonction RPC rechercher_personnes() (déjà utilisée par
// formulaires_preremplis.html).
//
// @param {string} nomId       id du champ Nom
// @param {string} prenomId    id du champ Prénom (optionnel)
// @param {object} champs      { idChamp: cléPersonne } — champs du
//                              formulaire à remplir à partir de la
//                              personne choisie (adresse, code_postal,
//                              ville, email, telephone, raison_sociale…)
// @param {function} onSelect  callback(personneId, personne) optionnel
// ============================================================

function initSelecteurPersonne(config) {
    var idsChamps = [config.nomId, config.prenomId].filter(Boolean);
    var minLength = 2;

    function remplirDepuisPersonne(personne) {
        if (config.nomId) {
            var elNom = document.getElementById(config.nomId);
            if (elNom) {
                elNom.value = personne.type_personne === 'entreprise' ? (personne.raison_sociale || '') : (personne.nom || '');
                elNom.dispatchEvent(new Event('input', { bubbles: true }));
            }
        }
        if (config.prenomId) {
            var elPrenom = document.getElementById(config.prenomId);
            if (elPrenom && personne.type_personne !== 'entreprise') {
                elPrenom.value = personne.prenom || '';
                elPrenom.dispatchEvent(new Event('input', { bubbles: true }));
            }
        }
        Object.keys(config.champs || {}).forEach(function(idChamp) {
            var cle = config.champs[idChamp];
            var el = document.getElementById(idChamp);
            if (el && personne[cle] !== undefined && personne[cle] !== null && personne[cle] !== '') {
                el.value = personne[cle];
                el.dispatchEvent(new Event('input', { bubbles: true }));
            }
        });
    }

    function fermerToutes() {
        document.querySelectorAll('.selecteur-personne-dropdown').forEach(function(d) {
            d.style.display = 'none';
            d.innerHTML = '';
        });
    }

    idsChamps.forEach(function(id) {
        var input = document.getElementById(id);
        if (!input) {
            console.error('[Sélecteur personne] Champ introuvable :', id);
            return;
        }

        var dropdown = document.createElement('div');
        dropdown.className = 'selecteur-personne-dropdown no-print';
        dropdown.style.cssText = 'position:absolute;background:white;border:1px solid #ccc;border-radius:6px;box-shadow:0 4px 12px rgba(0,0,0,0.15);max-height:220px;overflow-y:auto;z-index:1000;display:none;min-width:220px;font-family:Arial,sans-serif;';
        input.parentNode.style.position = 'relative';
        input.parentNode.appendChild(dropdown);

        var timer = null;

        async function rechercher(texte) {
            try {
                const { data, error } = await supabaseClient.rpc('rechercher_personnes', { p_recherche: texte });
                if (error) throw error;
                afficherResultats(data || []);
            } catch (e) {
                console.error('[Sélecteur personne] Erreur recherche :', e.message);
            }
        }

        function afficherResultats(personnes) {
            dropdown.innerHTML = '';
            if (personnes.length === 0) {
                dropdown.innerHTML = '<div style="padding:8px 12px;color:#888;font-size:13px;">Aucune personne trouvée</div>';
                dropdown.style.display = 'block';
                return;
            }
            personnes.forEach(function(p) {
                var nomAff = p.type_personne === 'entreprise' ? (p.raison_sociale || '—') : ((p.prenom || '') + ' ' + (p.nom || '')).trim();
                var ligne = document.createElement('div');
                ligne.style.cssText = 'padding:8px 12px;cursor:pointer;font-size:14px;border-bottom:1px solid #f0f0f0;';
                ligne.innerHTML = '<strong>' + nomAff + '</strong>' + (p.ville ? ' — ' + p.ville : '');
                ligne.addEventListener('mouseenter', function() { ligne.style.background = '#f5f5f5'; });
                ligne.addEventListener('mouseleave', function() { ligne.style.background = ''; });
                ligne.addEventListener('click', function() {
                    remplirDepuisPersonne(p);
                    fermerToutes();
                    if (typeof config.onSelect === 'function') config.onSelect(p.id || null, p);
                });
                dropdown.appendChild(ligne);
            });
            dropdown.style.display = 'block';
        }

        input.addEventListener('input', function() {
            clearTimeout(timer);
            var texte = input.value.trim();
            if (texte.length < minLength) { dropdown.style.display = 'none'; dropdown.innerHTML = ''; return; }
            timer = setTimeout(function() { rechercher(texte); }, 250);
        });
        input.addEventListener('focus', function() {
            var texte = input.value.trim();
            if (texte.length >= minLength) rechercher(texte);
        });
        document.addEventListener('click', function(e) {
            if (!input.parentNode.contains(e.target)) { dropdown.style.display = 'none'; dropdown.innerHTML = ''; }
        });
    });
}
