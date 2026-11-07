-- ============================================================
-- 069_banque_lier_sans_copie_type_description.sql
--
-- Évite les doublons dans l'analyse des chiffres : quand une ligne
-- bancaire est rapprochée d'une FACTURE, d'un CHÈQUE ou d'une REMISE DE
-- CHÈQUES, c'est le document qui porte le type de mouvement, la
-- description et le nom du chat. La ligne banque n'est plus que le
-- règlement : on ne recopie plus ces 3 champs dessus (063 le faisait).
--
-- Ce qui est conservé sur la ligne banque : le lien lui-même, le n° de
-- facture, le lien PDF, le fournisseur, le mode de règlement et le
-- libellé complémentaire (informations d'affichage, non utilisées pour
-- classer les montants).
--
-- NE CHANGE PAS : lier_banque_suivi (la ligne Suivi est ventilée par
-- Analyse) et lier_banque_caisse (virement interne).
--
-- Exécutable seul dans le SQL Editor de Supabase (create or replace).
-- Dépend de : 035, 038, 063.
-- ============================================================


-- ---------- CHÈQUE ----------
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
    if not exists (select 1 from cheques where id = p_cheque_id) then raise exception 'Chèque introuvable.'; end if;
    if exists (select 1 from banque_mouvements where id <> p_banque_mouvement_id and ref_cheque = p_cheque_id) then
        raise exception 'Ce chèque est déjà rattaché à un autre mouvement.';
    end if;

    -- type_mouvement, description et nom_chat restent ceux du chèque (pas de recopie)
    update banque_mouvements b set
        ref_cheque             = p_cheque_id,
        libelle_complementaire = coalesce(nullif(c.beneficiaire, ''), b.libelle_complementaire),
        fournisseur            = coalesce(nullif(c.fournisseur, ''), b.fournisseur),
        mode_reglement         = 'Chèque'
    from cheques c
    where b.id = p_banque_mouvement_id and c.id = p_cheque_id;

    update cheques set statut = 'encaisse', date_encaissement = v_date, ref_banque = p_banque_mouvement_id where id = p_cheque_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Chèque lié');
end;
$$;


-- ---------- REMISE DE CHÈQUES ----------
create or replace function lier_banque_remise(p_banque_mouvement_id uuid, p_remise_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut text;
    v_date   date;
    v_rem    remises_cheques%rowtype;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut, date_mouvement into v_statut, v_date from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut is null then raise exception 'Opération introuvable.'; end if;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" pour modifier.'; end if;
    select * into v_rem from remises_cheques where id = p_remise_id;
    if v_rem.id is null then raise exception 'Remise introuvable.'; end if;
    if exists (select 1 from banque_mouvements where id <> p_banque_mouvement_id and ref_remise = p_remise_id) then
        raise exception 'Cette remise est déjà rattachée à un autre mouvement.';
    end if;

    -- type et description : ceux des chèques du bordereau (remise_cheques_details), pas de recopie
    update banque_mouvements set
        ref_remise             = p_remise_id,
        libelle_complementaire = 'Remise chèques ' || coalesce(v_rem.numero_bordereau, '') || ' — ' || coalesce(v_rem.nb_cheques, 0) || ' chèque(s)',
        mode_reglement         = 'Remise de chèques'
    where id = p_banque_mouvement_id;

    update remises_cheques set statut = 'encaisse', date_encaissement = v_date, ref_banque = p_banque_mouvement_id where id = p_remise_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Remise de chèques liée');
end;
$$;


-- ---------- FACTURE ----------
-- Une banque peut régler plusieurs factures de types différents : chacune
-- est comptée sous son propre type/description (à la période de la facture).
create or replace function lier_banque_facture(p_banque_mouvement_id uuid, p_facture_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut text;
    v_date   date;
    v_fac    factures%rowtype;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut, date_mouvement into v_statut, v_date from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut is null then raise exception 'Opération introuvable.'; end if;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" pour modifier.'; end if;
    select * into v_fac from factures where id = p_facture_id;
    if v_fac.id is null then raise exception 'Facture introuvable.'; end if;

    insert into banque_mouvement_facture_liens (banque_mouvement_id, facture_id)
    values (p_banque_mouvement_id, p_facture_id)
    on conflict (banque_mouvement_id, facture_id) do nothing;

    update factures set statut = 'payee', date_reglement = v_date where id = p_facture_id;

    update banque_mouvements set numero_facture = (
        select nullif(string_agg(f.numero_facture, ', ' order by f.numero_facture), '')
        from banque_mouvement_facture_liens l join factures f on f.id = l.facture_id
        where l.banque_mouvement_id = p_banque_mouvement_id
    ) where id = p_banque_mouvement_id;

    -- Informations d'affichage seulement (type, description et nom_chat restent sur la facture)
    update banque_mouvements set
        fournisseur = (
            select nullif(string_agg(distinct f.fournisseur, ', '), '')
            from banque_mouvement_facture_liens l join factures f on f.id = l.facture_id
            where l.banque_mouvement_id = p_banque_mouvement_id
        ),
        lien_facture = coalesce(nullif(v_fac.lien_pdf, ''), lien_facture)
    where id = p_banque_mouvement_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Facture liée : ' || coalesce(v_fac.numero_facture, ''));
end;
$$;


-- ============================================================
-- PARTIE B — OPTIONNELLE : nettoyer les lignes DÉJÀ rapprochées
-- (type, description et chat recopiés par la 063).
-- Analyse (analyse.html) ignore de toute façon ces lignes ; ce nettoyage
-- sert seulement à ce que la grille Banque n'affiche plus de doublons.
-- 1) Lancer d'abord l'aperçu :
--
--   select count(*) as lignes_concernees
--   from banque_mouvements
--   where statut <> 'verifie'
--     and (ref_cheque is not null or ref_remise is not null or numero_facture is not null)
--     and suivi_ref is distinct from 'oui';
--
-- 2) Puis, si le nombre est cohérent, décommenter et exécuter :
--
--   update banque_mouvements set
--       type_mouvement = null, description = null, nom_chat = null
--   where statut <> 'verifie'
--     and (ref_cheque is not null or ref_remise is not null or numero_facture is not null)
--     and suivi_ref is distinct from 'oui';
--
-- Les lignes « Vérifié » (verrouillées) et celles liées à Suivi ne sont pas touchées.
-- ============================================================
