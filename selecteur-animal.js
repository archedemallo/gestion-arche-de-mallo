// ============================================================
// SÉLECTEUR D'ANIMAL — composant partagé, réutilisable sur tout
// formulaire ayant besoin de choisir un animal existant (Adoption,
// et plus tard les 3 formulaires de Réservation).
//
// Fichier ADDITIF : ne modifie pas formulaires-arche-mallo.js, pour ne
// rien changer aux formulaires pas encore migrés vers Supabase.
//
// Nécessite : un client Supabase déjà créé (variable `supabaseClient`),
// et les deux fonctions RPC rechercher_animaux() / obtenir_animal_pour_formulaire()
// (voir 004_selecteur_animal.sql).
// ============================================================

/**
 * @param {string} inputId       id du champ texte qui sert de recherche
 *                                (remplace un champ nomUsuel en saisie libre)
 * @param {string} contexte      'reservation' ou 'adoption' — c'est la
 *                                fonction SQL rechercher_animaux() qui décide
 *                                des statuts autorisés pour ce contexte, pas
 *                                le navigateur (voir 004_selecteur_animal.sql)
 * @param {object} champsVerrouilles  { idChamp: valeurAnimal } — champs à
 *                                remplir et verrouiller une fois l'animal choisi
 * @param {object} champsModifiables idem mais le champ reste éditable
 * @param {object} champsPersonne    idem, pour préremplir l'adoptant/réservant
 *                                si l'animal est déjà réservé (non verrouillés)
 * @param {function} onSelect    callback(animalId, reservationId) appelé après
 *                                la sélection, pour mémoriser l'id choisi
 */
function initSelecteurAnimal(config) {
    var input = document.getElementById(config.inputId);
    if (!input) {
        console.error('[Sélecteur animal] Champ introuvable :', config.inputId);
        return;
    }

    var dropdown = document.createElement('div');
    dropdown.className = 'selecteur-animal-dropdown no-print';
    dropdown.style.cssText = 'position:absolute;background:white;border:1px solid #ccc;border-radius:6px;box-shadow:0 4px 12px rgba(0,0,0,0.15);max-height:220px;overflow-y:auto;z-index:1000;display:none;min-width:220px;';
    input.parentNode.style.position = 'relative';
    input.parentNode.appendChild(dropdown);

    var animalIdChoisi = null;
    var reservationIdChoisi = null;
    var minLength = 0; // 0 = affiche tout de suite la liste au focus
    var timer = null;

    var lienChanger = document.createElement('a');
    lienChanger.href = '#';
    lienChanger.textContent = 'changer';
    lienChanger.className = 'no-print';
    lienChanger.style.cssText = 'display:none;font-size:12px;margin-left:8px;';
    input.parentNode.insertBefore(lienChanger, dropdown);
    lienChanger.addEventListener('click', function(e) {
        e.preventDefault();
        input.readOnly = false;
        input.style.background = '';
        input.value = '';
        lienChanger.style.display = 'none';
        deverrouillerTout();
        if (typeof config.onSelect === 'function') config.onSelect(null, null);
        input.focus();
    });

    function fermer() {
        dropdown.style.display = 'none';
        dropdown.innerHTML = '';
    }

    function deverrouillerTout() {
        Object.keys(config.champsVerrouilles || {}).forEach(function(id) {
            var el = document.getElementById(id);
            if (el) { el.readOnly = false; el.style.background = ''; }
        });
        animalIdChoisi = null;
        reservationIdChoisi = null;
    }

    async function rechercher(texte) {
        try {
            const { data, error } = await supabaseClient.rpc('rechercher_animaux', {
                p_recherche: texte,
                p_contexte: config.contexte
            });
            if (error) throw error;
            afficherResultats(data || []);
        } catch (e) {
            console.error('[Sélecteur animal] Erreur recherche :', e.message);
        }
    }

    function afficherResultats(animaux) {
        dropdown.innerHTML = '';
        if (animaux.length === 0) {
            dropdown.innerHTML = '<div style="padding:8px 12px;color:#888;font-size:13px;">Aucun animal trouvé</div>';
            dropdown.style.display = 'block';
            return;
        }
        animaux.forEach(function(a) {
            var ligne = document.createElement('div');
            ligne.style.cssText = 'padding:8px 12px;cursor:pointer;font-size:14px;border-bottom:1px solid #f0f0f0;';
            var badge = a.statut_actuel === 'reserve' ? ' <span style="color:#9a3412;font-size:11px;">(réservé)</span>' : '';
            var numero = a.numero_interne ? '<span style="color:#888;font-size:11px;">' + a.numero_interne + '</span> — ' : '';
            ligne.innerHTML = numero + '<strong>' + a.nom_usuel + '</strong>' + badge +
                (a.couleur ? ' — ' + a.couleur : '');
            ligne.addEventListener('mouseenter', function() { ligne.style.background = '#f5f5f5'; });
            ligne.addEventListener('mouseleave', function() { ligne.style.background = ''; });
            ligne.addEventListener('click', function() { choisir(a.id); });
            dropdown.appendChild(ligne);
        });
        dropdown.style.display = 'block';
    }

    async function choisir(animalId) {
        try {
            const { data, error } = await supabaseClient.rpc('obtenir_animal_pour_formulaire', { p_animal_id: animalId });
            if (error) throw error;
            if (!data) return;

            input.value = data.animal.nom_usuel;
            input.readOnly = true;
            input.style.background = '#f0f0f0';
            lienChanger.style.display = 'inline';
            fermer();

            Object.keys(config.champsVerrouilles || {}).forEach(function(id) {
                var champAnimal = config.champsVerrouilles[id];
                var el = document.getElementById(id);
                if (el && data.animal[champAnimal] !== undefined && data.animal[champAnimal] !== null) {
                    el.value = data.animal[champAnimal];
                    el.readOnly = true;
                    el.style.background = '#f0f0f0';
                }
            });
            Object.keys(config.champsModifiables || {}).forEach(function(id) {
                var champAnimal = config.champsModifiables[id];
                var el = document.getElementById(id);
                if (el && data.animal[champAnimal] !== undefined && data.animal[champAnimal] !== null) {
                    el.value = data.animal[champAnimal];
                }
            });

            if (data.personne && config.champsPersonne) {
                Object.keys(config.champsPersonne).forEach(function(id) {
                    var champPersonne = config.champsPersonne[id];
                    var el = document.getElementById(id);
                    if (el && data.personne[champPersonne] !== undefined && data.personne[champPersonne] !== null) {
                        el.value = data.personne[champPersonne];
                    }
                });
            }

            animalIdChoisi = animalId;
            reservationIdChoisi = data.reservation_id || null;
            if (typeof config.onSelect === 'function') {
                config.onSelect(animalIdChoisi, reservationIdChoisi);
            }
        } catch (e) {
            console.error('[Sélecteur animal] Erreur sélection :', e.message);
        }
    }

    input.addEventListener('input', function() {
        deverrouillerTout();
        if (typeof config.onSelect === 'function') config.onSelect(null, null);
        clearTimeout(timer);
        var texte = input.value;
        if (texte.length < minLength) { fermer(); return; }
        timer = setTimeout(function() { rechercher(texte); }, 200);
    });
    input.addEventListener('focus', function() {
        if (!animalIdChoisi) rechercher(input.value);
    });
    document.addEventListener('click', function(e) {
        if (!input.parentNode.contains(e.target)) fermer();
    });

    return {
        getAnimalId: function() { return animalIdChoisi; },
        getReservationId: function() { return reservationIdChoisi; }
    };
}
