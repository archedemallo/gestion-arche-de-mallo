-- ============================================================
-- 066_ecritures_diverses.sql
-- ============================================================
-- Écritures diverses (OD) : corrections de présentation des comptes,
-- SANS jamais toucher aux lignes réelles de Banque / Caisse / Chèques /
-- Remises (le rapprochement bancaire reste donc juste).
--
-- Trois natures :
--   'retrait'  : annule (écriture inverse) une écriture existante
--                (ex. écriture de l'année dernière à sortir des comptes)
--   'ajout'    : ajoute une écriture (ex. versement attendu, pas encore
--                reçu, à rattacher à la période en cours)
--   'extourne' : écriture inverse créée automatiquement sur la période
--                suivante quand on coche « extourner » à la création d'un
--                'ajout' (le vrai versement arrivera sur cette période-là,
--                il ne sera donc pas compté deux fois)
--
-- Les montants suivent la même convention que Banque/Caisse :
-- résultat = credit - debit.
-- Dépend de : 014 (config_compta, journal_audit_compta), 015
-- (role_compta_courant), 018 (valider_type_description).
-- ============================================================

create table if not exists ecritures_diverses (
    id                     uuid primary key default gen_random_uuid(),
    date_ecriture          date not null,
    periode                text not null,
    libelle                text not null,
    debit                  numeric(10,2) not null default 0,
    credit                 numeric(10,2) not null default 0,
    type_mouvement         text,
    description            text,
    libelle_complementaire text,
    fournisseur            text,
    nom_chat               text,
    nature                 text not null check (nature in ('retrait', 'ajout', 'extourne')),
    motif                  text not null,
    source_table           text check (source_table is null or source_table in ('banque', 'caisse', 'cheque', 'remise')),
    source_id              uuid,
    groupe_id              uuid,
    statut                 text not null default 'aucun' check (statut in ('aucun', 'verifie')),
    cree_par               text,
    cree_le                timestamptz not null default now()
);
create index if not exists idx_od_periode on ecritures_diverses(periode);
create index if not exists idx_od_groupe on ecritures_diverses(groupe_id);

alter table ecritures_diverses enable row level security;
drop policy if exists ecritures_diverses_lecture on ecritures_diverses;
create policy ecritures_diverses_lecture on ecritures_diverses
    for select using (role_compta_courant() is not null);
drop policy if exists ecritures_diverses_ecriture_insert on ecritures_diverses;
create policy ecritures_diverses_ecriture_insert on ecritures_diverses
    for insert with check (role_compta_courant() = 'admin');
drop policy if exists ecritures_diverses_ecriture_update on ecritures_diverses;
create policy ecritures_diverses_ecriture_update on ecritures_diverses
    for update using (role_compta_courant() = 'admin');
drop policy if exists ecritures_diverses_ecriture_delete on ecritures_diverses;
create policy ecritures_diverses_ecriture_delete on ecritures_diverses
    for delete using (role_compta_courant() = 'admin');

-- ------------------------------------------------------------
-- Création (+ extourne automatique optionnelle sur une autre période)
-- ------------------------------------------------------------
create or replace function creer_ecriture_diverse(
    p_date                  date,
    p_periode               text,
    p_libelle               text,
    p_debit                 numeric,
    p_credit                numeric,
    p_nature                text,
    p_motif                 text,
    p_type_mouvement        text,
    p_description           text default null,
    p_libelle_complementaire text default null,
    p_fournisseur           text default null,
    p_nom_chat              text default null,
    p_source_table          text default null,
    p_source_id             uuid default null,
    p_periode_extourne      text default null,
    p_date_extourne         date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
    v_groupe uuid := null;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_nature not in ('retrait', 'ajout') then
        raise exception 'Nature invalide : % (attendu retrait ou ajout).', p_nature;
    end if;
    if p_date is null then raise exception 'La date est obligatoire.'; end if;
    if p_periode is null or btrim(p_periode) = '' then raise exception 'La période est obligatoire.'; end if;
    if p_libelle is null or btrim(p_libelle) = '' then raise exception 'Le libellé est obligatoire.'; end if;
    if p_motif is null or btrim(p_motif) = '' then raise exception 'Le motif (justification) est obligatoire.'; end if;
    if coalesce(p_debit,0) <= 0 and coalesce(p_credit,0) <= 0 then
        raise exception 'Le montant doit être supérieur à 0.';
    end if;
    if coalesce(p_debit,0) > 0 and coalesce(p_credit,0) > 0 then
        raise exception 'Une écriture est soit une entrée, soit une sortie.';
    end if;
    if p_type_mouvement is null or p_type_mouvement = '' then
        raise exception 'Le type de mouvement est obligatoire.';
    end if;
    perform valider_type_description(p_type_mouvement, p_description);

    if p_periode_extourne is not null and btrim(p_periode_extourne) <> '' then
        if p_nature <> 'ajout' then raise exception 'L''extourne ne s''applique qu''à un ajout.'; end if;
        v_groupe := gen_random_uuid();
    end if;

    insert into ecritures_diverses (
        date_ecriture, periode, libelle, debit, credit, type_mouvement, description,
        libelle_complementaire, fournisseur, nom_chat, nature, motif,
        source_table, source_id, groupe_id, cree_par
    ) values (
        p_date, p_periode, p_libelle, coalesce(p_debit,0), coalesce(p_credit,0), p_type_mouvement, p_description,
        p_libelle_complementaire, p_fournisseur, p_nom_chat, p_nature, p_motif,
        p_source_table, p_source_id, v_groupe, auth.jwt() ->> 'email'
    ) returning id into v_id;

    if v_groupe is not null then
        insert into ecritures_diverses (
            date_ecriture, periode, libelle, debit, credit, type_mouvement, description,
            libelle_complementaire, fournisseur, nom_chat, nature, motif, groupe_id, cree_par
        ) values (
            coalesce(p_date_extourne, p_date), p_periode_extourne, p_libelle,
            coalesce(p_credit,0), coalesce(p_debit,0), p_type_mouvement, p_description,
            p_libelle_complementaire, p_fournisseur, p_nom_chat, 'extourne',
            'Extourne automatique : ' || p_motif, v_groupe, auth.jwt() ->> 'email'
        );
    end if;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'AJOUT', 'ecritures_diverses', v_id::text, p_nature || ' — ' || p_libelle);

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- Modification (répercutée sur l'extourne liée, en sens inverse)
-- ------------------------------------------------------------
create or replace function modifier_ecriture_diverse(
    p_id                    uuid,
    p_date                  date,
    p_periode               text,
    p_libelle               text,
    p_debit                 numeric,
    p_credit                numeric,
    p_motif                 text,
    p_type_mouvement        text,
    p_description           text default null,
    p_libelle_complementaire text default null,
    p_fournisseur           text default null,
    p_nom_chat              text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_ligne ecritures_diverses%rowtype;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select * into v_ligne from ecritures_diverses where id = p_id;
    if not found then raise exception 'Écriture introuvable.'; end if;
    if v_ligne.nature = 'extourne' then
        raise exception 'Une extourne se modifie depuis l''écriture d''origine.';
    end if;
    if exists (select 1 from ecritures_diverses
               where (id = p_id or (groupe_id is not null and groupe_id = v_ligne.groupe_id)) and statut = 'verifie') then
        raise exception 'Écriture verrouillée — décochez « Vérifié » pour modifier.';
    end if;
    if p_motif is null or btrim(p_motif) = '' then raise exception 'Le motif est obligatoire.'; end if;
    if coalesce(p_debit,0) <= 0 and coalesce(p_credit,0) <= 0 then raise exception 'Le montant doit être supérieur à 0.'; end if;
    if coalesce(p_debit,0) > 0 and coalesce(p_credit,0) > 0 then raise exception 'Une écriture est soit une entrée, soit une sortie.'; end if;
    perform valider_type_description(p_type_mouvement, p_description);

    update ecritures_diverses set
        date_ecriture = p_date, periode = p_periode, libelle = p_libelle,
        debit = coalesce(p_debit,0), credit = coalesce(p_credit,0),
        type_mouvement = p_type_mouvement, description = p_description,
        libelle_complementaire = p_libelle_complementaire, fournisseur = p_fournisseur,
        nom_chat = p_nom_chat, motif = p_motif
    where id = p_id;

    if v_ligne.groupe_id is not null then
        update ecritures_diverses set
            libelle = p_libelle, debit = coalesce(p_credit,0), credit = coalesce(p_debit,0),
            type_mouvement = p_type_mouvement, description = p_description,
            libelle_complementaire = p_libelle_complementaire, fournisseur = p_fournisseur,
            nom_chat = p_nom_chat, motif = 'Extourne automatique : ' || p_motif
        where groupe_id = v_ligne.groupe_id and nature = 'extourne';
    end if;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'ecritures_diverses', p_id::text, p_libelle);
end;
$$;

-- ------------------------------------------------------------
-- Verrouillage (« Vérifié ») — s'applique au groupe entier
-- ------------------------------------------------------------
create or replace function verrouiller_ecriture_diverse(p_id uuid, p_verrouiller boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_groupe uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select groupe_id into v_groupe from ecritures_diverses where id = p_id;
    update ecritures_diverses set statut = case when p_verrouiller then 'verifie' else 'aucun' end
    where id = p_id or (v_groupe is not null and groupe_id = v_groupe);
    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'ecritures_diverses', p_id::text,
            case when p_verrouiller then 'Verrouillée' else 'Déverrouillée' end);
end;
$$;

-- ------------------------------------------------------------
-- Suppression (supprime aussi l'extourne liée)
-- ------------------------------------------------------------
create or replace function supprimer_ecriture_diverse(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_groupe uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select groupe_id into v_groupe from ecritures_diverses where id = p_id;
    if exists (select 1 from ecritures_diverses
               where (id = p_id or (v_groupe is not null and groupe_id = v_groupe)) and statut = 'verifie') then
        raise exception 'Écriture verrouillée — décochez « Vérifié » avant de supprimer.';
    end if;
    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    select auth.jwt() ->> 'email', 'SUPPRESSION', 'ecritures_diverses', p_id::text, libelle
    from ecritures_diverses where id = p_id;
    delete from ecritures_diverses where id = p_id or (v_groupe is not null and groupe_id = v_groupe);
end;
$$;
