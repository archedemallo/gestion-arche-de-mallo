// ============================================================
// Appel générique de l'Edge Function "envoyer-mail-formulaire".
// À utiliser par n'importe quel formulaire Suivi une fois son PDF
// (pdf-lib) prêt : construire sujet/corps, convertir le PDF en base64,
// puis appeler envoyerMailFormulaire(). Contrairement à l'ancien appel
// Apps Script en mode:'no-cors', celui-ci répond normalement — en cas
// d'échec, on le sait et on peut prévenir la personne qui saisit.
// ============================================================

async function envoyerMailFormulaire({ sujet, corps, pdfBytes, pdfNomFichier, emailClient, nomClient }) {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) throw new Error("Session expirée — reconnectez-vous puis réessayez.");

    const url = SUPABASE_URL + '/functions/v1/envoyer-mail-formulaire';
    const pdfBase64 = arrayBufferToBase64(pdfBytes);

    const resp = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + session.access_token,
            'apikey': SUPABASE_ANON_KEY,
        },
        body: JSON.stringify({ sujet, corps, pdfBase64, pdfNomFichier, emailClient, nomClient }),
    });

    let result = {};
    try { result = await resp.json(); } catch (e) { /* réponse non-JSON, traité ci-dessous */ }

    if (!resp.ok || !result.ok) {
        throw new Error(result.error || ('Échec de l\'envoi (HTTP ' + resp.status + ')'));
    }
    return result; // { ok: true, destinataires: [...] }
}

// ============================================================
// ← AJOUTÉ : CORPS DU MAIL AVEC RÉSUMÉ
// Reprend le principe de construireCorpsMail() de l'ancien projet
// (Apps Script / Google Sheets) : le mail ne contient plus seulement
// une phrase générique, mais un résumé des informations saisies,
// pour que compta/bureau puissent lire l'essentiel sans ouvrir le PDF.
// À appeler juste avant envoyerMailFormulaire(), avec le même objet
// `data` que celui collecté par collectFormData().
// ============================================================
function formatDateFR(iso) {
    if (!iso) return '';
    var m = String(iso).match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!m) return iso;
    return m[3] + '/' + m[2] + '/' + m[1];
}

function formatDateHeureFR(date) {
    try {
        return new Intl.DateTimeFormat('fr-FR', {
            timeZone: 'Europe/Paris',
            day: '2-digit', month: '2-digit', year: 'numeric',
            hour: '2-digit', minute: '2-digit'
        }).format(date).replace(',', ' à');
    } catch (e) {
        return date.toLocaleString('fr-FR');
    }
}

// Libellés lisibles des onglets (= data-form-id de chaque formulaire)
var LIBELLES_ONGLET = {
    adoption:               'Contrat de cession à charge',
    reservation:            'Réservation Chat',
    adhesion:               'Adhésion',
    don:                    'Don',
    depot_chat:             'Dépôt Chat',
    famille_accueil:        "Famille d'accueil",
    certificat_engagement:  "Certificat d'engagement",
    abandon:                'Abandon',
    decharge_vaccin:        'Décharge 2ème vaccin',
    attestation_cbs_absent: 'Attestation CBS absent',
    pret_materiel:          'Prêt de matériel',
    retour_materiel:        'Retour de matériel',
    recu_fiscal_particulier:'Reçu fiscal (particulier)',
    recu_fiscal_entreprise: 'Reçu fiscal (entreprise)'
};

// Libellés lisibles des champs (fusion des champs de tous les formulaires)
var LIBELLES_CHAMPS = {
    nom: 'Nom', prenom: 'Prénom', nomComplet: 'Nom et prénom',
    raisonSociale: 'Raison sociale', representant: 'Représentant',
    formeJuridique: 'Forme juridique', sirenEntreprise: 'SIREN',
    adresse: 'Adresse', codePostal: 'Code postal', code_postal: 'Code postal', ville: 'Ville', commune: 'Commune',
    email: 'Email', portable: 'Téléphone portable', telephone: 'Téléphone',
    dateFait: 'Fait le', date_fait: 'Fait le', lieu: 'Fait à',
    saisiPar: 'Saisi par',
    check_civilite: 'Civilité', check_sexe: 'Sexe', sexe: 'Sexe',
    check_paiement: 'Mode de règlement', check_vaccin: 'Vaccin', check_sterilise: 'Stérilisé',
    check_espece: 'Espèce', check_anonyme: 'Don anonyme', check_typeDonateur: 'Type de donateur',
    check_souhaiteRecu: 'Souhaite un reçu fiscal', check_type: "Type d'adhésion",
    nomUsuel: 'Nom usuel animal', nomAdoption: 'Nom choisi par la famille', nomChat: 'Nom du chat', nom_chat: 'Nom du chat',
    nomMaman: 'Nom de la maman', nomAnimal: 'Nom de l\'animal', nom_animal: 'Nom de l\'animal',
    couleur: 'Couleur', dateNaissance: 'Date de naissance', date_naissance: 'Date de naissance',
    dateNaissanceChat: 'Date de naissance (chat)', puce: 'N° puce / tatouage', identification: 'N° identification',
    espece_autre: 'Espèce (autre)', signesParticuliers: 'Signes particuliers', superficie: 'Superficie (m²)',
    numeroBox: 'N° du BOX', numeroCage: 'N° de cage', numeroPasseport: 'N° carnet de santé',
    nomAttestation: 'Attestation au nom de',
    totalParticipation: 'Total participation (€)', tarifParticulier: 'Tarif particulier (€)',
    autresMotif: 'Autre motif', autresMontant: 'Autre montant (€)',
    montantDon: 'Montant du don (€)', montantDonLibre: 'Montant du don (€)', montantLettres: 'Montant en lettres',
    donBienfaiteur: 'Montant don bienfaiteur (€)', donSympatisant: 'Montant virement sympathisant (€)',
    cotisationAdherent: 'Cotisation adhérent (€)', montantAdhesion: 'Montant total adhésion (€)',
    montant_cb: 'Montant CB (€)', montant_espece: 'Montant espèces (€)', montant_virement: 'Montant virement (€)',
    montant_cheque: 'Montant chèque (€)',
    numeroPaiement: 'N° chèque', numeroCheque: 'N° chèque', numeroChequeRestitution: 'N° chèque restitué',
    montantConserve: 'Montant conservé (€)', montantRestitue: 'Montant restitué (€)',
    dateSignature: 'Date de signature', date_signature: 'Date de signature', dateAdoption: 'Date de cession',
    dateAdoptant: 'Date (famille)', dateReservation: 'Date de réservation',
    dateVaccin: 'Date vaccin', dateRappel: 'Date rappel vaccin', dateLimiteRappel: 'Date limite rappel',
    datePrimoVaccin: 'Date primo-vaccin', dateRdvVet: 'Date RDV vétérinaire',
    dateVermifuge: 'Date vermifuge', prochainVermifuge: 'Prochain vermifuge', produitVermifuge: 'Produit vermifuge',
    dateAntiPuces: 'Date antipuces', dateprochainAntiPuces: 'Prochain antipuces', produitAntiPuces: 'Produit antipuces',
    dateCertificatVeto: 'Date certificat vétérinaire',
    dateSterilisationCas1: 'Date stérilisation (cas 1)', dateSterilisationPrevue: 'Date stérilisation prévue',
    dateLimiteSterilisation: 'Date limite stérilisation',
    adresseAdoptant: 'Adresse (famille)', codePostalAdoptant: 'Code postal (famille)', villeAdoptant: 'Ville (famille)',
    nomAdoptant: 'Nom (famille)', prenomAdoptant: 'Prénom (famille)',
    adresseEmprunteur: 'Adresse emprunteur', codePostalEmprunteur: 'Code postal emprunteur',
    villeEmprunteur: 'Ville emprunteur', emailEmprunteur: 'Email emprunteur', telephoneEmprunteur: 'Téléphone emprunteur',
    nomEmprunteur: 'Nom emprunteur', prenomEmprunteur: 'Prénom emprunteur',
    materiel_autre_texte: 'Matériel (autre)', datePriseEnCharge: 'Date de prise en charge',
    dateRetour: 'Date de retour prévue', dateRetourEffectif: 'Date de retour effective', anomalies: 'Anomalies constatées',
    dateNaissancePersonne: 'Date de naissance (personne)',
    causeAbandon1: "Cause d'abandon", causeAbandon2: "Cause d'abandon (2)",
    problemeSante1: 'Problème de santé', problemeSante2: 'Problème de santé (2)',
    defauts1: 'Défauts', defauts2: 'Défauts (2)', qualites1: 'Qualités', qualites2: 'Qualités (2)',
    vaccins: 'Vaccins', nombreChats: 'Nombre de chats', nombreChatons: 'Nombre de chatons',
    nombreAutres: "Nombre d'autres animaux", preciserAutre: 'Préciser (autre)',
    date_debut: 'Date début accueil', date_fin: 'Date fin accueil',
    numeroRecuFiscal: 'N° reçu fiscal', dateEmission: "Date d'émission", descriptionNature: 'Nature du don',
    paysDonateur: 'Pays du donateur', recuFiscalSouhaite: 'Reçu fiscal souhaité',
    motifTraitement: 'Motif du traitement', motifAutre: 'Motif (autre)',
    nomSignataire: 'Nom signataire', prenomSignataire: 'Prénom signataire'
};

// Clés techniques à ne jamais afficher dans le résumé
var CHAMPS_EXCLUS_RESUME = [
    'onglet', 'htmlContent', 'signatureImage', 'action', 'filename',
    'photoReservation', 'donId', 'adoptionId', 'saisiPar', 'montantAdhesion'
];

function construireCorpsMail(data) {
    data = data || {};
    var now = formatDateHeureFR(new Date());
    var typeLibelle = LIBELLES_ONGLET[data.onglet] || data.onglet || 'Formulaire';

    var lignes = [
        'Bonjour,',
        '',
        'Un nouveau ' + typeLibelle + ' a été soumis le ' + now + '.',
        ''
    ];

    // "Saisi par" lu directement dans le <select> (le libellé lisible, pas
    // l'identifiant technique renvoyé par collectFormData()).
    var saisiParEl = document.getElementById('saisiPar');
    if (saisiParEl && saisiParEl.selectedIndex > 0) {
        lignes.push('Saisi par : ' + saisiParEl.options[saisiParEl.selectedIndex].text);
        lignes.push('');
    }

    lignes.push('─── Informations saisies ────────────────');

    Object.keys(data).forEach(function(k) {
        if (CHAMPS_EXCLUS_RESUME.indexOf(k) !== -1) return;
        if (k.charAt(0) === '_') return; // champs internes (ex. _adoptionId)
        var val = data[k];
        if (val === null || val === undefined || String(val).trim() === '') return;
        if (typeof val === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(val)) {
            val = formatDateFR(val);
        }
        var label = LIBELLES_CHAMPS[k] || k;
        lignes.push('  ' + label + ' : ' + val);
    });

    lignes = lignes.concat([
        '─────────────────────────────────────',
        '',
        'Le formulaire PDF complet est joint à ce mail.',
        '',
        '— Association L\'Arche de Mallo'
    ]);

    return lignes.join('\n');
}

function arrayBufferToBase64(bytesOrBuffer) {
    const bytes = bytesOrBuffer instanceof Uint8Array ? bytesOrBuffer : new Uint8Array(bytesOrBuffer);
    let binary = '';
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(binary);
}
