-- ============================================================
-- 063_banque_lier_copie_type_description.sql
--
-- Aligne le rapprochement bancaire de "gestion" sur celui de "compta"
-- (banque.html > panneau Rapprochement) :
--
--   1. LIER recopie désormais type de mouvement + description (et les
--      champs associés) sur la ligne bancaire, pour les 5 types de
--      liaison : chèque, facture, remise de chèques, sortie de caisse,
--      ligne Suivi. Avant, seuls les identifiants de liaison étaient
--      posés : le type et la description restaient à saisir à la main.
--
--   2. La liaison Suivi est désormais AJOUTÉE aux liens existants
--      (avant : lier_banque_suivi supprimait tous les liens du mouvement
--      puis réinsérait ceux de la sélection — comme dans compta, où
--      "toute nouvelle sélection s'ajoute, rien n'est écrasé").
--
--   3. Deux nouvelles fonctions alimentent les sous-catégories (onglets)
--      du panneau : lister_suivi_pour_rapprochement() et
--      compter_suivi_a_rapprocher() — équivalent de la file
--      Import_Rapprochement "en_attente" de compta, avec ses badges.
--
-- Mapping onglet Suivi -> type / description (repris de
-- import-suivi.html de compta) :
--   Adoption                 -> Adoption / Adoption
--   Réservation (chat, chaton, autre animal)
--                            -> Adoption / Reservation
--   Prêt matériel            -> Adoption / Retour matériel
--   Don                      -> Dons / Dons
--   Adhésion                 -> Adhesion / Adhesion
-- Chaque valeur est d'abord cherchée dans la config (types_mouvement /
-- descriptions_mouvement, sans tenir compte de la casse ni des accents)
-- pour reprendre l'orthographe exacte de la page Configuration ; si elle
-- n'y existe pas, la valeur par défaut ci-dessus est utilisée.
--
-- Exécutable seul dans le SQL Editor de Supabase (create or replace).
-- ============================================================


-- ---------- Utilitaires ----------

create or replace function norm_txt(p text)
returns text
language sql
immutable
as $$
    select translate(lower(coalesce(p, '')), 'éèêëàâäîïôöûùüç', 'eeeeaaaiioouuuc');
$$;

-- Fusionne deux listes séparées par des virgules sans doublon, en
-- gardant l'ordre d'apparition (équivalent de mergeCsv de compta).
create or replace function fusion_csv(p_existant text, p_ajout text)
returns text
language sql
immutable
as $$
    select nullif(string_agg(v, ', ' order by ord), '')
    from (
        select distinct on (v) v, ord
        from (
            select btrim(t.v0) as v, t.ord
            from unnest(string_to_array(coalesce(p_existant, '') || ',' || coalesce(p_ajout, ''), ',')) with ordinality as t(v0, ord)
        ) x
        where v <> ''
        order by v, ord
    ) s;
$$;

create or replace function nom_personne_affiche(p_personne_id uuid)
returns text
language sql
stable
set search_path = public
as $$
    select coalesce(
        (select coalesce(nullif(btrim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), ''), p.raison_sociale)
         from personnes p where p.id = p_personne_id),
        'Anonyme'
    );
$$;

-- Cherche, dans la config, le premier type (puis la première description
-- de ce type) parmi les candidats ; sinon renvoie les premiers candidats
-- tels quels.
create or replace function resoudre_type_description(p_types text[], p_descriptions text[])
returns table (r_type text, r_desc text)
language plpgsql
stable
set search_path = public
as $$
declare
    v_type_id uuid;
    v_type    text;
    v_desc    text;
    c         text;
begin
    foreach c in array p_types loop
        select tm.id, tm.valeur into v_type_id, v_type
        from types_mouvement tm where norm_txt(tm.valeur) = norm_txt(c) limit 1;
        exit when v_type_id is not null;
    end loop;

    if v_type_id is null then
        return query select p_types[1], p_descriptions[1];
        return;
    end if;

    foreach c in array p_descriptions loop
        select dm.valeur into v_desc
        from descriptions_mouvement dm
        where dm.type_mouvement_id = v_type_id and norm_txt(dm.valeur) = norm_txt(c) limit 1;
        exit when v_desc is not null;
    end loop;

    return query select v_type, coalesce(v_desc, p_descriptions[1]);
end;
$$;

-- Informations à recopier sur la ligne bancaire pour un enregistrement Suivi.
create or replace function infos_suivi(p_kind text, p_id uuid)
returns table (nom text, nom_chat text, numero_recu text, r_type text, r_desc text)
language plpgsql
stable
set search_path = public
as $$
declare
    v_nom   text;
    v_chat  text;
    v_recu  text;
    v_types text[];
    v_descs text[];
begin
    if p_kind = 'adhesion' then
        select nom_personne_affiche(a.personne_id) into v_nom from adhesions a where a.id = p_id;
        v_types := array['Adhesion', 'Adhésion'];  v_descs := array['Adhesion', 'Adhésion'];
    elsif p_kind = 'don' then
        select nom_personne_affiche(d.personne_id), d.numero_recu_fiscal into v_nom, v_recu from dons d where d.id = p_id;
        v_types := array['Dons', 'Don'];  v_descs := array['Dons', 'Don'];
    elsif p_kind = 'adoption' then
        select nom_personne_affiche(ad.personne_id), coalesce(nullif(an.nom_adoption, ''), an.nom_usuel)
          into v_nom, v_chat
        from adoptions ad left join animaux an on an.id = ad.animal_id where ad.id = p_id;
        v_types := array['Adoption'];  v_descs := array['Adoption'];
    elsif p_kind = 'reservation' then
        select nom_personne_affiche(r.personne_id), an.nom_usuel
          into v_nom, v_chat
        from reservations r left join animaux an on an.id = r.animal_id where r.id = p_id;
        v_types := array['Adoption'];  v_descs := array['Reservation', 'Réservation'];
    else  -- materiel_mouvement
        select nom_personne_affiche(m.personne_id) into v_nom from materiel_mouvements m where m.id = p_id;
        v_types := array['Adoption'];  v_descs := array['Retour matériel', 'Retour materiel'];
    end if;

    return query
    select v_nom, v_chat, v_recu, x.r_type, x.r_desc
    from resoudre_type_description(v_types, v_descs) x;
end;
$$;


-- ============================================================
-- 1. SUIVI : lier = ajouter aux liens existants + recopier type,
--    description, nom(s), nom du chat, n° de reçu fiscal
-- ============================================================
create or replace function lier_banque_suivi(
    p_banque_mouvement_id uuid,
    p_liens jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_item     jsonb;
    v_count    integer := 0;
    v_nb_cibles integer;
    v_statut   text;
    v_kind     text;
    v_cible    uuid;
    v_exist    uuid;
    v_info     record;
    v_noms     text;
    v_chats    text;
    v_recus    text;
    v_type     text;
    v_desc     text;
    v_premier  boolean := true;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_liens is null or jsonb_array_length(p_liens) = 0 then
        raise exception 'Ajoutez au moins un lien.';
    end if;
    select statut into v_statut from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut is null then raise exception 'Opération introuvable.'; end if;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" pour modifier.'; end if;

    for v_item in select * from jsonb_array_elements(p_liens) loop
        v_nb_cibles :=
              (case when v_item ? 'adhesion_id' and v_item->>'adhesion_id' is not null then 1 else 0 end)
            + (case when v_item ? 'don_id' and v_item->>'don_id' is not null then 1 else 0 end)
            + (case when v_item ? 'adoption_id' and v_item->>'adoption_id' is not null then 1 else 0 end)
            + (case when v_item ? 'reservation_id' and v_item->>'reservation_id' is not null then 1 else 0 end)
            + (case when v_item ? 'materiel_mouvement_id' and v_item->>'materiel_mouvement_id' is not null then 1 else 0 end);
        if v_nb_cibles <> 1 then
            raise exception 'Chaque ligne de ventilation doit cibler exactement un enregistrement Suivi (adhésion, don, adoption, réservation ou prêt de matériel).';
        end if;

        v_kind := case
            when v_item->>'adhesion_id' is not null then 'adhesion'
            when v_item->>'don_id' is not null then 'don'
            when v_item->>'adoption_id' is not null then 'adoption'
            when v_item->>'reservation_id' is not null then 'reservation'
            else 'materiel_mouvement' end;
        v_cible := (v_item->>(v_kind || '_id'))::uuid;

        -- Déjà lié à ce mouvement : on met seulement le montant à jour.
        select l.id into v_exist
        from banque_mouvement_suivi_liens l
        where l.banque_mouvement_id = p_banque_mouvement_id
          and coalesce(l.adhesion_id, l.don_id, l.adoption_id, l.reservation_id, l.materiel_mouvement_id) = v_cible
        limit 1;

        if v_exist is not null then
            update banque_mouvement_suivi_liens set montant = (v_item->>'montant')::numeric where id = v_exist;
        else
            insert into banque_mouvement_suivi_liens (banque_mouvement_id, adhesion_id, don_id, adoption_id, reservation_id, materiel_mouvement_id, montant)
            values (
                p_banque_mouvement_id,
                (v_item->>'adhesion_id')::uuid,
                (v_item->>'don_id')::uuid,
                (v_item->>'adoption_id')::uuid,
                (v_item->>'reservation_id')::uuid,
                (v_item->>'materiel_mouvement_id')::uuid,
                (v_item->>'montant')::numeric
            );
        end if;

        select * into v_info from infos_suivi(v_kind, v_cible);
        v_noms  := fusion_csv(v_noms,  v_info.nom);
        v_chats := fusion_csv(v_chats, v_info.nom_chat);
        v_recus := fusion_csv(v_recus, v_info.numero_recu);
        if v_premier then            -- comme compta : type/description de la 1re ligne liée
            v_type := v_info.r_type;
            v_desc := v_info.r_desc;
            v_premier := false;
        end if;
        v_count := v_count + 1;
    end loop;

    update banque_mouvements set
        suivi_ref              = 'oui',
        type_mouvement         = coalesce(v_type, type_mouvement),
        description            = coalesce(v_desc, description),
        libelle_complementaire = fusion_csv(libelle_complementaire, v_noms),
        nom_chat               = fusion_csv(nom_chat, v_chats),
        numero_don_fiscal      = fusion_csv(numero_don_fiscal, v_recus)
    where id = p_banque_mouvement_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text,
            format('%s ligne(s) Suivi liée(s) : %s', v_count, coalesce(v_noms, '')));

    return v_count;
end;
$$;


-- ============================================================
-- 2. CHÈQUE : recopie type, description, bénéficiaire, fournisseur,
--    mode de règlement, nom du chat
-- ============================================================
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

    update banque_mouvements b set
        ref_cheque             = p_cheque_id,
        type_mouvement         = coalesce(nullif(c.type_mouvement, ''), b.type_mouvement),
        description            = coalesce(nullif(c.description, ''), b.description),
        libelle_complementaire = coalesce(nullif(c.beneficiaire, ''), b.libelle_complementaire),
        fournisseur            = coalesce(nullif(c.fournisseur, ''), b.fournisseur),
        mode_reglement         = 'Chèque',
        nom_chat               = coalesce(nullif(c.nom_chat, ''), b.nom_chat)
    from cheques c
    where b.id = p_banque_mouvement_id and c.id = p_cheque_id;

    update cheques set statut = 'encaisse', date_encaissement = v_date, ref_banque = p_banque_mouvement_id where id = p_cheque_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Chèque lié');
end;
$$;


-- ============================================================
-- 3. REMISE DE CHÈQUES : type et description "Remise Cheque",
--    détail du bordereau, mode de règlement
-- ============================================================
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
    v_type   text;
    v_desc   text;
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

    select x.r_type, x.r_desc into v_type, v_desc
    from resoudre_type_description(array['Remise Cheque', 'Remise chèque', 'Remise de chèques'],
                                   array['Remise Cheque', 'Remise chèque', 'Remise de chèques']) x;

    update banque_mouvements set
        ref_remise             = p_remise_id,
        type_mouvement         = v_type,
        description            = v_desc,
        libelle_complementaire = 'Remise chèques ' || coalesce(v_rem.numero_bordereau, '') || ' — ' || coalesce(v_rem.nb_cheques, 0) || ' chèque(s)',
        mode_reglement         = 'Remise de chèques'
    where id = p_banque_mouvement_id;

    update remises_cheques set statut = 'encaisse', date_encaissement = v_date, ref_banque = p_banque_mouvement_id where id = p_remise_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Remise de chèques liée');
end;
$$;


-- ============================================================
-- 4. FACTURE : recopie catégorie -> type, description, fournisseur,
--    lien PDF, nom du chat (cas "plusieurs factures Amazon" inclus)
-- ============================================================
create or replace function lier_banque_facture(p_banque_mouvement_id uuid, p_facture_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut      text;
    v_date        date;
    v_fac         factures%rowtype;
    v_nb          integer;
    v_tous_amazon boolean;
    v_ref_cheque  uuid;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select statut, date_mouvement, ref_cheque into v_statut, v_date, v_ref_cheque from banque_mouvements where id = p_banque_mouvement_id;
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

    -- Recopie sur la ligne bancaire
    select count(*), coalesce(bool_and(lower(coalesce(f.fournisseur, '')) like '%amazon%'), false)
      into v_nb, v_tous_amazon
    from banque_mouvement_facture_liens l join factures f on f.id = l.facture_id
    where l.banque_mouvement_id = p_banque_mouvement_id;

    if v_ref_cheque is null then
        if v_nb > 1 and v_tous_amazon then
            update banque_mouvements set
                type_mouvement = 'Plusieurs Factures Amazon',
                description    = 'Plusieurs Factures Amazon',
                fournisseur    = 'Amazon'
            where id = p_banque_mouvement_id;
        else
            update banque_mouvements b set
                type_mouvement = coalesce(nullif(v_fac.categorie, ''), b.type_mouvement),
                description    = coalesce(nullif(v_fac.description, ''), b.description),
                fournisseur    = coalesce(nullif(v_fac.fournisseur, ''), b.fournisseur)
            where b.id = p_banque_mouvement_id;
        end if;
    else
        -- Chèque déjà lié : son type/description priment, on complète le fournisseur
        update banque_mouvements set fournisseur = (
            select nullif(string_agg(distinct f.fournisseur, ', '), '')
            from banque_mouvement_facture_liens l join factures f on f.id = l.facture_id
            where l.banque_mouvement_id = p_banque_mouvement_id
        ) where id = p_banque_mouvement_id;
    end if;

    update banque_mouvements b set
        lien_facture = coalesce(nullif(v_fac.lien_pdf, ''), b.lien_facture),
        nom_chat     = fusion_csv(b.nom_chat, v_fac.nom_chat)
    where b.id = p_banque_mouvement_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Facture liée : ' || coalesce(v_fac.numero_facture, ''));
end;
$$;


-- ============================================================
-- 5. SORTIE DE CAISSE : recopie type (défaut "Virement interne"),
--    description, n° de bordereau / caisse
-- ============================================================
create or replace function lier_banque_caisse(p_banque_mouvement_id uuid, p_caisse_mouvement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_statut_banque text;
    v_statut_caisse text;
    v_deja_liee     uuid;
    v_c             caisse_mouvements%rowtype;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;

    select statut into v_statut_banque from banque_mouvements where id = p_banque_mouvement_id;
    if v_statut_banque is null then raise exception 'Opération bancaire introuvable.'; end if;
    if v_statut_banque = 'verifie' then raise exception 'Ligne bancaire verrouillée — décochez "Vérifié" pour modifier.'; end if;

    select flag_statut, ref_banque into v_statut_caisse, v_deja_liee from caisse_mouvements where id = p_caisse_mouvement_id;
    if v_statut_caisse is null then raise exception 'Mouvement de caisse introuvable.'; end if;
    if v_statut_caisse = 'verifie' then raise exception 'Ligne de caisse verrouillée — décochez "Vérifié" pour modifier.'; end if;
    if v_deja_liee is not null then raise exception 'Cette sortie de caisse est déjà rattachée à un mouvement bancaire.'; end if;

    update caisse_mouvements set ref_banque = p_banque_mouvement_id where id = p_caisse_mouvement_id;

    select * into v_c from caisse_mouvements where id = p_caisse_mouvement_id;

    update banque_mouvements b set
        numero_remise_espece   = coalesce(nullif(v_c.numero_bordereau, ''), v_c.caisse || '-' || v_c.date_mouvement::text),
        type_mouvement         = coalesce(nullif(v_c.type_mouvement, ''), 'Virement interne'),
        description            = coalesce(nullif(v_c.description, ''), b.description),
        libelle_complementaire = case when v_c.caisse = 'caisse2' then 'Caisse2' else 'Caisse1' end
    where b.id = p_banque_mouvement_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_banque_mouvement_id::text, 'Sortie de caisse liée');
end;
$$;


-- ============================================================
-- 6. SOUS-CATÉGORIES (onglets) du panneau Suivi
-- ============================================================
-- Onglets : adoption, reservation_chat, reservation_chaton,
-- reservation_autre, don, adhesion, materiel.
-- Ne renvoie que les enregistrements pas encore liés à un mouvement
-- bancaire (équivalent de la file "en_attente" d'Import_Rapprochement).

create or replace function lister_suivi_pour_rapprochement(p_onglet text, p_recherche text default null)
returns table (
    type            text,
    id              uuid,
    nom_affiche     text,
    nom_chat        text,
    montant_suggere numeric,
    date_operation  date,
    numero_recu     text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
    v_q text := nullif(btrim(coalesce(p_recherche, '')), '');
begin
    if role_compta_courant() is null then
        raise exception 'Accès refusé : réservé aux comptes Compta.';
    end if;

    if p_onglet = 'adoption' then
        return query
        select 'adoption'::text as type, a.id as id, nom_personne_affiche(a.personne_id) as nom_affiche,
               coalesce(nullif(an.nom_adoption, ''), an.nom_usuel) as nom_chat,
               a.tarif_particulier as montant_suggere, a.date_adoption as date_operation, null::text as numero_recu
        from adoptions a left join animaux an on an.id = a.animal_id
        where not exists (select 1 from banque_mouvement_suivi_liens l where l.adoption_id = a.id)
          and (v_q is null or nom_personne_affiche(a.personne_id) ilike '%' || v_q || '%'
               or an.nom_usuel ilike '%' || v_q || '%' or an.nom_adoption ilike '%' || v_q || '%')
        order by a.date_adoption desc nulls last
        limit 100;

    elsif p_onglet in ('reservation_chat', 'reservation_chaton', 'reservation_autre') then
        return query
        select 'reservation'::text as type, r.id as id, nom_personne_affiche(r.personne_id) as nom_affiche,
               an.nom_usuel as nom_chat,
               r.montant as montant_suggere, r.date_reservation as date_operation, null::text as numero_recu
        from reservations r left join animaux an on an.id = r.animal_id
        where r.type_reservation = case p_onglet
                  when 'reservation_chat' then 'chat'
                  when 'reservation_chaton' then 'chaton'
                  else 'autre_animal' end
          and not exists (select 1 from banque_mouvement_suivi_liens l where l.reservation_id = r.id)
          and (v_q is null or nom_personne_affiche(r.personne_id) ilike '%' || v_q || '%'
               or an.nom_usuel ilike '%' || v_q || '%')
        order by r.date_reservation desc nulls last
        limit 100;

    elsif p_onglet = 'don' then
        return query
        select 'don'::text as type, d.id as id, nom_personne_affiche(d.personne_id) as nom_affiche,
               null::text as nom_chat,
               d.montant as montant_suggere, d.date_signature as date_operation, d.numero_recu_fiscal as numero_recu
        from dons d
        where not exists (select 1 from banque_mouvement_suivi_liens l where l.don_id = d.id)
          and (v_q is null or nom_personne_affiche(d.personne_id) ilike '%' || v_q || '%'
               or d.numero_recu_fiscal ilike '%' || v_q || '%')
        order by d.date_signature desc nulls last
        limit 100;

    elsif p_onglet = 'adhesion' then
        return query
        select 'adhesion'::text as type, a.id as id, nom_personne_affiche(a.personne_id) as nom_affiche,
               null::text as nom_chat,
               a.montant_total as montant_suggere, a.date_adhesion as date_operation, null::text as numero_recu
        from adhesions a
        where not exists (select 1 from banque_mouvement_suivi_liens l where l.adhesion_id = a.id)
          and (v_q is null or nom_personne_affiche(a.personne_id) ilike '%' || v_q || '%')
        order by a.date_adhesion desc nulls last
        limit 100;

    elsif p_onglet = 'materiel' then
        -- Une caution est versée mais materiel_mouvements ne stocke pas de
        -- montant : pas de montant suggéré, à saisir à la main.
        return query
        select 'materiel_mouvement'::text as type, m.id as id,
               nom_personne_affiche(m.personne_id) || ' — ' || coalesce(m.materiel, '') as nom_affiche,
               null::text as nom_chat,
               null::numeric as montant_suggere, m.date_mouvement as date_operation, null::text as numero_recu
        from materiel_mouvements m
        where m.type_mouvement = 'pret'
          and not exists (select 1 from banque_mouvement_suivi_liens l where l.materiel_mouvement_id = m.id)
          and (v_q is null or nom_personne_affiche(m.personne_id) ilike '%' || v_q || '%'
               or m.materiel ilike '%' || v_q || '%')
        order by m.date_mouvement desc nulls last
        limit 100;
    end if;
end;
$$;

-- Badges des onglets (nombre d'enregistrements pas encore liés à la banque)
create or replace function compter_suivi_a_rapprocher()
returns table (onglet text, nb integer)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
    if role_compta_courant() is null then
        raise exception 'Accès refusé : réservé aux comptes Compta.';
    end if;

    return query
    select 'adoption'::text as onglet, count(*)::integer as nb
    from adoptions a where not exists (select 1 from banque_mouvement_suivi_liens l where l.adoption_id = a.id)
    union all
    select 'reservation_chat', count(*)::integer
    from reservations r where r.type_reservation = 'chat' and not exists (select 1 from banque_mouvement_suivi_liens l where l.reservation_id = r.id)
    union all
    select 'reservation_chaton', count(*)::integer
    from reservations r where r.type_reservation = 'chaton' and not exists (select 1 from banque_mouvement_suivi_liens l where l.reservation_id = r.id)
    union all
    select 'reservation_autre', count(*)::integer
    from reservations r where r.type_reservation = 'autre_animal' and not exists (select 1 from banque_mouvement_suivi_liens l where l.reservation_id = r.id)
    union all
    select 'don', count(*)::integer
    from dons d where not exists (select 1 from banque_mouvement_suivi_liens l where l.don_id = d.id)
    union all
    select 'adhesion', count(*)::integer
    from adhesions a where not exists (select 1 from banque_mouvement_suivi_liens l where l.adhesion_id = a.id)
    union all
    select 'materiel', count(*)::integer
    from materiel_mouvements m where m.type_mouvement = 'pret' and not exists (select 1 from banque_mouvement_suivi_liens l where l.materiel_mouvement_id = m.id);
end;
$$;
