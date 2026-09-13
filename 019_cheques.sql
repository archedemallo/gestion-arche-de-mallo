-- ============================================================
-- CHÈQUES ÉMIS
-- ============================================================
-- Reprend cheques.html. Un chèque émis n'apparaît en banque qu'au
-- moment de son encaissement (saisi manuellement côté Banque, page pas
-- encore migrée) — ce n'était déjà pas automatique dans l'ancien
-- système non plus.

create or replace function creer_cheque(
    p_numero_cheque  text,
    p_date_emission  date,
    p_beneficiaire   text,
    p_montant        numeric,
    p_type_mouvement text,
    p_description    text default null,
    p_libelle_complementaire text default null,
    p_fournisseur    text default null,
    p_nom_chat       text default null,
    p_periode        text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_numero_cheque is null or p_numero_cheque = '' then raise exception 'Le numéro de chèque est obligatoire.'; end if;
    if p_beneficiaire is null or p_beneficiaire = '' then raise exception 'Le bénéficiaire est obligatoire.'; end if;
    if coalesce(p_montant,0) <= 0 then raise exception 'Le montant doit être supérieur à 0.'; end if;
    if p_type_mouvement is null or p_type_mouvement = '' then raise exception 'Le type de mouvement est obligatoire.'; end if;
    perform valider_type_description(p_type_mouvement, p_description);

    insert into cheques (
        numero_cheque, date_emission, beneficiaire, montant, type_mouvement,
        description, libelle_complementaire, fournisseur, nom_chat, periode, statut
    ) values (
        p_numero_cheque, p_date_emission, p_beneficiaire, p_montant, p_type_mouvement,
        p_description, p_libelle_complementaire, p_fournisseur, p_nom_chat, p_periode, 'en_attente'
    )
    returning id into v_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'AJOUT', 'cheques', v_id::text, p_numero_cheque || ' — ' || p_beneficiaire);

    return v_id;
end;
$$;

create or replace function modifier_cheque(
    p_id             uuid,
    p_numero_cheque  text,
    p_date_emission  date,
    p_beneficiaire   text,
    p_montant        numeric,
    p_type_mouvement text,
    p_description    text default null,
    p_libelle_complementaire text default null,
    p_fournisseur    text default null,
    p_nom_chat       text default null,
    p_periode        text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_verifie boolean;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select verifie into v_verifie from cheques where id = p_id;
    if v_verifie is null then raise exception 'Chèque introuvable.'; end if;
    if v_verifie then raise exception 'Chèque vérifié — décochez pour modifier.'; end if;
    if coalesce(p_montant,0) <= 0 then raise exception 'Le montant doit être supérieur à 0.'; end if;
    perform valider_type_description(p_type_mouvement, p_description);

    update cheques set
        numero_cheque = p_numero_cheque, date_emission = p_date_emission, beneficiaire = p_beneficiaire,
        montant = p_montant, type_mouvement = p_type_mouvement, description = p_description,
        libelle_complementaire = p_libelle_complementaire, fournisseur = p_fournisseur,
        nom_chat = p_nom_chat, periode = p_periode
    where id = p_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'cheques', p_id::text, p_numero_cheque);
end;
$$;

create or replace function verrouiller_cheque(p_id uuid, p_verrouiller boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update cheques set verifie = p_verrouiller where id = p_id;
    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'cheques', p_id::text, case when p_verrouiller then 'Verrouillé' else 'Déverrouillé' end);
end;
$$;

create or replace function supprimer_cheque(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_verifie boolean;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select verifie into v_verifie from cheques where id = p_id;
    if v_verifie then raise exception 'Chèque vérifié — décochez avant de supprimer.'; end if;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    select auth.jwt() ->> 'email', 'SUPPRESSION', 'cheques', p_id::text, numero_cheque from cheques where id = p_id;

    delete from cheques where id = p_id;
end;
$$;
