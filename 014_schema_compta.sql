-- ============================================================
-- SCHÉMA COMPTA — L'Arche de Mallo
-- ============================================================
-- Repris depuis compta-main/sheets.js (SHEETS_CONFIG + COLS_*), qui
-- fait foi pour la structure actuelle. Chaque table ci-dessous
-- correspond à une feuille Google Sheets ; les noms de colonnes ont
-- été traduits en snake_case mais gardent le même sens.
--
-- Simplifications volontaires par rapport aux sheets d'origine :
--  1. Caisse / Caisse2 → une seule table caisse_mouvements avec une
--     colonne "caisse" ('caisse1'|'caisse2'), au lieu de deux onglets.
--     Idem pour Caisse1_physique / Caisse2_physique.
--  2. Remises_cheques : les 10 blocs de détail répétés en colonnes
--     (Donateur1..10, Montant1..10, etc.) sont normalisés en une table
--     enfant remise_cheques_details (une ligne par chèque de la remise),
--     plus flexible et sans limite de 10 chèques par remise.
--  3. Import_Rapprochement / Import_historique : même structure de
--     colonnes dans les deux sheets (l'historique est juste l'archive
--     des lignes traitées). Une seule table import_rapprochement, avec
--     le statut ('en_attente' / 'rapprochee' / 'ignoree') qui fait office
--     de séparation — l'"archivage" devient une simple mise à jour du
--     statut au lieu d'un déplacement de ligne entre deux onglets.
--
-- Les tables sont créées sans les clés étrangères qui se référencent
-- mutuellement (banque <-> chèques <-> remises), puis les contraintes
-- sont ajoutées à la fin une fois que toutes les tables existent.

create extension if not exists pgcrypto;

-- ---- CONFIG (clé/valeur, remplace le sheet Config) ----
create table if not exists config_compta (
    cle     text primary key,
    valeur  jsonb not null,
    maj_le  timestamptz not null default now()
);

-- ---- JOURNAL D'AUDIT ----
create table if not exists journal_audit_compta (
    id           uuid primary key default gen_random_uuid(),
    horodatage   timestamptz not null default now(),
    user_email   text,
    user_name    text,
    action       text,        -- ex. AJOUT / MODIF / SUPPRESSION
    onglet       text,        -- table/écran d'origine, pour compat avec l'existant
    ligne_ref    text,        -- id de la ligne concernée
    detail       text,
    is_admin     boolean default false
);

-- ---- CAISSE (mouvements physiques, Caisse + Caisse2) ----
create table if not exists caisse_mouvements (
    id               uuid primary key default gen_random_uuid(),
    caisse           text not null check (caisse in ('caisse1', 'caisse2')),
    date_mouvement   date not null,
    libelle          text,
    debit            numeric(10,2) default 0,
    credit           numeric(10,2) default 0,
    solde            numeric(10,2),
    periode          text,       -- ex. "2026-03"
    type_mouvement   text,
    libelle_complementaire text,   -- "type_comp" dans les sheets : en fait un texte libre complémentaire, pas une classification comptable
    description      text,
    nom              text,
    reglement        text,
    nom_chat         text,
    numero_recu      text,
    numero_bordereau text,
    lien_facture     text,
    flag_statut      text not null default 'aucun' check (flag_statut in ('aucun','a_verifier','verifie')),  -- "flag_check" à 3 états dans les sheets, pas un simple oui/non
    flag_commentaire text,
    suivi_ref        text,       -- référence vers un formulaire Suivi (don, adhésion...)
    fournisseur      text,
    cree_le          timestamptz not null default now()
);
create index if not exists idx_caisse_mouvements_date on caisse_mouvements(date_mouvement);
create index if not exists idx_caisse_mouvements_periode on caisse_mouvements(periode);

-- ---- CHÈQUES ----
create table if not exists cheques (
    id              uuid primary key default gen_random_uuid(),
    numero_cheque   text,
    date_emission   date,
    beneficiaire    text,
    montant         numeric(10,2),
    type_mouvement  text,
    libelle_complementaire text,  -- idem
    description     text,
    periode         text,
    statut          text check (statut in ('en_attente', 'encaisse', 'annule')),
    date_encaissement date,
    ref_banque      uuid,       -- FK ajoutée plus bas -> banque_mouvements(id)
    verifie         boolean default false,
    fournisseur     text,
    nom_chat        text,
    cree_le         timestamptz not null default now()
);

-- ---- REMISES DE CHÈQUES ----
create table if not exists remises_cheques (
    id               uuid primary key default gen_random_uuid(),
    date_remise      date,
    numero_bordereau text,
    nb_cheques       integer default 0,
    montant_total    numeric(10,2) default 0,
    periode          text,
    statut           text not null default 'en_attente' check (statut in ('en_attente', 'encaissee')),
    date_encaissement date,
    ref_banque       uuid,      -- FK ajoutée plus bas -> banque_mouvements(id)
    verifie          boolean default false,
    cree_le          timestamptz not null default now()
);

-- Détail d'une remise : remplace les 10 blocs de colonnes répétées
-- (Donateur1..10, Montant1..10, Chèque1..10, ...) du sheet d'origine.
create table if not exists remise_cheques_details (
    id                uuid primary key default gen_random_uuid(),
    remise_id         uuid not null references remises_cheques(id) on delete cascade,
    numero_ordre      integer not null,   -- position dans la remise (1, 2, 3...)
    donateur          text,
    montant           numeric(10,2),
    cheque_ref        text,   -- référence libre du chèque (pas forcément lié à la table cheques)
    type_mouvement    text,
    description       text,
    libelle_complementaire text,
    nom_chat          text,
    numero_recu       text,
    suivi_ref         text,
    unique (remise_id, numero_ordre)
);

-- ---- BANQUE (mouvements bancaires) ----
create table if not exists banque_mouvements (
    id                   uuid primary key default gen_random_uuid(),
    date_mouvement       date not null,
    libelle              text,
    debit                numeric(10,2) default 0,
    credit               numeric(10,2) default 0,
    solde                numeric(10,2),
    periode              text,
    type_mouvement       text,
    description          text,
    nom                  text,
    libelle_complementaire       text,  -- idem
    numero_facture       text,
    nom_chat             text,
    numero_don_fiscal    text,  -- rapprochable de dons.numero_recu_fiscal (Suivi), même base Supabase
    flag_verifie         boolean not null default false,  -- annotation "à vérifier" simple (TRUE/FALSE dans les sheets) — distinct du verrouillage, qui est porté par "statut" ci-dessous pour banque (contrairement à caisse, où flag_check fait les deux)
    ref_remise           uuid references remises_cheques(id),
    numero_remise_espece text,
    ref_cheque           uuid references cheques(id),
    lien_facture         text,
    statut               text default 'aucun' check (statut in ('aucun', 'verifie')),  -- 'verifie' = ligne verrouillée
    flag_commentaire     text,
    suivi_ref            text,
    fournisseur          text,
    mode_reglement       text,
    cree_le              timestamptz not null default now()
);
create index if not exists idx_banque_mouvements_date on banque_mouvements(date_mouvement);
create index if not exists idx_banque_mouvements_periode on banque_mouvements(periode);

-- Chèques et remises pointent vers le mouvement bancaire où ils ont été
-- encaissés (ajouté après coup car banque_mouvements n'existait pas
-- encore au moment de créer ces deux tables). Protégé par un test
-- d'existence : sans ça, relancer ce script après une première
-- installation échoue avec "constraint ... already exists".
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'cheques_ref_banque_fkey') then
        alter table cheques add constraint cheques_ref_banque_fkey foreign key (ref_banque) references banque_mouvements(id);
    end if;
end $$;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'remises_cheques_ref_banque_fkey') then
        alter table remises_cheques add constraint remises_cheques_ref_banque_fkey foreign key (ref_banque) references banque_mouvements(id);
    end if;
end $$;

-- ---- FACTURES ----
create table if not exists factures (
    id             uuid primary key default gen_random_uuid(),
    numero_facture text,
    fournisseur    text,
    date_facture   date,
    montant_ttc    numeric(10,2),
    categorie      text,
    description    text,
    date_reglement date,
    mode_reglement text,
    lien_pdf       text,
    commentaire    text,
    periode        text,
    statut         text,
    nom_chat       text,
    cree_le        timestamptz not null default now()
);
create index if not exists idx_factures_periode on factures(periode);

-- ---- COMPTAGES CAISSE PHYSIQUE (billets/pièces, Caisse1 + Caisse2) ----
create table if not exists caisse_physique_comptages (
    id           uuid primary key default gen_random_uuid(),
    caisse       text not null check (caisse in ('caisse1', 'caisse2')),
    date_comptage date,
    periode      text,  -- absente à l'origine : le filtre par période de la page ne pouvait jamais rien trouver (repéré en revue)
    mois         text,
    b500 integer default 0, b200 integer default 0, b100 integer default 0,
    b50  integer default 0, b20  integer default 0, b10  integer default 0,
    b5   integer default 0,
    p200 integer default 0, p100 integer default 0, p050 integer default 0,
    p020 integer default 0, p010 integer default 0, p005 integer default 0,
    p002 integer default 0, p001 integer default 0,
    total       numeric(10,2),
    commentaire text
);

-- ---- IMPORT / RAPPROCHEMENT BANCAIRE ----
-- Fusionne Import_Rapprochement (en cours) et Import_historique (traité) :
-- le statut distingue les deux au lieu de deux onglets séparés.
create table if not exists import_rapprochement (
    id                 uuid primary key default gen_random_uuid(),
    onglet             text,      -- destination d'origine (Caisse/Banque/...)
    statut             text not null default 'en_attente' check (statut in ('en_attente', 'rapprochee', 'ignoree')),
    destination        text,
    date_mouvement     date,
    periode            text,
    libelle            text,
    montant            numeric(10,2),
    type_mouvement     text,
    mode_reglement     text,
    nom_chat           text,
    numero_cheque      text,
    numero_recu        text,
    description        text,
    date_import        date,
    date_rapprochement date,
    motif_ignore       text,
    cree_le            timestamptz not null default now()
);
create index if not exists idx_import_rapprochement_statut on import_rapprochement(statut);

-- ============================================================
-- LIENS AVEC LES TABLES DÉJÀ EN PLACE
-- ============================================================

-- Reportée depuis 001_schema_arche_de_mallo.sql : le soin vétérinaire
-- (Suivi) peut être rattaché à la facture (Compta) qui l'a réglé.
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'fk_animaux_soins_veto_facture_id') then
        alter table animaux_soins_veto add constraint fk_animaux_soins_veto_facture_id foreign key (facture_id) references factures(id) on delete set null;
    end if;
end $$;

-- Rattachement optionnel au fournisseur déjà géré via
-- ajouter_fournisseur()/definir_actif_fournisseur() (006_configuration.sql).
-- Nullable et en plus du champ texte libre "fournisseur" existant (utile
-- pour importer les sheets tel quel, puis rattacher au fur et à mesure).
alter table factures add column if not exists fournisseur_id uuid references fournisseurs(id);
alter table cheques add column if not exists fournisseur_id uuid references fournisseurs(id);
alter table banque_mouvements add column if not exists fournisseur_id uuid references fournisseurs(id);
alter table caisse_mouvements add column if not exists fournisseur_id uuid references fournisseurs(id);
create index if not exists idx_factures_fournisseur_id on factures(fournisseur_id);
create index if not exists idx_cheques_fournisseur_id on cheques(fournisseur_id);
create index if not exists idx_banque_mouvements_fournisseur_id on banque_mouvements(fournisseur_id);
create index if not exists idx_caisse_mouvements_fournisseur_id on caisse_mouvements(fournisseur_id);

-- ============================================================
-- VUE : solde cumulé par compte ET par période (banque, caisse1,
-- caisse2), calculé à la volée — jamais stocké. Intègre le solde
-- initial de la table "soldes" : sans ça, la vue ne donnait qu'un solde
-- relatif à zéro, pas le vrai solde comptable (signalé et corrigé).
-- Remplace v_mouvements_solde (ébauche retirée).
-- ============================================================
create or replace view v_solde_cumule as
select
    'banque'::text as compte, b.id, b.date_mouvement, b.periode, b.credit, b.debit,
    coalesce(s.montant, 0) + sum(coalesce(b.credit,0) - coalesce(b.debit,0)) over (
        partition by b.periode
        order by b.date_mouvement, b.id rows between unbounded preceding and current row
    ) as solde_cumule
from banque_mouvements b
left join soldes s on s.compte = 'banque' and s.periode = b.periode and s.type_solde = 'initial'
union all
select
    c.caisse as compte, c.id, c.date_mouvement, c.periode, c.credit, c.debit,
    coalesce(s.montant, 0) + sum(coalesce(c.credit,0) - coalesce(c.debit,0)) over (
        partition by c.caisse, c.periode
        order by c.date_mouvement, c.id rows between unbounded preceding and current row
    ) as solde_cumule
from caisse_mouvements c
left join soldes s on s.compte = c.caisse and s.periode = c.periode and s.type_solde = 'initial';
