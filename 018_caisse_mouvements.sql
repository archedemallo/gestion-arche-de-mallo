-- ============================================================
-- CAISSE — mouvements du quotidien (caisse1 + caisse2)
-- ============================================================
-- Reprend caisse.html / caisse2.html (quasi identiques dans
-- compta-main, fusionnés en une seule page avec sélecteur de caisse —
-- même principe que caisse_physique.html).
--
-- Validation demandée : la description doit appartenir au type de
-- mouvement choisi (ex. type "Dons" → seule description "Dons"
-- possible si c'est la seule créée sous ce type dans la config). Cette
-- validation n'existait PAS dans l'ancien système (la description y
-- était une liste globale, non filtrée par type) — c'est un vrai ajout,
-- pas une reprise à l'identique.
--
-- Toutes les fonctions d'écriture vérifient explicitement le rôle admin
-- (obligatoire : "security definer" contourne le RLS par nature).

create or replace function valider_type_description(p_type text, p_description text)
returns void
language plpgsql
stable
as $$
begin
    if p_description is null or p_description = '' then
        return; -- description optionnelle
    end if;
    if not exists (
        select 1 from descriptions_mouvement dm
        join types_mouvement tm on tm.id = dm.type_mouvement_id
        where tm.valeur = p_type and dm.valeur = p_description
    ) then
        raise exception 'La description "%" n''est pas associée au type de mouvement "%" (voir la page Configuration).', p_description, p_type;
    end if;
end;
$$;

create or replace function creer_operation_caisse(
    p_caisse         text,
    p_date           date,
    p_libelle        text,
    p_debit          numeric default 0,
    p_credit         numeric default 0,
    p_periode        text default null,
    p_type_mouvement text default null,
    p_description    text default null,
    p_libelle_complementaire text default null,
    p_fournisseur    text default null,
    p_nom_chat       text default null,
    p_numero_recu    text default null,
    p_numero_bordereau text default null,
    p_reglement      text default 'Espèces'
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
    if p_caisse not in ('caisse1', 'caisse2') then
        raise exception 'Caisse invalide : % (attendu caisse1 ou caisse2)', p_caisse;
    end if;
    if coalesce(p_debit,0) <= 0 and coalesce(p_credit,0) <= 0 then
        raise exception 'Le montant doit être supérieur à 0.';
    end if;
    if p_type_mouvement is null or p_type_mouvement = '' then
        raise exception 'Le type de mouvement est obligatoire.';
    end if;
    perform valider_type_description(p_type_mouvement, p_description);

    insert into caisse_mouvements (
        caisse, date_mouvement, libelle, debit, credit, periode,
        type_mouvement, description, libelle_complementaire, fournisseur,
        nom, reglement, nom_chat, numero_recu, numero_bordereau
    ) values (
        p_caisse, p_date, p_libelle, coalesce(p_debit,0), coalesce(p_credit,0), p_periode,
        p_type_mouvement, p_description, p_libelle_complementaire, p_fournisseur,
        p_libelle, p_reglement, p_nom_chat, p_numero_recu, p_numero_bordereau
    )
    returning id into v_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'AJOUT', 'caisse_mouvements', v_id::text, p_libelle);

    return v_id;
end;
$$;

create or replace function modifier_operation_caisse(
    p_id             uuid,
    p_date           date,
    p_libelle        text,
    p_debit          numeric default 0,
    p_credit         numeric default 0,
    p_periode        text default null,
    p_type_mouvement text default null,
    p_description    text default null,
    p_libelle_complementaire text default null,
    p_fournisseur    text default null,
    p_nom_chat       text default null,
    p_numero_recu    text default null,
    p_numero_bordereau text default null
)
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

    select flag_statut into v_statut from caisse_mouvements where id = p_id;
    if v_statut is null then
        raise exception 'Opération introuvable.';
    end if;
    if v_statut = 'verifie' then
        raise exception 'Ligne verrouillée — décochez "Vérifié" pour modifier.';
    end if;
    if coalesce(p_debit,0) <= 0 and coalesce(p_credit,0) <= 0 then
        raise exception 'Le montant doit être supérieur à 0.';
    end if;
    perform valider_type_description(p_type_mouvement, p_description);

    update caisse_mouvements set
        date_mouvement = p_date, libelle = p_libelle, debit = coalesce(p_debit,0), credit = coalesce(p_credit,0),
        periode = p_periode, type_mouvement = p_type_mouvement, description = p_description,
        libelle_complementaire = p_libelle_complementaire, fournisseur = p_fournisseur, nom = p_libelle,
        nom_chat = p_nom_chat, numero_recu = p_numero_recu, numero_bordereau = p_numero_bordereau
    where id = p_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'caisse_mouvements', p_id::text, p_libelle);
end;
$$;

-- Verrouille ('verifie') ou déverrouille ('aucun') une ligne. Une ligne
-- verrouillée ne peut plus être modifiée ni supprimée tant qu'elle n'est
-- pas déverrouillée (voir modifier_operation_caisse et
-- supprimer_operation_caisse ci-dessus/dessous).
create or replace function verrouiller_operation_caisse(p_id uuid, p_verrouiller boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update caisse_mouvements
        set flag_statut = case when p_verrouiller then 'verifie' else 'aucun' end
        where id = p_id;
    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'caisse_mouvements', p_id::text, case when p_verrouiller then 'Verrouillée' else 'Déverrouillée' end);
end;
$$;

-- Annote une ligne ("à vérifier" + commentaire), ou efface l'annotation
-- si marquée résolue.
create or replace function annoter_operation_caisse(p_id uuid, p_commentaire text, p_resolu boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update caisse_mouvements set
        flag_statut = case when p_resolu then 'aucun' else 'a_verifier' end,
        flag_commentaire = case when p_resolu then null else p_commentaire end
    where id = p_id and flag_statut <> 'verifie';
end;
$$;

create or replace function supprimer_operation_caisse(p_id uuid)
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
    select flag_statut into v_statut from caisse_mouvements where id = p_id;
    if v_statut = 'verifie' then
        raise exception 'Ligne verrouillée — décochez "Vérifié" avant de supprimer.';
    end if;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    select auth.jwt() ->> 'email', 'SUPPRESSION', 'caisse_mouvements', p_id::text, libelle
    from caisse_mouvements where id = p_id;

    delete from caisse_mouvements where id = p_id;
end;
$$;
