-- ============================================================
-- L'Arche de Mallo — Schéma Supabase (Suivi + Compta regroupés)
-- Généré à partir du schéma validé (voir Proposition_tables_
-- Arche_de_Mallo.xlsx). Idempotent : peut être rejoué sans erreur
-- sur une base vide.
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- 1. TABLES — colonnes, clés primaires, contraintes UNIQUE/CHECK
--    (les clés étrangères sont ajoutées plus bas, en bloc, pour
--    éviter les problèmes d'ordre entre tables qui se référencent
--    mutuellement, ex: mouvements <-> cheques_emis)
-- ============================================================

create table if not exists utilisateurs (
    id uuid primary key default gen_random_uuid(),
    nom text not null,
    email text not null unique,
    is_admin boolean not null default false,
    actif boolean not null default true,
    created_at timestamptz not null default now()
);

create table if not exists personnes (
    id uuid primary key default gen_random_uuid(),
    type_personne text not null default 'particulier',
    civilite text,
    nom text,
    prenom text,
    raison_sociale text,
    representant text,
    adresse text,
    code_postal text,
    ville text,
    pays text default 'France',
    email text,
    telephone text,
    date_naissance date,
    siren text,
    forme_juridique text,
    created_at timestamptz not null default now(),
    constraint personnes_type_check check (type_personne in ('particulier','entreprise'))
);

create table if not exists fournisseurs (
    id uuid primary key default gen_random_uuid(),
    nom text not null unique,
    actif boolean not null default true
);

create table if not exists animaux (
    id uuid primary key default gen_random_uuid(),
    nom_usuel text not null,
    nom_adoption text,
    noms_precedents text,
    espece text not null default 'chat',
    race text,
    couleur text,
    sexe text,
    date_naissance date,
    date_naissance_estimee boolean not null default false,
    puce text,
    numero_carnet_sante text,
    nom_maman text,
    mere_id uuid,
    signes_particuliers text,
    date_arrivee date,
    origine_arrivee text,
    personne_origine_id uuid,
    statut_actuel text,
    date_deces date,
    created_at timestamptz not null default now(),
    constraint animaux_origine_check check (origine_arrivee is null or origine_arrivee in ('depot','abandon','saisie','ne_a_association','transfert_autre_association'))
);

create table if not exists animaux_sterilisation (
    id uuid primary key default gen_random_uuid(),
    animal_id uuid not null unique,
    sterilise boolean not null default false,
    date_sterilisation date,
    fichier_sterilisation_url text,
    saisi_par uuid,
    derniere_maj timestamptz not null default now()
);

create table if not exists animaux_statuts_historique (
    id uuid primary key default gen_random_uuid(),
    animal_id uuid not null,
    statut text not null,
    date_debut date not null,
    date_fin date,
    motif text,
    saisi_par uuid,
    constraint animaux_statut_check check (statut in ('arrive','en_observation','au_veto','adoptable','non_adoptable','reserve','adopte','famille_accueil','decede','relache','retour','transfere'))
);

create table if not exists animaux_soins_veto (
    id uuid primary key default gen_random_uuid(),
    animal_id uuid not null,
    date_soin date not null,
    type_soin text,
    veterinaire text,
    description text,
    prochain_rappel date,
    facture_id uuid
);

create table if not exists animaux_photos (
    id uuid primary key default gen_random_uuid(),
    animal_id uuid not null,
    url text not null,
    est_photo_principale boolean not null default false
);

create table if not exists icad_suivi (
    id uuid primary key default gen_random_uuid(),
    animal_id uuid not null unique,
    date_transfert date,
    commentaire text,
    fichier_icad_url text,
    derniere_maj timestamptz not null default now()
);

create table if not exists adhesions (
    id uuid primary key default gen_random_uuid(),
    personne_id uuid not null,
    date_adhesion date,
    type_adhesion text,
    cotisation_adherent numeric(10,2),
    don_bienfaiteur numeric(10,2),
    don_sympathisant numeric(10,2),
    montant_total numeric(10,2),
    montant_virement numeric(10,2),
    montant_espece numeric(10,2),
    saisi_par uuid,
    date_fait date,
    adoption_id uuid
);

create table if not exists adhesions_cheques (
    id uuid primary key default gen_random_uuid(),
    adhesion_id uuid not null,
    numero_cheque text,
    montant numeric(10,2)
);

create table if not exists dons (
    id uuid primary key default gen_random_uuid(),
    personne_id uuid,
    don_anonyme boolean not null default false,
    date_signature date,
    montant numeric(10,2),
    montant_virement numeric(10,2),
    montant_espece numeric(10,2),
    montant_cb numeric(10,2),
    description_nature text,
    numero_recu_fiscal text unique,
    saisi_par uuid,
    adoption_id uuid
);

create table if not exists dons_cheques (
    id uuid primary key default gen_random_uuid(),
    don_id uuid not null,
    numero_cheque text,
    montant numeric(10,2)
);

create table if not exists adoptions (
    id uuid primary key default gen_random_uuid(),
    animal_id uuid not null,
    personne_id uuid not null,
    date_adoption date,
    nom_attestation text,
    tarif_particulier numeric(10,2),
    total_participation numeric(10,2),
    montant_virement numeric(10,2),
    montant_espece numeric(10,2),
    montant_cb numeric(10,2),
    date_fait date,
    saisi_par uuid
);

create table if not exists adoptions_cheques (
    id uuid primary key default gen_random_uuid(),
    adoption_id uuid not null,
    numero_cheque text,
    montant numeric(10,2)
);

create table if not exists reservations (
    id uuid primary key default gen_random_uuid(),
    type_reservation text not null,
    animal_id uuid,
    personne_id uuid not null,
    numero_box text,
    date_reservation date,
    montant numeric(10,2),
    montant_virement numeric(10,2),
    montant_espece numeric(10,2),
    montant_cb numeric(10,2),
    signes_particuliers text,
    superficie numeric(6,2),
    saisi_par uuid,
    constraint reservations_type_check check (type_reservation in ('chat','chaton','autre_animal'))
);

create table if not exists reservations_cheques (
    id uuid primary key default gen_random_uuid(),
    reservation_id uuid not null,
    numero_cheque text,
    montant numeric(10,2)
);

create table if not exists depots_chat (
    id uuid primary key default gen_random_uuid(),
    personne_id uuid,
    date_depot date,
    commune text,
    preciser_autre text,
    nombre_chats_historique integer,
    nombre_chatons_historique integer,
    nombre_autres_historique integer,
    saisi_par uuid
);

create table if not exists depot_chat_animaux (
    id uuid primary key default gen_random_uuid(),
    depot_id uuid not null,
    animal_id uuid not null
);

create table if not exists abandons (
    id uuid primary key default gen_random_uuid(),
    animal_id uuid,
    personne_id uuid,
    cause_abandon text,
    problemes_sante text,
    qualites text,
    defauts text,
    vaccins text,
    date_fait date,
    saisi_par uuid
);

create table if not exists familles_accueil (
    id uuid primary key default gen_random_uuid(),
    type_accueil text not null,
    personne_id uuid,
    animal_id uuid,
    date_debut date,
    date_fin date,
    date_fait date,
    saisi_par uuid,
    constraint familles_accueil_type_check check (type_accueil in ('provisoire','chat_libre','adoption'))
);

create table if not exists attestations (
    id uuid primary key default gen_random_uuid(),
    type_attestation text not null,
    animal_id uuid,
    personne_id uuid,
    motif text,
    date_rdv_veto date,
    date_naissance_animal date,
    date_primo_vaccin date,
    date_limite_rappel date,
    date_fait date,
    saisi_par uuid,
    constraint attestations_type_check check (type_attestation in ('cbs_absent','decharge_vaccin'))
);

create table if not exists materiel_mouvements (
    id uuid primary key default gen_random_uuid(),
    type_mouvement text not null,
    personne_id uuid,
    materiel text,
    date_mouvement date,
    saisi_par uuid,
    constraint materiel_type_check check (type_mouvement in ('pret','retour'))
);

create table if not exists certificats_engagement (
    id uuid primary key default gen_random_uuid(),
    personne_id uuid,
    date_fait date,
    saisi_par uuid
);

create table if not exists soumission_fichiers (
    id uuid primary key default gen_random_uuid(),
    table_source text not null,
    enregistrement_id uuid not null,
    type_fichier text,
    url text not null
);

create table if not exists types_mouvement (
    id uuid primary key default gen_random_uuid(),
    valeur text not null unique,
    ordre integer
);

create table if not exists descriptions_mouvement (
    id uuid primary key default gen_random_uuid(),
    type_mouvement_id uuid not null,
    valeur text not null,
    ordre integer,
    unique (type_mouvement_id, valeur)
);

-- NOTE : mouvements / mouvement_suivi_liens / mouvement_facture_liens /
-- cheques_emis / remises_cheques / remise_cheque_lignes / factures /
-- caisse_physique / import_rapprochement / import_historique / notes /
-- journal / presence faisaient partie d'une première ébauche du schéma
-- Compta, écrite avant d'avoir accès au vrai code compta-main. Elles ont
-- été retirées au profit du schéma fidèle aux sheets réels dans
-- 014_schema_compta.sql (caisse_mouvements, banque_mouvements, cheques,
-- remises_cheques, remise_cheques_details, factures,
-- caisse_physique_comptages, import_rapprochement) et
-- 015_auth_rls_compta.sql (journal_audit_compta). "soldes",
-- "types_mouvement", "descriptions_mouvement", "config_listes" et
-- "parametres" restent : déjà utilisées par 006_configuration.sql et
-- toujours valables avec le nouveau schéma.

create table if not exists soldes (
    id uuid primary key default gen_random_uuid(),
    periode text not null,
    compte text not null,
    type_solde text not null,
    montant numeric(10,2),
    constraint soldes_type_check check (type_solde in ('initial','final')),
    unique (periode, compte, type_solde)
);

create table if not exists config_listes (
    id uuid primary key default gen_random_uuid(),
    categorie text not null,
    valeur text not null,
    ordre integer,
    unique (categorie, valeur)
);

create table if not exists compteurs_recus_fiscaux (
    id uuid primary key default gen_random_uuid(),
    type text not null,
    annee integer not null,
    dernier_numero integer not null default 0,
    constraint compteurs_type_check check (type in ('particulier','entreprise')),
    unique (type, annee)
);

create table if not exists parametres (
    cle text primary key,
    valeur text
);

-- ============================================================
-- 2. CLÉS ÉTRANGÈRES
-- ============================================================

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_animaux_mere_id') then
        alter table animaux add constraint fk_animaux_mere_id foreign key (mere_id) references animaux(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_animaux_personne_origine_id') then
        alter table animaux add constraint fk_animaux_personne_origine_id foreign key (personne_origine_id) references personnes(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_animaux_sterilisation_animal_id') then
        alter table animaux_sterilisation add constraint fk_animaux_sterilisation_animal_id foreign key (animal_id) references animaux(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_animaux_sterilisation_saisi_par') then
        alter table animaux_sterilisation add constraint fk_animaux_sterilisation_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_animaux_statuts_historique_animal_id') then
        alter table animaux_statuts_historique add constraint fk_animaux_statuts_historique_animal_id foreign key (animal_id) references animaux(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_animaux_statuts_historique_saisi_par') then
        alter table animaux_statuts_historique add constraint fk_animaux_statuts_historique_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_animaux_soins_veto_animal_id') then
        alter table animaux_soins_veto add constraint fk_animaux_soins_veto_animal_id foreign key (animal_id) references animaux(id) on delete cascade;
    end if;
end $$;
-- fk_animaux_soins_veto_facture_id : reportée en fin de
-- 014_schema_compta.sql (la table factures y est créée).
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_animaux_photos_animal_id') then
        alter table animaux_photos add constraint fk_animaux_photos_animal_id foreign key (animal_id) references animaux(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_icad_suivi_animal_id') then
        alter table icad_suivi add constraint fk_icad_suivi_animal_id foreign key (animal_id) references animaux(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_adhesions_personne_id') then
        alter table adhesions add constraint fk_adhesions_personne_id foreign key (personne_id) references personnes(id) on delete restrict;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_adhesions_saisi_par') then
        alter table adhesions add constraint fk_adhesions_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_adhesions_adoption_id') then
        alter table adhesions add constraint fk_adhesions_adoption_id foreign key (adoption_id) references adoptions(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_adhesions_cheques_adhesion_id') then
        alter table adhesions_cheques add constraint fk_adhesions_cheques_adhesion_id foreign key (adhesion_id) references adhesions(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_dons_personne_id') then
        alter table dons add constraint fk_dons_personne_id foreign key (personne_id) references personnes(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_dons_saisi_par') then
        alter table dons add constraint fk_dons_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_dons_adoption_id') then
        alter table dons add constraint fk_dons_adoption_id foreign key (adoption_id) references adoptions(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_dons_cheques_don_id') then
        alter table dons_cheques add constraint fk_dons_cheques_don_id foreign key (don_id) references dons(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_adoptions_animal_id') then
        alter table adoptions add constraint fk_adoptions_animal_id foreign key (animal_id) references animaux(id) on delete restrict;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_adoptions_personne_id') then
        alter table adoptions add constraint fk_adoptions_personne_id foreign key (personne_id) references personnes(id) on delete restrict;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_adoptions_saisi_par') then
        alter table adoptions add constraint fk_adoptions_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_adoptions_cheques_adoption_id') then
        alter table adoptions_cheques add constraint fk_adoptions_cheques_adoption_id foreign key (adoption_id) references adoptions(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_reservations_animal_id') then
        alter table reservations add constraint fk_reservations_animal_id foreign key (animal_id) references animaux(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_reservations_personne_id') then
        alter table reservations add constraint fk_reservations_personne_id foreign key (personne_id) references personnes(id) on delete restrict;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_reservations_saisi_par') then
        alter table reservations add constraint fk_reservations_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_reservations_cheques_reservation_id') then
        alter table reservations_cheques add constraint fk_reservations_cheques_reservation_id foreign key (reservation_id) references reservations(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_depots_chat_personne_id') then
        alter table depots_chat add constraint fk_depots_chat_personne_id foreign key (personne_id) references personnes(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_depots_chat_saisi_par') then
        alter table depots_chat add constraint fk_depots_chat_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_depot_chat_animaux_depot_id') then
        alter table depot_chat_animaux add constraint fk_depot_chat_animaux_depot_id foreign key (depot_id) references depots_chat(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_depot_chat_animaux_animal_id') then
        alter table depot_chat_animaux add constraint fk_depot_chat_animaux_animal_id foreign key (animal_id) references animaux(id) on delete cascade;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_abandons_animal_id') then
        alter table abandons add constraint fk_abandons_animal_id foreign key (animal_id) references animaux(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_abandons_personne_id') then
        alter table abandons add constraint fk_abandons_personne_id foreign key (personne_id) references personnes(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_abandons_saisi_par') then
        alter table abandons add constraint fk_abandons_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_familles_accueil_personne_id') then
        alter table familles_accueil add constraint fk_familles_accueil_personne_id foreign key (personne_id) references personnes(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_familles_accueil_animal_id') then
        alter table familles_accueil add constraint fk_familles_accueil_animal_id foreign key (animal_id) references animaux(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_familles_accueil_saisi_par') then
        alter table familles_accueil add constraint fk_familles_accueil_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_attestations_animal_id') then
        alter table attestations add constraint fk_attestations_animal_id foreign key (animal_id) references animaux(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_attestations_personne_id') then
        alter table attestations add constraint fk_attestations_personne_id foreign key (personne_id) references personnes(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_attestations_saisi_par') then
        alter table attestations add constraint fk_attestations_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_materiel_mouvements_personne_id') then
        alter table materiel_mouvements add constraint fk_materiel_mouvements_personne_id foreign key (personne_id) references personnes(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_materiel_mouvements_saisi_par') then
        alter table materiel_mouvements add constraint fk_materiel_mouvements_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_certificats_engagement_personne_id') then
        alter table certificats_engagement add constraint fk_certificats_engagement_personne_id foreign key (personne_id) references personnes(id) on delete set null;
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_certificats_engagement_saisi_par') then
        alter table certificats_engagement add constraint fk_certificats_engagement_saisi_par foreign key (saisi_par) references utilisateurs(id) on delete set null;
    end if;
end $$;
-- Les FK vers/depuis mouvements, mouvement_suivi_liens,
-- mouvement_facture_liens, cheques_emis, remises_cheques,
-- remise_cheque_lignes, factures, notes, journal (ébauche Compta
-- retirée, voir note plus haut) sont retirées avec ces tables.
-- fk_animaux_soins_veto_facture_id (vers factures) est reportée à la
-- fin de 014_schema_compta.sql, une fois la vraie table factures créée.
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_descriptions_mouvement_type_mouvement_id') then
        alter table descriptions_mouvement add constraint fk_descriptions_mouvement_type_mouvement_id foreign key (type_mouvement_id) references types_mouvement(id) on delete cascade;
    end if;
end $$;

-- ============================================================
-- 3. INDEX
--    Postgres n'indexe pas automatiquement les colonnes de clé
--    étrangère : on les indexe ici (utile pour les jointures et
--    les suppressions en cascade). + quelques colonnes filtrées
--    fréquemment (date, statut, periode).
-- ============================================================

create index if not exists idx_animaux_mere_id on animaux(mere_id);
create index if not exists idx_animaux_personne_origine_id on animaux(personne_origine_id);
create index if not exists idx_animaux_sterilisation_animal_id on animaux_sterilisation(animal_id);
create index if not exists idx_animaux_sterilisation_saisi_par on animaux_sterilisation(saisi_par);
create index if not exists idx_animaux_statuts_historique_animal_id on animaux_statuts_historique(animal_id);
create index if not exists idx_animaux_statuts_historique_saisi_par on animaux_statuts_historique(saisi_par);
create index if not exists idx_animaux_soins_veto_animal_id on animaux_soins_veto(animal_id);
create index if not exists idx_animaux_soins_veto_facture_id on animaux_soins_veto(facture_id);
create index if not exists idx_animaux_photos_animal_id on animaux_photos(animal_id);
create index if not exists idx_icad_suivi_animal_id on icad_suivi(animal_id);
create index if not exists idx_adhesions_personne_id on adhesions(personne_id);
create index if not exists idx_adhesions_saisi_par on adhesions(saisi_par);
create index if not exists idx_adhesions_adoption_id on adhesions(adoption_id);
create index if not exists idx_adhesions_cheques_adhesion_id on adhesions_cheques(adhesion_id);
create index if not exists idx_dons_personne_id on dons(personne_id);
create index if not exists idx_dons_saisi_par on dons(saisi_par);
create index if not exists idx_dons_adoption_id on dons(adoption_id);
create index if not exists idx_dons_cheques_don_id on dons_cheques(don_id);
create index if not exists idx_adoptions_animal_id on adoptions(animal_id);
create index if not exists idx_adoptions_personne_id on adoptions(personne_id);
create index if not exists idx_adoptions_saisi_par on adoptions(saisi_par);
create index if not exists idx_adoptions_cheques_adoption_id on adoptions_cheques(adoption_id);
create index if not exists idx_reservations_animal_id on reservations(animal_id);
create index if not exists idx_reservations_personne_id on reservations(personne_id);
create index if not exists idx_reservations_saisi_par on reservations(saisi_par);
create index if not exists idx_reservations_cheques_reservation_id on reservations_cheques(reservation_id);
create index if not exists idx_depots_chat_personne_id on depots_chat(personne_id);
create index if not exists idx_depots_chat_saisi_par on depots_chat(saisi_par);
create index if not exists idx_depot_chat_animaux_depot_id on depot_chat_animaux(depot_id);
create index if not exists idx_depot_chat_animaux_animal_id on depot_chat_animaux(animal_id);
create index if not exists idx_abandons_animal_id on abandons(animal_id);
create index if not exists idx_abandons_personne_id on abandons(personne_id);
create index if not exists idx_abandons_saisi_par on abandons(saisi_par);
create index if not exists idx_familles_accueil_personne_id on familles_accueil(personne_id);
create index if not exists idx_familles_accueil_animal_id on familles_accueil(animal_id);
create index if not exists idx_familles_accueil_saisi_par on familles_accueil(saisi_par);
create index if not exists idx_attestations_animal_id on attestations(animal_id);
create index if not exists idx_attestations_personne_id on attestations(personne_id);
create index if not exists idx_attestations_saisi_par on attestations(saisi_par);
create index if not exists idx_materiel_mouvements_personne_id on materiel_mouvements(personne_id);
create index if not exists idx_materiel_mouvements_saisi_par on materiel_mouvements(saisi_par);
create index if not exists idx_certificats_engagement_personne_id on certificats_engagement(personne_id);
create index if not exists idx_certificats_engagement_saisi_par on certificats_engagement(saisi_par);
create index if not exists idx_descriptions_mouvement_type_mouvement_id on descriptions_mouvement(type_mouvement_id);
create index if not exists idx_animaux_statut_actuel on animaux(statut_actuel);
create index if not exists idx_animaux_statuts_historique_statut on animaux_statuts_historique(statut);

-- Les index et la vue v_mouvements_solde qui portaient sur l'ébauche
-- Compta retirée sont recréés (sur les vraies tables) dans
-- 014_schema_compta.sql.

-- Éléments Suivi qui n'ont encore aucune ligne de rapprochement
-- bancaire (remplace l'écran 'Import Suivi' actuel).
-- NB : mouvement_suivi_liens (table unique de l'ébauche) a été
-- remplacée par caisse_mouvement_suivi_liens / banque_mouvement_suivi_liens
-- (voir 017_liens_mouvement_suivi.sql) — un don/une adhésion/etc. peut
-- être rapproché via l'une OU l'autre, d'où le double NOT EXISTS.
create or replace view v_dons_non_rapproches as
select d.*
from dons d
where not exists (select 1 from caisse_mouvement_suivi_liens l where l.don_id = d.id)
  and not exists (select 1 from banque_mouvement_suivi_liens l where l.don_id = d.id);

create or replace view v_adhesions_non_rapprochees as
select a.*
from adhesions a
where not exists (select 1 from caisse_mouvement_suivi_liens l where l.adhesion_id = a.id)
  and not exists (select 1 from banque_mouvement_suivi_liens l where l.adhesion_id = a.id);

create or replace view v_adoptions_non_rapprochees as
select a.*
from adoptions a
where not exists (select 1 from caisse_mouvement_suivi_liens l where l.adoption_id = a.id)
  and not exists (select 1 from banque_mouvement_suivi_liens l where l.adoption_id = a.id);

create or replace view v_reservations_non_rapprochees as
select r.*
from reservations r
where not exists (select 1 from caisse_mouvement_suivi_liens l where l.reservation_id = r.id)
  and not exists (select 1 from banque_mouvement_suivi_liens l where l.reservation_id = r.id);
