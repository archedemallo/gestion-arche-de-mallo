-- ============================================================
-- RATTACHEMENT CHÈQUE/FACTURE DEPUIS BANQUE — panneau dédié
-- ============================================================
-- Rétablit, pour un mouvement bancaire, ce que faisait l'ancien système
-- (Google Sheets) dans son panneau "Rapprochement & Ventilation" :
--  - lier un chèque en attente à un mouvement (le marque "encaissé") —
--    jusqu'ici possible seulement à la création via
--    creer_operation_banque(p_ref_cheque), pas après coup ;
--  - lier une ou plusieurs factures non réglées à un mouvement (les
--    marque "payée", et reporte leur(s) numéro(s) dans
--    banque_mouvements.numero_facture, séparés par virgule si
--    plusieurs — même convention que l'ancien système).
--
-- Une facture peut être liée à plusieurs mouvements bancaires (relance,
-- règlement partiel...), d'où une vraie table de liaison plutôt qu'une
-- FK unique sur factures — même modèle que
-- caisse_mouvement_suivi_liens / banque_mouvement_suivi_liens
-- (017_liens_mouvement_suivi.sql).

create table if not exists banque_mouvement_facture_liens (
    id                   uuid primary key default gen_random_uuid(),
    banque_mouvement_id  uuid not null references banque_mouvements(id) on delete cascade,
    facture_id           uuid not null references factures(id) on delete cascade,
    unique (banque_mouvement_id, facture_id)
);
create index if not exists idx_bmfl_banque_mouvement_id on banque_mouvement_facture_liens(banque_mouvement_id);
create index if not exists idx_bmfl_facture_id on banque_mouvement_facture_liens(facture_id);

alter table banque_mouvement_facture_liens enable row level security;

drop policy if exists banque_mouvement_facture_liens_lecture on banque_mouvement_facture_liens;
create policy banque_mouvement_facture_liens_lecture on banque_mouvement_facture_liens
    for select using (role_compta_courant() is not null);
drop policy if exists banque_mouvement_facture_liens_ecriture on banque_mouvement_facture_liens;
create policy banque_mouvement_facture_liens_ecriture on banque_mouvement_facture_liens
    for all using (role_compta_courant() = 'admin');

-- Lie un chèque en attente à un mouvement bancaire déjà existant.
create or replace function lier_banque_cheque(p_banque_mouvement_id uuid, p_cheque_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut text;
    v_date   date;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut, date_mouvement into v_statut, v_date from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut is null then raise exception 'Opération introuvable.'; end if;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" pour modifier.'; end if;
    if exists (select 1 from banque_mouvements where id <> p_banque_mouvement_id and ref_cheque = p_cheque_id) then
        raise exception 'Ce chèque est déjà rattaché à un autre mouvement.';
    end if;

    update banque_mouvements set ref_cheque = p_cheque_id where id = p_banque_mouvement_id;
    update cheques set statut = 'encaisse', date_encaissement = v_date, ref_banque = p_banque_mouvement_id where id = p_cheque_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Chèque lié');
end;
$$;

-- Lie une facture non réglée à un mouvement bancaire : la marque payée
-- et régénère banque_mouvements.numero_facture à partir de toutes les
-- factures actuellement liées (séparées par ", ").
create or replace function lier_banque_facture(p_banque_mouvement_id uuid, p_facture_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut text;
    v_date   date;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut, date_mouvement into v_statut, v_date from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut is null then raise exception 'Opération introuvable.'; end if;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" pour modifier.'; end if;
    if not exists (select 1 from factures where id = p_facture_id) then raise exception 'Facture introuvable.'; end if;

    insert into banque_mouvement_facture_liens (banque_mouvement_id, facture_id)
    values (p_banque_mouvement_id, p_facture_id)
    on conflict (banque_mouvement_id, facture_id) do nothing;

    update factures set statut = 'payee', date_reglement = v_date where id = p_facture_id;

    update banque_mouvements set numero_facture = (
        select nullif(string_agg(f.numero_facture, ', ' order by f.numero_facture), '')
        from banque_mouvement_facture_liens l join factures f on f.id = l.facture_id
        where l.banque_mouvement_id = p_banque_mouvement_id
    ) where id = p_banque_mouvement_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    select auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Facture liée : ' || coalesce(numero_facture, '')
    from factures where id = p_facture_id;
end;
$$;

-- Délie une facture d'un mouvement bancaire : la repasse en attente et
-- régénère banque_mouvements.numero_facture à partir des factures
-- restantes.
create or replace function delier_banque_facture(p_banque_mouvement_id uuid, p_facture_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut text;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut into v_statut from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" pour modifier.'; end if;

    delete from banque_mouvement_facture_liens
        where banque_mouvement_id = p_banque_mouvement_id and facture_id = p_facture_id;

    update factures set statut = null, date_reglement = null where id = p_facture_id;

    update banque_mouvements set numero_facture = (
        select nullif(string_agg(f.numero_facture, ', ' order by f.numero_facture), '')
        from banque_mouvement_facture_liens l join factures f on f.id = l.facture_id
        where l.banque_mouvement_id = p_banque_mouvement_id
    ) where id = p_banque_mouvement_id;
end;
$$;

-- supprimer_operation_banque doit aussi libérer les factures liées
-- (comme c'était déjà fait pour chèque/remise), sans quoi elles
-- resteraient marquées "payée" sans mouvement bancaire réel.
create or replace function supprimer_operation_banque(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut text;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut into v_statut from banque_mouvements where id = p_id;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" avant de supprimer.'; end if;

    -- Libère le chèque/la remise/les factures éventuellement rattaché(e)s,
    -- pour ne pas les laisser marqué(e)s "encaissé"/"payée" sans mouvement
    -- bancaire réel.
    update cheques set statut = 'en_attente', date_encaissement = null, ref_banque = null where ref_banque = p_id;
    update remises_cheques set statut = 'en_attente', date_encaissement = null, ref_banque = null where ref_banque = p_id;
    update factures set statut = null, date_reglement = null
        where id in (select facture_id from banque_mouvement_facture_liens where banque_mouvement_id = p_id);
    delete from banque_mouvement_facture_liens where banque_mouvement_id = p_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    select auth.jwt() ->> 'email', 'SUPPRESSION', 'banque_mouvements', p_id::text, libelle from banque_mouvements where id = p_id;

    delete from banque_mouvements where id = p_id;
end;
$$;
