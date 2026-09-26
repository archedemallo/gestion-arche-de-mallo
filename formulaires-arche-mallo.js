// ============================================================================
// Formulaires L'Arche de Mallo
// ============================================================================

// APPS_SCRIPT_URL est défini dans config.js

// ============================================================
// EN-TÊTE ASSOCIATION
// ============================================================
function creerEntete(options) {
    options = options || {};
    var dateId    = options.dateId    || 'dateAdoption';
    var dateLabel = options.dateLabel || 'Date :';
    var titre     = options.titre     || '';

    var el = document.getElementById('entete');
    if (!el) return;

    el.innerHTML =
        '<div class="header-adoption">' +
    '<div style="display:flex;align-items:center;gap:18px;flex:1;">' +
        '<div class="logo-box"></div>' +
        '<div class="header-info" style="font-size:11pt;">' +
            '<p class="bold">Association L\'ARCHE DE MALLO</p>' +
            '<p>' +
                '8 ter rue d\'Eschène<br>' +
                '90140 AUTRECHÊNE<br>' +
                '07.71.64.69.89<br>' +
                '<a href="mailto:archedemallo@gmail.com" class="blue">archedemallo@gmail.com</a>' +
            '</p>' +
        '</div>' +
    '</div>' +
    '<div class="header-adoption-right">' +
        dateLabel + ' <input type="date" class="editable editable-date" id="' + dateId + '"><br>' +
        '<span class="blue bold">Saisi par :</span> ' + 
        '<select class="editable editable-medium bold" id="saisiPar" data-required="true" data-label="Saisi par"></select>' +
    '</div>' +
'</div>' +
(titre ? '<div class="title">' + titre + '</div>' : '');

    // Pré-remplir la date à aujourd'hui
    var dateEl = document.getElementById(dateId);
    if (dateEl && !dateEl.value) {
        dateEl.value = new Date().toISOString().split('T')[0];
    }
}


let formSaved     = false;
let savedFilename = '';

// ============================================================
// CASES A COCHER
// ============================================================
function toggleCheck(element, groupName) {
    let box;
    if (element.classList.contains('checkbox')) {
        box       = element;
        groupName = element.getAttribute('data-group');
    } else if (element.classList.contains('clickable-row')) {
        box = element.querySelector('.checkbox');
        if (!groupName) groupName = box && box.getAttribute('data-group');
    } else {
        box = element.querySelector ? element.querySelector('.checkbox') : element;
        if (!groupName && box) groupName = box.getAttribute('data-group');
    }
    if (!box) return;
    if (groupName) {
        document.querySelectorAll('.checkbox[data-group="' + groupName + '"]').forEach(function(cb) {
            if (cb !== box) cb.classList.remove('checked');
        });
    }
    box.classList.toggle('checked');
}

// Toggle case à cocher multi-sélection (sans exclusion de groupe)
function toggleCheckMulti(element, event) {
    // Ignorer les clics qui viennent d'un input, textarea ou select enfant
    if (event && event.target) {
        var tag = event.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
    }
    // Support direct click on div.motif-ligne or span.clickable-row
    var box = element.querySelector ? element.querySelector('.checkbox') : element;
    if (box) box.classList.toggle('checked');
}

// Paiement dynamique : coche le mode ET affiche/masque le détail montant
function togglePaiement(element, mode) {
    var box    = element.querySelector('.checkbox');
    var detail = document.getElementById('detail_' + mode);
    if (!box) return;
    box.classList.toggle('checked');
    if (detail) detail.style.display = box.classList.contains('checked') ? 'inline' : 'none';
}

// ============================================================
// COLLECTE DES DONNEES
// ============================================================
function collectFormData() {
    var data = {};
    document.querySelectorAll('input.editable, textarea.editable').forEach(function(el) {
        if (el.id) data[el.id] = el.value;
    });
    
	
	// Collecter le sexe (cases à cocher)
	var sexeCoche = document.querySelector('.checkbox[data-group="sexe"].checked');
	if (sexeCoche) {
		data['sexe'] = sexeCoche.parentElement.textContent.trim();
	}
	
 // Collecter les cases multi-sélection (data-checked-group)
    document.querySelectorAll('.checkbox.checked[data-checked-group]').forEach(function(cb) {
        var group = cb.getAttribute('data-checked-group');
        var label = cb.parentElement.textContent.trim();
        data['check_' + group] = data['check_' + group]
            ? data['check_' + group] + ', ' + label
            : label;
    });
    
    document.querySelectorAll('input[type="checkbox"]:checked').forEach(function(cb) {
        var label = document.querySelector('label[for="' + cb.id + '"]');
        var key   = 'check_' + (cb.name || cb.id);
        data[key] = data[key]
            ? data[key] + ', ' + (label ? label.textContent.trim() : cb.id)
            : (label ? label.textContent.trim() : cb.id);
    });
    // Collecter les modes de paiement (multi-sélection par id)
    var modesPaiement = [];
    var payIds = {
        'pay_virement':          'Virement',
        'pay_cb':                'CB',
        'pay_espece':            'Espèce',
        'pay_cheque':            'Chèque',
        'pay_plusieurs_cheques': 'Plusieurs chèques'
    };
    Object.keys(payIds).forEach(function(id) {
        var el = document.getElementById(id);
        if (el && el.classList.contains('checked')) {
            modesPaiement.push(payIds[id]);
            // Collecter le montant associé si présent
            var modeKey = id.replace('pay_', '');
            var montantEl = document.getElementById('montant_' + modeKey);
            if (montantEl && montantEl.value) {
                data['montant_' + modeKey] = montantEl.value;
            }
        }
    });
    // Plusieurs chèques : collecter N° et montants par chèque
    var payPlusieurs = document.getElementById('pay_plusieurs_cheques');
    if (payPlusieurs && payPlusieurs.classList.contains('checked')) {
        ['1','2','3','4'].forEach(function(n) {
            var numEl = document.getElementById('cheque' + n);
            var mtEl  = document.getElementById('montant_cheque' + n);
            if (numEl && numEl.value) data['cheque' + n] = numEl.value;
            if (mtEl  && mtEl.value)  data['montant_cheque' + n] = mtEl.value;
        });
    }
    // Rétrocompatibilité ancien champ pay_2cheques
    var pay2 = document.getElementById('pay_2cheques');
    if (pay2 && pay2.classList.contains('checked')) {
        modesPaiement.push('Paiement en plusieurs fois');
    }
    if (modesPaiement.length > 0) {
        data['check_paiement'] = modesPaiement.join(', ');
    }
    // Autres animaux : collecter la case "Autre" + texte libre
    var animalAutre = document.getElementById('animal_autre');
    if (animalAutre && animalAutre.classList.contains('checked')) {
        var animalAutreTexte = document.getElementById('animal_autre_texte');
        data['animal_autre'] = animalAutreTexte ? animalAutreTexte.value : 'Autre';
    }

	// Calcul montant
var montant = 0;

if (document.getElementById('type_adherent')?.classList.contains('checked')) {
    var valAdherent = Number(document.getElementById('cotisationAdherent')?.value || 20);
    montant += valAdherent;
    data.cotisationAdherent = valAdherent;
}

if (document.getElementById('type_bienfaiteur')?.classList.contains('checked')) {
    montant += Number(document.getElementById('donBienfaiteur')?.value || 0);
}

if (document.getElementById('type_sympathisant')?.classList.contains('checked')) {
    montant += Number(document.getElementById('donSympatisant')?.value || 0);
}

data.montantAdhesion = montant;


	
    return data;
}

// ============================================================
// NOM DU FICHIER
// ============================================================
// Remplace les caractères accentués par leur équivalent sans accent
// (é -> e, à -> a, ç -> c...) au lieu de les transformer en "_" comme
// le fait le regex [^a-zA-Z0-9] plus loin. Sans ça, "prêt" devenait
// "pr_t" et "matériel" devenait "mat_riel" dans les noms de fichiers.
function retirerAccents(str) {
    return String(str || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

function buildFilename(data) {
    var date    = new Date();
    var dateStr = [
        String(date.getDate()).padStart(2, '0'),
        String(date.getMonth() + 1).padStart(2, '0'),
        date.getFullYear()
    ].join('-');
    var nomComplet = data.nomAdoptant || data.nomComplet || data.nomProprietaire ||
                      ((data.prenom || '') + ' ' + (data.nom || '')).trim() ||
                      data.raisonSociale || '';
    var nom   = retirerAccents(nomComplet).replace(/[^a-zA-Z0-9]/g, '_');
    var chat  = retirerAccents(data.nomChat || data.nomAnimal || data.chat || data.nom_animal || '').replace(/[^a-zA-Z0-9]/g, '_');
    var titre = retirerAccents(document.title).replace(/[^a-zA-Z0-9]/g, '_').substring(0, 40);
    var parts = [titre];
    if (nom)  parts.push(nom);
    if (chat) parts.push(chat);
    parts.push(dateStr);
    return parts.join('_');
}

// ============================================================
// CONSTRUIRE HTML AVEC DONNEES
// ============================================================
function buildHtmlWithData() {
    // Injecter la photo avant de sérialiser le DOM
    // (important : la photo doit être dans le DOM avant outerHTML)
    var previewAnimal = document.getElementById('preview_Animal');
    var photoSrcSaved = '';
    if (previewAnimal) {
        var previewImg = previewAnimal.querySelector('img');
        if (previewImg && previewImg.src && previewImg.src.startsWith('data:')) {
            photoSrcSaved = previewImg.src;
        } else if (previewAnimal._photoBase64) {
            photoSrcSaved = previewAnimal._photoBase64;
        }
        // Si on a la photo, s'assurer que l'img est bien dans le div AVANT outerHTML
        if (photoSrcSaved && (!previewImg || !previewImg.src.startsWith('data:'))) {
            previewAnimal.innerHTML = '<img src="' + photoSrcSaved + '" style="max-width:220px;max-height:160px;display:block;border:1px solid #ccc;border-radius:4px;">';
        }
    }

    var html = document.documentElement.outerHTML;

    document.querySelectorAll('input.editable').forEach(function(input) {
        if (!input.id || !input.value) return;
        var val = input.value
            .replace(/&/g, '&amp;')
            .replace(/"/g, '&quot;');
        var regex = new RegExp('(id="' + input.id + '")((?:[^>]*?))(>)', 'g');
        html = html.replace(regex, function(match, id, rest, end) {
            var cleanRest = rest.replace(/\s+value="[^"]*"/, '');
            return id + cleanRest + ' value="' + val + '"' + end;
        });
    });

    document.querySelectorAll('textarea.editable').forEach(function(textarea) {
        if (!textarea.id) return;
        var val = textarea.value
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
        var regex = new RegExp('(<textarea[^>]*?id="' + textarea.id + '"[^>]*>)[\\s\\S]*?(<\\/textarea>)', 'g');
        html = html.replace(regex, '$1' + val + '$2');
    });

    // Selects éditables (ex. "Saisi par") : le choix de l'utilisateur ne vit
    // que dans la propriété .value du <select>, jamais dans un attribut
    // "selected" du HTML sérialisé — sans ce traitement, le PDF/impression
    // retombe toujours sur la première option ("— Choisir —").
    document.querySelectorAll('select.editable').forEach(function(select) {
        if (!select.id) return;
        var val = select.value;
        var regex = new RegExp('(<select[^>]*?id="' + select.id + '"[^>]*>)([\\s\\S]*?)(<\\/select>)', 'g');
        html = html.replace(regex, function(match, openTag, optionsHtml, closeTag) {
            var cleaned = optionsHtml.replace(/\s+selected(="[^"]*")?/g, '');
            if (val) {
                var valEscaped = val.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                var optRegex = new RegExp('(<option[^>]*?value="' + valEscaped + '"(?![^>]*selected))');
                cleaned = cleaned.replace(optRegex, '$1 selected');
            }
            return openTag + cleaned + closeTag;
        });
    });

    // Remplacer les cases à cocher par ☑ ou ☐ selon leur état réel
    document.querySelectorAll('.checkbox').forEach(function(cb) {
        var isChecked = cb.classList.contains('checked');
        var symbol = isChecked ? '☑' : '☐';
        html = html.replace(cb.outerHTML,
            '<span style="font-size:14px;font-family:Arial;vertical-align:middle;">' + symbol + '</span>'
        );
    });

    // Cacher les boutons, canvas et bouton Effacer — afficher toutes les signatures images
    html = html.replace('<head>', '<head><style>' +
        '.buttons{display:none!important}' +
        '.signature-pad-wrap{display:none!important}' +
        '.signature-controls{display:none!important}' +
        '[id$="-print"]{display:block!important}' +
        'button{display:none!important}' +
        'input.editable{border:none!important;border-bottom:1px solid #333!important;background:transparent!important;-webkit-appearance:none!important;box-shadow:none!important;outline:none!important;}' +
'#puce,#nom,#prenom,#adresse,#email,#nomAttestation{min-width:300px!important;width:auto!important;}' +
        'label[style*="background:#0563c1"]{display:none!important}' +
'.preview-wrap p.small{display:none!important}' +
        '.no-print{display:none!important}' +
        '#preview_Animal{display:block!important;}' +
        '#preview_Animal img{display:block!important;max-width:220px!important;max-height:160px!important;border:1px solid #ccc!important;}' +
        '</style>');

    // Injecter les images de signature dans les placeholders
    // Chercher toutes les signatures disponibles (sig1, sig2, sig3...)
    var sigIds = ['sig1', 'sig2', 'sig3', 'sig4'];
    sigIds.forEach(function(sigId) {
        var canvas = document.querySelector('#' + sigId + ' canvas');
        if (canvas) {
            var sigImage = canvas.toDataURL('image/png');
            var printId = sigId + '-print';
            // Remplacer le [[SIGNATURE_IMAGE]] dans le div correspondant
            var regex = new RegExp('(id="' + printId + '"[^>]*>)\\[\\[SIGNATURE_IMAGE\\]\\]', 'g');
            html = html.replace(regex, '$1<img src="' + sigImage + '" style="max-width:280px;max-height:120px;border:1px solid #ccc;display:block;">');
        }
    });
    // Effacer les placeholders non remplis
    html = html.replace(/\[\[SIGNATURE_IMAGE\]\]/g, '');

    
// Dates : format français + masque invisible si vide
   html = html.replace(
    /<input([^>]*?)type="date"([^>]*?)>/g,
    function(match) {
        var valMatch = match.match(/value="([^"]*)"/);
        var val = valMatch ? valMatch[1] : '';
        var affichage = '';
        if (val) {
            var parts = val.split('-');
            if (parts.length === 3) affichage = parts[2] + '/' + parts[1] + '/' + parts[0];
        }
        return '<span style="border-bottom:1px solid #333;display:inline-block;min-width:100px;padding:0 2px;">'
            + affichage + '</span>';
    }
);
    // ── Injecter la photo de l'animal dans le HTML ──────────
    // La <img> est déjà dans le DOM (mise par aperçuPhoto via FileReader.onload)
    // On récupère son src base64 et on l'injecte explicitement dans le html sérialisé.
    var previewAnimal = document.getElementById('preview_Animal');
    if (previewAnimal) {
        var previewImg = previewAnimal.querySelector('img');
        var photoSrc = '';
        // Essai 1 : img déjà dans le DOM avec src base64
        if (previewImg && previewImg.src && previewImg.src.startsWith('data:')) {
            photoSrc = previewImg.src;
        }
        // Essai 2 : src stocké sur le div via _photoBase64
        if (!photoSrc && previewAnimal._photoBase64) {
            photoSrc = previewAnimal._photoBase64;
        }

        if (photoSrc) {
            var photoHtml = '<div id="preview_Animal" style="margin-top:8px;margin-bottom:8px;page-break-inside:avoid;">' +
                '<img src="' + photoSrc + '" style="max-width:220px;max-height:160px;display:block;border:1px solid #ccc;border-radius:4px;">' +
                '</div>';
            // Remplacer TOUTES les occurrences du div preview_Animal dans le html
            html = html.replace(/<div id="preview_Animal"[^>]*>[\s\S]*?<\/div>/g, photoHtml);
        }
    }

    return html;
}

// ============================================================
// ENCODAGE BASE64 UNICODE
// ============================================================
function encodeBase64Unicode(str) {
    var uint8 = new TextEncoder().encode(str);
    var binary = '';
    uint8.forEach(function(b) { binary += String.fromCharCode(b); });
    return btoa(binary);
}

// ============================================================
// ENVOI VERS GOOGLE
// ============================================================
async function sendToGoogle(data) {
    var json = JSON.stringify(data);
    console.log('Taille des donnees : ' + Math.round(json.length / 1024) + ' Ko');
    try {
        console.log('Envoi en cours...');
        await fetch(APPS_SCRIPT_URL, {
            method:  'POST',
            mode:    'no-cors',
            headers: { 'Content-Type': 'text/plain' },
            body:    json
        });
        console.log('Envoi termine');
        return true;
    } catch(e) {
        console.error('Erreur envoi :', e);
        return false;
    }
}

// ============================================================
// VALIDATION CHAMPS OBLIGATOIRES
// ============================================================

function validateRequiredFields() {
    var missing = [];

    // Champs input avec data-required
    document.querySelectorAll('[data-required="true"]').forEach(function(el) {
        var label = el.getAttribute('data-label') || el.id || 'Champ inconnu';
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') {
            if (!el.value || el.value.trim() === '') {
                missing.push(label);
                el.style.borderBottom = '2px solid red';
            } else {
                el.style.borderBottom = '';
            }
        }
    });

    // Cases "Lu et approuvé" — cherche luApprouve1 et luApprouve2 par préfixe (tous suffixes : _fa, _dep, _resa, _ab, etc.)
    ['luApprouve1', 'luApprouve2'].forEach(function(prefix) {
        // Cherche d'abord l'ID exact, sinon cherche un ID qui commence par ce préfixe
        var el = document.getElementById(prefix);
        if (!el) {
            el = document.querySelector('[id^="' + prefix + '"]');
        }
        if (el) {
            var box = el.querySelector('.checkbox');
            if (box && !box.classList.contains('checked')) {
                var labels = {
                    luApprouve1: 'Lu et approuvé (L\'Arche de Mallo)',
                    luApprouve2: 'Lu et approuvé (Signataire)'
                };
                missing.push(labels[prefix]);
                box.style.outline = '2px solid red';
                box.style.outlineOffset = '1px';
            } else if (box) {
                box.style.outline = '';
            }
        }
    });

    // Signatures
    ['sig1', 'sig2'].forEach(function(sigId) {
        var container = document.getElementById(sigId);
        if (!container) return;
        if (!container._signed) {
            var sigLabels = { sig1: 'Signature Arche de Mallo', sig2: 'Signature de l\'adoptant' };
            missing.push(sigLabels[sigId] || 'Signature manquante');
        }
    });

// Civilité obligatoire
    var civiliteChecked = document.querySelector('.checkbox[data-group="civilite"].checked');
    if (!civiliteChecked) {
        missing.push('Civilité (Monsieur ou Madame)');
        // Mettre en rouge uniquement les cases à cocher
        document.querySelectorAll('.checkbox[data-group="civilite"]').forEach(function(cb) {
            cb.style.outline = '2px solid red';
            cb.style.outlineOffset = '1px';
        });
    } else {
        // Retirer le rouge si une civilité est cochée
        document.querySelectorAll('.checkbox[data-group="civilite"]').forEach(function(cb) {
            cb.style.outline = '';
        });
    }
	
    // Paiement : au moins un mode obligatoire
    var allPayIds = ['pay_virement','pay_cb','pay_espece','pay_cheque','pay_plusieurs_cheques','pay_2cheques'];
    var paiementCoche = allPayIds.some(function(id) {
        var el = document.getElementById(id);
        return el && el.classList.contains('checked');
    });
    if (!paiementCoche) {
        missing.push('Mode de règlement (au moins un à cocher)');
        allPayIds.forEach(function(id) {
            var el = document.getElementById(id);
            if (el) { el.style.outline = '2px solid red'; el.style.outlineOffset = '1px'; }
        });
    } else {
        allPayIds.forEach(function(id) {
            var el = document.getElementById(id);
            if (el) el.style.outline = '';
        });
    }

    // N° chèque obligatoire si Chèque coché
    var payCheque = document.getElementById('pay_cheque');
    if (payCheque && payCheque.classList.contains('checked')) {
        var numPaiement = document.getElementById('numeroPaiement') || document.getElementById('numeroCheque');
        if (!numPaiement || !numPaiement.value.trim()) {
            missing.push('Numéro de chèque');
            if (numPaiement) numPaiement.style.borderBottom = '2px solid red';
        }
    }

    // Résultat FIV et Diarrhée si OUI coché
    var libRes = {
        resultatFIV:      'Résultat FIV/FEL (Négatif ou Positif)',
        resultatDiarrhee: 'Résultat test diarrhée (Négatif ou Positif)'
    };
	
    ['resultatFIV', 'resultatDiarrhee'].forEach(function(group) {
        if (document.body.getAttribute('data-required-group-' + group) === 'true') {
            var checked = document.querySelector('.checkbox[data-group="' + group + '"].checked');
            if (!checked) {
                missing.push(libRes[group]);
                // Mettre en rouge les cases NÉGATIF et POSITIF
                document.querySelectorAll('.checkbox[data-group="' + group + '"]').forEach(function(cb) {
                    cb.style.outline = '2px solid red';
                    cb.style.outlineOffset = '1px';
                });
            } else {
                // Retirer le rouge si une case est cochée
                document.querySelectorAll('.checkbox[data-group="' + group + '"]').forEach(function(cb) {
                    cb.style.outline = '';
                });
            }
        }
    });;

    // Email format
    document.querySelectorAll('input[type="email"].editable').forEach(function(el) {
        if (!el.value || el.value.trim() === '') return;
        var valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(el.value.trim());
        if (!valid) {
            missing.push('Email invalide : ' + el.value);
            el.style.borderBottom = '2px solid red';
        }
    });

    // Dates conditionnelles : marquer en rouge si obligatoires et vides
    ['dateVermifuge', 'prochainVermifuge', 'dateAntiPuces', 'dateprochainAntiPuces',
     'dateVaccin', 'dateRappel',
     'dateSterilisationCas1', 'dateLimiteSterilisation'].forEach(function(id) {
        var el = document.getElementById(id);
        if (el && el.getAttribute('data-required') === 'true' && !el.value) {
            el.style.borderBottom = '2px solid red';
        }
    });

    // Photo de l'animal — obligatoire si le champ existe dans le formulaire
    var photoAnimalInput = document.getElementById('photoAnimal');
    if (photoAnimalInput) {
        var lblAnimal = photoAnimalInput.parentElement;
        if (!photoAnimalInput.files || !photoAnimalInput.files[0]) {
            missing.push("Photo de l'animal (obligatoire)");
            if (lblAnimal) lblAnimal.style.outline = '2px solid red';
        } else {
            if (lblAnimal) lblAnimal.style.outline = '';
        }
    }

    return missing;
}








// ============================================================
// RÉCUPÉRER L'IMAGE DE SIGNATURE
// ============================================================
function getSignatureImage() {
    var canvas = document.querySelector('#sig1 canvas');
    if (!canvas) return '';
    return canvas.toDataURL('image/png');
}


// ============================================================
// BOUTON SAUVEGARDER
// ============================================================
async function saveForm() {
    // Validation des champs obligatoires
    var missing = validateRequiredFields();
    if (missing.length > 0) {
       afficherMessage('⚠️ Veuillez remplir les champs obligatoires :<br><br>• ' + missing.join('<br>• '), 'erreur');
        return;
    }

    var data     = collectFormData();
    var filename = buildFilename(data);

    data.onglet         = document.body.getAttribute('data-form-id') || document.title.substring(0, 30);
    data.filename       = filename;
    data.signatureImage = getSignatureImage(); // sig1 pour compatibilité
    data.htmlContent    = encodeBase64Unicode(buildHtmlWithData());

    var overlay = document.createElement('div');
    overlay.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.6);z-index:9999;display:flex;align-items:center;justify-content:center;color:white;font-size:18px;font-weight:bold;font-family:Arial;';
    overlay.innerHTML = '<div style="text-align:center">En cours...<br><br><small>Veuillez patienter</small></div>';
    document.body.appendChild(overlay);

    var ok = await sendToGoogle(data);
    document.body.removeChild(overlay);

    if (ok !== false) {
        formSaved     = true;
        savedFilename = filename;

        var btnSave  = document.querySelector('.btn-save');
        var btnPrint = document.querySelector('.btn-print');

        if (btnSave) {
            btnSave.textContent = 'Sauvegarde OK';
            btnSave.className   = 'btn btn-saved';
            btnSave.disabled    = true;
        }
        if (btnPrint) {
            btnPrint.textContent = 'Imprimer';
            btnPrint.className   = 'btn btn-print';
            btnPrint.disabled    = false;
        }

        // Hook post-save : permet à chaque formulaire d'envoyer ses photos
        if (typeof postSavePhotos === 'function') {
            await postSavePhotos(data, filename);
        }

        afficherMessage('✅ Mail généré<br>Vous pouvez maintenant imprimer si besoin.');
    } else {
        alert('Erreur lors de la sauvegarde. Vérifiez votre connexion.');
    }
}

// ============================================================
// Fonction afficher message
// ============================================================
function afficherMessage(texte, type) {
    var overlay = document.createElement('div');
    overlay.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:99999;display:flex;align-items:center;justify-content:center;';

    var couleurBordure = (type === 'erreur') ? '#c00000' : '#28a745';

    var boite = document.createElement('div');
    boite.style.cssText = 'background:white;border-radius:10px;padding:30px 40px;max-width:400px;width:90%;box-shadow:0 4px 20px rgba(0,0,0,0.3);border-top:4px solid ' + couleurBordure + ';font-family:Calibri,Arial,sans-serif;text-align:center;';
    boite.innerHTML =
        '<p style="font-size:15px;line-height:1.6;margin:0 0 20px;">' + texte + '</p>' +
        '<button onclick="this.closest(\'div[style*=fixed]\').remove()" ' +
        'style="background:' + couleurBordure + ';color:white;border:none;padding:10px 30px;border-radius:5px;cursor:pointer;font-size:14px;font-weight:bold;">OK</button>';

    overlay.appendChild(boite);
    document.body.appendChild(overlay);
}


// ============================================================
// BOUTON IMPRIMER
// ============================================================
function printForm() {
    if (!formSaved) {
        alert("Veuillez d'abord sauvegarder le formulaire.");
        return;
    }
    var originalTitle = document.title;
    document.title    = savedFilename || document.title;
    window.print();
    setTimeout(function() { document.title = originalTitle; }, 2000);
}

// ============================================================
// BOUTON NOUVEAU
// ============================================================
function resetForm() {
    if (!confirm('Voulez-vous vraiment reinitialiser le formulaire ? Toutes les donnees saisies seront perdues.')) return;

    var today      = getTodayISO();
    var excludeIds = ['dateNaissance', 'dateSterilisationPrevue', 'dateNaissancePersonne', 'dateVermifuge', 'prochainVermifuge','dateprochainAntiPuces', 'dateAntipuces', 'dateAntiPuces', 'dateVaccin' ,'dateRappel', 'dateSterilisationCas1', 'dateLimiteSterilisation', 'dateCertificatVeto', 'date_debut', 'date_fin', 'dateNaissanceMembre'];

    document.querySelectorAll('input.editable').forEach(function(input) {
        if (input.type === 'date') {
            input.value = excludeIds.includes(input.id) ? '' : today;
        } else {
            input.value = '';
        }
    });

    document.querySelectorAll('textarea.editable').forEach(function(t) { t.value = ''; });
    document.querySelectorAll('select.editable').forEach(function(s) { s.value = ''; });
    document.querySelectorAll('.checkbox').forEach(function(cb) { cb.classList.remove('checked'); });
    document.querySelectorAll('input[type="checkbox"]').forEach(function(cb) { cb.checked = false; });

    formSaved     = false;
    savedFilename = '';

    var btnSave  = document.querySelector('.btn-save');
    var btnPrint = document.querySelector('.btn-print');

    if (btnSave) {
        btnSave.textContent = 'Sauvegarder';
        btnSave.className   = 'btn btn-save';
        btnSave.disabled    = false;
    }
    if (btnPrint) {
        btnPrint.textContent = 'Imprimer';
        btnPrint.className   = 'btn btn-print btn-print-disabled';
        btnPrint.disabled    = true;
    }
}

// ============================================================
// UTILITAIRES
// ============================================================
function getTodayISO() {
    var d = new Date();
    return [
        d.getFullYear(),
        String(d.getMonth() + 1).padStart(2, '0'),
        String(d.getDate()).padStart(2, '0')
    ].join('-');
}

// ============================================================
// INIT
// ============================================================
document.addEventListener('DOMContentLoaded', function() {
    var today      = getTodayISO();
    var excludeIds = ['dateNaissance', 'dateSterilisationPrevue', 'dateNaissancePersonne', 'dateVermifuge', 'prochainVermifuge', 'dateAntipuces', 'dateAntiPuces', 'dateprochainAntiPuces', 'dateVaccin', 'dateRappel', 'dateSterilisationCas1', 'dateLimiteSterilisation', 'dateCertificatVeto', 'date_debut', 'date_fin'];

    document.querySelectorAll('input[type="date"].editable').forEach(function(el) {
        if (!excludeIds.includes(el.id) && !el.value) {
            el.value = today;
        }
    });

    // Forcer le vidage des dates qui ne doivent pas se remplir automatiquement
    // (annule l'autofill de Chrome)
    excludeIds.forEach(function(id) {
        var el = document.getElementById(id);
        if (el) el.value = '';
    });

    makeDraggable();
});

// ============================================================
// DRAG & DROP
// ============================================================
function makeDraggable() {
    var panel = document.querySelector('.buttons');
    if (!panel) return;

    var isDragging = false;
    var startX, startY, offsetX = 0, offsetY = 0;

    function onStart(e) {
        if (e.target.classList.contains('btn')) return;
        isDragging = true;
        var point = e.touches ? e.touches[0] : e;
        startX = point.clientX - offsetX;
        startY = point.clientY - offsetY;
    }

    function onMove(e) {
        if (!isDragging) return;
        e.preventDefault();
        var point = e.touches ? e.touches[0] : e;
        offsetX = point.clientX - startX;
        offsetY = point.clientY - startY;
        panel.style.transform = 'translate(' + offsetX + 'px, ' + offsetY + 'px)';
    }

    function onEnd() { isDragging = false; }

    panel.addEventListener('mousedown',  onStart);
    panel.addEventListener('touchstart', onStart, { passive: false });
    document.addEventListener('mousemove',  onMove);
    document.addEventListener('touchmove',  onMove, { passive: false });
    document.addEventListener('mouseup',  onEnd);
    document.addEventListener('touchend', onEnd);
}



// ============================================================
// SIGNATURE TACTILE
// ============================================================

function creerSignature(containerId, width, height) {
    width  = width  || 280;
    height = height || 120;

    var container = document.getElementById(containerId);
    if (!container) return;

    var wrap   = document.createElement('div');
    wrap.className = 'signature-pad-wrap';

    var canvas = document.createElement('canvas');
    canvas.width  = width;
    canvas.height = height;
    wrap.appendChild(canvas);
    container.appendChild(wrap);

    var btn = document.createElement('button');
    btn.textContent = 'Effacer';
    container.appendChild(btn);

    var ctx     = canvas.getContext('2d');
    var drawing = false;
    var signed  = false;

    // FLAG : indique qu'une signature a été tracée
    container._signed = false;

    ctx.strokeStyle = '#000';
    ctx.lineWidth   = 2;
    ctx.lineCap     = 'round';

    function hint() {
        ctx.fillStyle = '#bbb';
        ctx.font      = 'italic 12px Arial';
        ctx.fillText('Signez ici...', 8, height / 2);
    }
    hint();

    function getPos(e) {
        var rect  = canvas.getBoundingClientRect();
        var point = e.touches ? e.touches[0] : e;
        return { x: point.clientX - rect.left, y: point.clientY - rect.top };
    }
    function start(e) {
        e.preventDefault();
        if (!signed) { ctx.clearRect(0, 0, width, height); signed = true; }
        drawing = true;
        container._signed = true;  // FLAG activé
        var pos = getPos(e);
        ctx.beginPath();
        ctx.moveTo(pos.x, pos.y);
    }
    function draw(e) {
        if (!drawing) return;
        e.preventDefault();
        var pos = getPos(e);
        ctx.lineTo(pos.x, pos.y);
        ctx.stroke();
    }
    function stop() { drawing = false; }

    canvas.addEventListener('mousedown',  start);
    canvas.addEventListener('mousemove',  draw);
    canvas.addEventListener('mouseup',    stop);
    canvas.addEventListener('mouseleave', stop);
    canvas.addEventListener('touchstart', start, { passive: false });
    canvas.addEventListener('touchmove',  draw,  { passive: false });
    canvas.addEventListener('touchend',   stop);

    btn.addEventListener('click', function() {
        ctx.clearRect(0, 0, width, height);
        signed = false;
        container._signed = false;  // FLAG remis à zéro
        hint();
    });
}

function majObligatoire(group, champIds, valeursOui) {
    valeursOui = valeursOui || ['OUI'];
    var checked  = document.querySelector('.checkbox[data-group="' + group + '"].checked');
    var estActif = false;
    if (checked) {
        var texte = checked.parentElement.textContent.trim().toUpperCase();
        estActif  = valeursOui.some(function(v) { return texte.startsWith(v.toUpperCase()); });
    }
    // Cas 1 / Cas 2 : testés via leur id direct
    if (group === 'cas1direct') {
        var c = document.getElementById('cas1_check');
        estActif = c ? c.classList.contains('checked') : false;
    }
    if (group === 'cas2direct') {
        var c = document.getElementById('cas2_check');
        estActif = c ? c.classList.contains('checked') : false;
    }
    champIds.forEach(function(id) {
        var el = document.getElementById(id);
        if (!el) { document.body.setAttribute('data-required-group-' + id, estActif ? 'true' : ''); return; }
        if (estActif) {
            el.setAttribute('data-required', 'true');
            el.setAttribute('data-label', el.getAttribute('data-label') || id);
        } else {
            el.removeAttribute('data-required');
            el.style.borderBottom = '';
        }
    });
}

// ============================================================
// PHOTO — aperçu + redimensionnement (partagé)
// ============================================================
function aperçuPhoto(input, previewId) {
    var preview = document.getElementById(previewId);
    if (!preview) return;
    if (!input.files || !input.files[0]) return;
    var file = input.files[0];
    var reader = new FileReader();
    reader.onload = function(e) {
        var src = e.target.result;
        preview.innerHTML = '<img src="' + src + '" style="max-width:200px;max-height:150px;margin-top:4px;border:1px solid #ccc;border-radius:4px;" alt="Photo animal">' +
            '<br><span class="no-print" style="font-size:10px;color:green;">✔ ' + file.name + '</span>';
        // Stocker sur le div ET sur l'img pour retrouver dans buildHtmlWithData
        preview._photoBase64 = src;
        var img = preview.querySelector('img');
        if (img) img._photoBase64 = src;
    };
    reader.readAsDataURL(file);
}

// Ouvre la photo en plein écran dans un nouvel onglet. Manquait de ce
// fichier partagé — n'était dupliquée que dans adoption.html et
// reservation.html, absente de famille_accueil.html (ReferenceError au
// clic sur "Voir la photo" — repéré en revue de code, corrigé en la
// rendant commune comme aperçuPhoto ci-dessus).
function ouvrirPhoto(previewId) {
    var preview = document.getElementById(previewId);
    if (!preview || !preview._photoBase64) return;
    var w = window.open();
    w.document.write('<body style="margin:0;background:#000;"><img src="' + preview._photoBase64 + '" style="max-width:100%;height:auto;display:block;margin:auto;"></body>');
    w.document.close();
}

function redimensionnerImage(file, callback) {
    var reader = new FileReader();
    reader.onload = function(e) {
        var img = new Image();
        img.onload = function() {
            var canvas = document.createElement('canvas');
            var max = 1200;
            var w = img.width, h = img.height;
            if (w > max || h > max) {
                if (w > h) { h = Math.round(h * max / w); w = max; }
                else       { w = Math.round(w * max / h); h = max; }
            }
            canvas.width = w; canvas.height = h;
            canvas.getContext('2d').drawImage(img, 0, 0, w, h);
            callback(canvas.toDataURL('image/jpeg', 0.7).split(',')[1]);
        };
        img.src = e.target.result;
    };
    reader.readAsDataURL(file);
}

/**
 * Envoie la photo "photoAnimal" à Apps Script.
 * @param {string} onglet   - nom de l'onglet Google Sheets (ex: 'Famille_Accueil_Provisoire')
 * @param {string} nomPers  - nom de la personne (adoptant, famille, etc.)
 * @param {string} nomAnimal - nom du chat/animal
 * @param {string} dateStr  - date au format YYYY-MM-DD
 */
// ============================================================
// PRÉ-REMPLISSAGE DEPUIS URL (?prefill=...)
// ============================================================

/**
 * À appeler dans le DOMContentLoaded de chaque formulaire.
 * Lit le paramètre ?prefill= dans l'URL et remplit tous les champs
 * dont l'id correspond à une clé du JSON.
 *
 * Exemple d'appel dans un formulaire :
 *   document.addEventListener('DOMContentLoaded', function() {
 *       creerEntete({ ... });
 *       appliquerPrefill();   // <-- ajouter cette ligne
 *   });
 */
function appliquerPrefill() {
    try {
        var params = new URLSearchParams(window.location.search);
        var raw    = params.get('prefill');
        if (!raw) return;

        var data = JSON.parse(decodeURIComponent(raw));
        if (!data || typeof data !== 'object') return;

        // Bannière d'info discrète
        var banner = document.createElement('div');
        banner.style.cssText = [
            'position:fixed', 'top:0', 'left:0', 'right:0', 'z-index:9999',
            'background:#2a7a4b', 'color:#fff', 'text-align:center',
            'font-family:DM Sans,Arial,sans-serif', 'font-size:13pt',
            'padding:9px 16px', 'box-shadow:0 2px 8px rgba(0,0,0,0.15)',
            'display:flex', 'align-items:center', 'justify-content:center', 'gap:12px'
        ].join(';');
        banner.innerHTML = '✅ Formulaire pré-rempli depuis les données existantes'
            + ' <button onclick="this.parentElement.remove()" style="'
            + 'background:rgba(255,255,255,0.25);border:none;border-radius:6px;'
            + 'color:#fff;font-size:12pt;padding:2px 10px;cursor:pointer;margin-left:8px;">✕</button>';
        document.body.appendChild(banner);
        setTimeout(function() { if (banner.parentElement) banner.remove(); }, 5000);

        // Remplir les champs input et textarea
        var remplis = 0;
        Object.keys(data).forEach(function(cle) {
            if (cle === '_source') return;
            var val = data[cle];
            if (!val || String(val).trim() === '') return;

            var el = document.getElementById(cle);
            if (!el) return;

            if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                // Convertir date JJ/MM/AAAA → AAAA-MM-JJ pour les input[type=date]
                if (el.type === 'date') {
                    var parts = String(val).split('/');
                    if (parts.length === 3) {
                        val = parts[2] + '-' + parts[1] + '-' + parts[0];
                    }
                }
                el.value = val;
                el.dispatchEvent(new Event('input', { bubbles: true }));
                remplis++;
            }
        });

        // Afficher la photo prise lors de la réservation (référence visuelle
        // uniquement — un input[type=file] ne peut pas être prérempli par
        // script, la capture de la photo d'adoption reste obligatoire).
        if (data.photoReservation) {
            var zonePhotoReservation = document.getElementById('photoReservationPreview');
            if (zonePhotoReservation) {
                zonePhotoReservation.innerHTML =
                    '<p class="bold blue no-print" style="margin:0 0 6px;">📷 Photo prise lors de la réservation</p>' +
                    '<img src="' + data.photoReservation + '" style="max-width:200px;max-height:150px;border:1px solid #ccc;border-radius:4px;display:block;" alt="Photo réservation">' +
                    '<button type="button" class="btn-voir-photo no-print" style="margin-top:4px;" onclick="window.open(\'' + data.photoReservation + '\', \'_blank\')">Voir la photo</button>' +
                    '<p class="no-print" style="font-size:11px;color:#666;margin:4px 0 0;">Référence uniquement, non modifiable ici</p>';
                zonePhotoReservation.style.display = 'block';
            }
        }

        // Gérer le sexe (case à cocher radio) — cherche la case dont le texte correspond
        var sexeVal = data['sexe'] || data['check_sexe'] || data['check_sexe_chat'] || '';
        if (sexeVal) {
            // Chercher dans les groupes 'sterilise', 'sexe', 'sexe_chat'
            ['sexe', 'sexe_chat', 'check_sexe'].forEach(function(grp) {
                document.querySelectorAll('.checkbox[data-group="' + grp + '"]').forEach(function(cb) {
                    var txt = (cb.parentElement ? cb.parentElement.textContent : '').trim().toLowerCase();
                    var sexeNorm = sexeVal.trim().toLowerCase();
                    if (txt === sexeNorm || 
                        (sexeNorm.includes('mâle') && txt === 'mâle') ||
                        (sexeNorm.includes('male') && txt === 'mâle') ||
                        (sexeNorm.includes('femelle') && txt === 'femelle')) {
                        // Décocher tous du groupe puis cocher celui-ci
                        document.querySelectorAll('.checkbox[data-group="' + grp + '"]').forEach(function(c) { c.classList.remove('checked'); });
                        cb.classList.add('checked');
                    }
                });
            });
        }

        console.log('[Prefill] ' + remplis + ' champ(s) pré-rempli(s) depuis ' + (data._source || '?'));

    } catch(e) {
        console.warn('[Prefill] Erreur lors du pré-remplissage :', e.message);
    }
}

async function envoyerPhotoAnimal(onglet, prenom, nom, nomAnimal, dateStr) {
    var input = document.getElementById('photoAnimal');
    if (!input || !input.files || !input.files[0]) return true;
    var date = dateStr || new Date().toISOString().split('T')[0];
    // Version "propre" (underscores) réservée UNIQUEMENT au nom de fichier.
    var prenomFichier = (prenom   || ''       ).replace(/\s+/g, '_');
    var nomFichier     = (nom     || 'Inconnu').replace(/\s+/g, '_');
    var animalFichier  = (nomAnimal || 'Animal').replace(/\s+/g, '_');
    var filename = [prenomFichier, nomFichier, animalFichier, 'Photo', date].filter(Boolean).join('_');
    return await new Promise(function(resolve) {
        redimensionnerImage(input.files[0], function(base64) {
            fetch(window.APPS_SCRIPT_URL || APPS_SCRIPT_URL, {
                method: 'POST',
                // text/plain exprès (voir sendToGoogle juste au-dessus) : évite
                // la pré-vérification CORS que l'Apps Script ne gère pas.
                // Contrairement à avant (mode:'no-cors'), on lit maintenant la
                // réponse pour savoir si l'envoi a vraiment réussi côté Drive.
                headers: { 'Content-Type': 'text/plain' },
                body: JSON.stringify({
                    action:      'photo',
                    onglet:      onglet,
                    filename:    filename,
                    imageBase64: base64,
                    mimeType:    'image/jpeg',
                    prenom:      (prenom   || ''       ).trim(),
                    nom:         (nom      || 'Inconnu').trim(),
                    animal:      (nomAnimal || 'Animal').trim(),
                    dateDossier: date
                })
            }).then(async function(resp) {
                var result = {};
                try { result = await resp.json(); } catch (e) { /* réponse non-JSON */ }
                if (!resp.ok || result.status !== 'ok') {
                    console.error('[Photo] Échec de l\'envoi vers Drive :', result.message || ('HTTP ' + resp.status));
                    resolve(false);
                } else {
                    resolve(true);
                }
            }).catch(function(e) {
                console.error('[Photo] Erreur réseau lors de l\'envoi :', e);
                resolve(false);
            });
        });
    });
}

// ============================================================
// CONNEXION SUIVI — suite à la revue de code : les formulaires étaient
// jusqu'ici en accès public, et leurs fonctions SQL (SECURITY DEFINER,
// donc hors RLS) étaient appelables directement par n'importe qui
// connaissant la clé anon publique. Chaque formulaire doit désormais
// être précédé d'une connexion. Mutualisé ici pour ne pas dupliquer 14
// fois la même logique — chaque formulaire n'a besoin que du bloc HTML
// #login-screen et d'un appel à initSessionSuivi() juste après avoir
// créé son supabaseClient (supabaseClient n'existe pas encore quand ce
// fichier se charge, donc cet appel ne peut pas se faire tout seul ici).
// ============================================================
async function seConnecterSuivi() {
    var errEl = document.getElementById('login-err');
    errEl.textContent = '';
    var email = document.getElementById('login-email').value.trim();
    var password = document.getElementById('login-password').value;
    var res = await supabaseClient.auth.signInWithPassword({ email: email, password: password });
    if (res.error) { errEl.textContent = 'Connexion refusée : ' + res.error.message; return; }
    await verifierAccesSuivi(res.data.user);
}

async function seDeconnecterSuivi() {
    await supabaseClient.auth.signOut();
    location.reload();
}

async function verifierAccesSuivi(user) {
    var errEl = document.getElementById('login-err');
    try {
        var res = await supabaseClient.from('profils_suivi').select('email').eq('user_id', user.id).maybeSingle();
        if (res.error || !res.data) {
            if (errEl) errEl.textContent = "Ce compte n'est pas autorisé sur Suivi.";
            await supabaseClient.auth.signOut();
            return;
        }
        var screen = document.getElementById('login-screen');
        if (screen) screen.style.display = 'none';
    } catch (e) {
        // Échec réseau (pas un refus d'accès) : on ne bloque pas l'écran
        // de connexion sans explication, on propose de réessayer.
        afficherErreurChargement(e);
    }
}

// À appeler explicitement depuis chaque formulaire, juste après avoir
// créer supabaseClient (voir note ci-dessus).
function initSessionSuivi() {
    supabaseClient.auth.getSession().then(function(res) {
        if (res.data.session) verifierAccesSuivi(res.data.session.user);
    }).catch(function(e) {
        afficherErreurChargement(e);
    });
}

// ============================================================
// LISTE "SAISI PAR" — remplace le champ texte libre qui n'existait dans
// aucun formulaire jusqu'ici (id="saisiPar" référencé côté JS mais
// jamais présent dans le HTML, repéré en revue de code : le paramètre
// était donc toujours vide). Alimente un <select id="saisiPar">, à
// appeler après avoir créé supabaseClient.
// ============================================================
async function chargerListeSaisisseurs(selectId) {
    var select = document.getElementById(selectId || 'saisiPar');
    if (!select) return;
    var res = await supabaseClient.from('utilisateurs').select('id, nom').eq('actif', true).order('nom');
    if (res.error) { console.error('[chargerListeSaisisseurs]', res.error.message); return; }
    select.innerHTML = '<option value="">— Choisir —</option>' +
        (res.data || []).map(function(u) { return '<option value="' + u.id + '">' + u.nom.replace(/</g,'&lt;') + '</option>'; }).join('');
}
