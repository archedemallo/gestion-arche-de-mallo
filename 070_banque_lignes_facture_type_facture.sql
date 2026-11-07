-- ============================================================
-- 070_banque_lignes_facture_type_facture.sql
--
-- Toutes les lignes bancaires liées à une facture reçoivent :
--     Type de mouvement : Facture
--     Description       : Facture
--
-- 1) lier_banque_facture est redéfinie pour que les PROCHAINES liaisons
--    posent aussi Facture / Facture (la facture elle-même garde son vrai
--    type et sa vraie description, qui servent à l'analyse).
-- 2) Une mise à jour en masse applique la même règle aux lignes DÉJÀ liées.
--
-- Une ligne est « liée à une facture » si banque_mouvements.numero_facture
-- est renseigné OU si elle figure dans banque_mouvement_facture_liens.
--
-- Analyse (analyse.html) ignore ces lignes (le document compte, pas son
-- règlement) : changer leur type n'a aucun effet sur les chiffres.
--
-- Pour que le type « Facture » apparaisse aussi dans la fenêtre de
-- modification d'une ligne banque, ajouter dans Configuration le type de
-- mouvement « Facture » avec la description « Facture » (si absent).
--
-- AVANT d'exécuter (facultatif) : aperçu du nombre de lignes concernées
--
--   select count(*) as lignes,
--          count(*) filter (where statut = 'verifie') as dont_verrouillees
--   from banque_mouvements b
--   where nullif(btrim(b.numero_facture), '') is not null
--      or exists (select 1 from banque_mouvement_facture_liens l where l.banque_mouvement_id = b.id);
--
-- Exécutable seul dans le SQL Editor de Supabase. Dépend de : 035, 063, 069.
-- ============================================================


-- ---------- 1. Prochaines liaisons ----------
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
    v_type   text;
    v_desc   text;
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

    -- Orthographe exacte du type/description « Facture » telle que configurée (sinon « Facture »)
    select x.r_type, x.r_desc into v_type, v_desc
    from resoudre_type_description(array['Facture', 'Factures'], array['Facture', 'Factures']) x;

    update banque_mouvements set
        type_mouvement = v_type,
        description    = v_desc,
        fournisseur    = (
            select nullif(string_agg(distinct f.fournisseur, ', '), '')
            from banque_mouvement_facture_liens l join factures f on f.id = l.facture_id
            where l.banque_mouvement_id = p_banque_mouvement_id
        ),
        lien_facture   = coalesce(nullif(v_fac.lien_pdf, ''), lien_facture)
    where id = p_banque_mouvement_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Facture liée : ' || coalesce(v_fac.numero_facture, ''));
end;
$$;


-- ---------- 2. Lignes déjà liées : mise à jour en masse ----------
do $$
declare
    v_type text;
    v_desc text;
    v_nb   integer;
begin
    select x.r_type, x.r_desc into v_type, v_desc
    from resoudre_type_description(array['Facture', 'Factures'], array['Facture', 'Factures']) x;

    update banque_mouvements b set
        type_mouvement = v_type,
        description    = v_desc
    where nullif(btrim(b.numero_facture), '') is not null
       or exists (select 1 from banque_mouvement_facture_liens l where l.banque_mouvement_id = b.id);

    get diagnostics v_nb = row_count;
    raise notice '% ligne(s) banque liée(s) à une facture passée en Type "%" / Description "%".', v_nb, v_type, v_desc;
end;
$$;
