# Convention de nommage des formulaires — L'Arche de Mallo

Un seul nom canonique en français par formulaire ; tout le reste s'en déduit
mécaniquement, pour éviter les dérives observées dans le projet actuel
(ex : `Contrat_reservation_chaton.html` dont l'identifiant interne perd le
préfixe `Contrat_` que gardent ses formulaires jumeaux chat/autre-animal ;
plusieurs `<title>` restés au nom technique brut).

## Règle

- **Fichier** : minuscules, sans accents, underscores, **singulier**
  (`adhesion.html`, `don.html` — même si la table SQL correspondante reste
  au pluriel : `adhesions`, `dons`)
- **Titre visible (`<title>`)** : `{Nom canonique} — L'Arche de Mallo`,
  même suffixe pour tous les formulaires
- **Identifiant interne** (`data-form-id`) : identique au nom de fichier,
  sans l'extension `.html`

## Table de correspondance (18 formulaires Suivi)

| Nom canonique | Ancien fichier | Nouveau fichier | Identifiant interne |
|---|---|---|---|
| Adhésion | Bulletin_adhesion.html | adhesion.html | adhesion |
| Don | Dons.html | don.html | don |
| Adoption | Contrat_adoption.html | adoption.html | adoption |
| Réservation (chat / chaton / autre animal) | Contrat_reservation_chat.html + Contrat_reservation_chaton.html + Contrat_reservation_autre_animal.html | reservation.html | reservation |
| Dépôt de chat | Formulaire_depot_chat.html | depot_chat.html | depot_chat |
| Abandon | Formulaire_abandon.html | abandon.html | abandon |
| Famille d'accueil (provisoire / chat libre / en vue d'adoption) | Formulaire_famille_accueil_provisoire.html + Formulaire_famille_accueil_definitive_chat_libre.html + Contrat_famille_accueil_adoption_definitive.html | famille_accueil.html | famille_accueil |
| Certificat d'engagement et de connaissance | Certificat_engagement_et_de_connaissance.html | certificat_engagement.html | certificat_engagement |
| Attestation CBS absent | Formulaire_CBS_absent.html | attestation_cbs_absent.html | attestation_cbs_absent |
| Décharge 2ème vaccin | Formulaire_decharge_vaccin.html | decharge_vaccin.html | decharge_vaccin |
| Prêt de matériel | Formulaire_pret_materiel.html | pret_materiel.html | pret_materiel |
| Retour de matériel | Formulaire_retour_materiel.html | retour_materiel.html | retour_materiel |
| Reçu fiscal particulier | Recu_fiscal_particulier.html | recu_fiscal_particulier.html | recu_fiscal_particulier |
| Reçu fiscal entreprise | Recu_fiscal_entreprise.html | recu_fiscal_entreprise.html | recu_fiscal_entreprise |

## Statut

- Les 14 formulaires Suivi sont construits : adhesion, don, adoption,
  reservation, depot_chat, abandon, famille_accueil, certificat_engagement,
  attestation_cbs_absent, decharge_vaccin, pret_materiel, retour_materiel,
  recu_fiscal_particulier, recu_fiscal_entreprise. Aucun n'est encore testé
  en conditions réelles (Supabase pas encore déployé).
- Décidé : les 3 formulaires Réservation (chat/chaton/autre animal) sont fusionnés en un seul fichier avec un sélecteur de type en tête, plutôt que 3 fichiers séparés — cohérent avec la table `reservations` unique (colonne `type_reservation`).
- `recu_fiscal_particulier.html` / `recu_fiscal_entreprise.html` : le numéro
  d'ordre (Cerfa) est désormais généré à la sauvegarde plutôt qu'à
  l'ouverture (voir 013_recu_fiscal.sql) — pour éviter de gâcher des
  numéros sur des formulaires ouverts puis abandonnés. `don.html` transmet
  maintenant le `donId` du don créé à ces deux formulaires, pour qu'ils
  puissent y rattacher le numéro généré.
- Deux fichiers partagés (`formulaires-arche-mallo.js`/`.css`) et
  `config.js` étaient référencés par tous les formulaires mais absents du
  premier export Fusion.zip — récupérés depuis le dépôt Suivi-main
  d'origine et ajoutés au dossier. Sans eux, aucun formulaire ne pouvait
  fonctionner.
- Cette convention ne concerne que les formulaires Suivi. Les pages Compta
  (banque.html, caisse.html, factures.html...) sont des outils/tableaux de
  bord, pas des formulaires de saisie unitaire.

## Compta — schéma construit, pages HTML pas encore commencées

- `014_schema_compta.sql` + `015_auth_rls_compta.sql` : schéma complet
  repris du vrai `compta-main/sheets.js` (8 feuilles → 10 tables), avec
  authentification Supabase (2 comptes : admin `compta@archedemallo.fr`,
  lecteur `jonathan@archedemallo.fr`) et RLS — contrairement à Suivi,
  Compta n'est pas en accès public.
- Une première ébauche du schéma Compta (table `mouvements` unifiée)
  avait été écrite dans `001_schema_arche_de_mallo.sql` avant d'avoir
  accès à `compta-main`. Elle a été retirée au profit du schéma actuel
  (tables séparées `caisse_mouvements`/`banque_mouvements`, fidèles aux
  vraies colonnes des sheets). `soldes`, `types_mouvement`,
  `descriptions_mouvement`, `config_listes`, `parametres` restent
  utilisées telles quelles par `configuration.html`/`006_configuration.sql`.
- Perdu dans le nettoyage, à reconstruire si utile : les tables
  `mouvement_suivi_liens` / `mouvement_facture_liens` de l'ébauche
  reliaient proprement un mouvement financier à son formulaire Suivi
  d'origine (adhésion/don/adoption/réservation) ou à une facture, via de
  vraies clés étrangères. Le nouveau schéma ne garde que des champs texte
  libres (`suivi_ref`, `numero_facture`...) pour rester fidèle aux sheets
  — moins robuste pour les rapprochements automatiques.
- **Pas encore fait** : les 20 pages HTML de Compta (banque, caisse,
  factures, chèques, remises, import/rapprochement, synthèse, analyse...)
  ne sont pas migrées. C'est un chantier à part entière, largement plus
  gros que les 14 formulaires Suivi.
