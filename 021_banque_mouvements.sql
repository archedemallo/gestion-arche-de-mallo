-- ============================================================
-- BANQUE — mouvements bancaires
-- ============================================================
-- Reprend banque.html. Simplification volontaire restante par rapport à
-- l'ancien système :
--  - Le rattachement à un chèque/une remise/une facture se fait en
--    indiquant directement leur id (pas de panneau de recherche dédié).
-- La ventilation d'un mouvement sur plusieurs dons/adhésions (voir
-- lier_banque_suivi ci-dessous) est en revanche bien prise en charge,
-- suite à la revue de code — ce n'était pas le cas dans une version
-- antérieure de ce fichier.

create or replace function creer_operation_banque(
    p_date              date,
    p_libelle           text,
    p_debit             numeric default 0,
    p_credit            numeric default 0,
    p_periode           text default null,
    p_type_mouvement    text default null,
    p_description       text default null,
    p_libelle_complementaire text default null,
    p_fournisseur       text default null,
    p_nom_chat          text default null,
    p_numero_facture    text default null,
    p_numero_don_fiscal text default null,
    p_mode_reglement    text default null,
    p_ref_cheque        uuid default null,
    p_ref_remise        uuid default null
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
    if coalesce(p_debit,0) <= 0 and coalesce(p_credit,0) <= 0 then
        raise exception 'Le montant doit être supérieur à 0.';
    end if;
    if p_type_mouvement is null or p_type_mouvement = '' then
        raise exception 'Le type de mouvement est obligatoire.';
    end if;
    perform valider_type_description(p_type_mouvement, p_description);

    insert into banque_mouvements (
        date_mouvement, libelle, debit, credit, periode, type_mouvement, description,
        libelle_complementaire, fournisseur, nom, nom_chat, numero_facture, numero_don_fiscal,
        mode_reglement, ref_cheque, ref_remise
    ) values (
        p_date, p_libelle, coalesce(p_debit,0), coalesce(p_credit,0), p_periode, p_type_mouvement, p_description,
        p_libelle_complementaire, p_fournisseur, p_libelle, p_nom_chat, p_numero_facture, p_numero_don_fiscal,
        p_mode_reglement, p_ref_cheque, p_ref_remise
    )
    returning id into v_id;

    -- Si l'opération encaisse un chèque ou une remise, on les marque
    -- comme tels et on les rattache à ce mouvement.
    if p_ref_cheque is not null then
        update cheques set statut = 'encaisse', date_encaissement = p_date, ref_banque = v_id where id = p_ref_cheque;
    end if;
    if p_ref_remise is not null then
        update remises_cheques set statut = 'encaissee', date_encaissement = p_date, ref_banque = v_id where id = p_ref_remise;
    end if;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'AJOUT', 'banque_mouvements', v_id::text, p_libelle);

    return v_id;
end;
$$;

create or replace function modifier_operation_banque(
    p_id                uuid,
    p_date              date,
    p_libelle           text,
    p_debit             numeric default 0,
    p_credit            numeric default 0,
    p_periode           text default null,
    p_type_mouvement    text default null,
    p_description       text default null,
    p_libelle_complementaire text default null,
    p_fournisseur       text default null,
    p_nom_chat          text default null,
    p_numero_facture    text default null,
    p_numero_don_fiscal text default null,
    p_mode_reglement    text default null
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
    select statut into v_statut from banque_mouvements where id = p_id;
    if v_statut is null then raise exception 'Opération introuvable.'; end if;
    if v_statut = 'verifie' then raise exception 'Ligne verrouillée — décochez "Vérifié" pour modifier.'; end if;
    if coalesce(p_debit,0) <= 0 and coalesce(p_credit,0) <= 0 then raise exception 'Le montant doit être supérieur à 0.'; end if;
    perform valider_type_description(p_type_mouvement, p_description);

    update banque_mouvements set
        date_mouvement = p_date, libelle = p_libelle, debit = coalesce(p_debit,0), credit = coalesce(p_credit,0),
        periode = p_periode, type_mouvement = p_type_mouvement, description = p_description,
        libelle_complementaire = p_libelle_complementaire, fournisseur = p_fournisseur, nom = p_libelle,
        nom_chat = p_nom_chat, numero_facture = p_numero_facture, numero_don_fiscal = p_numero_don_fiscal,
        mode_reglement = p_mode_reglement
    where id = p_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_id::text, p_libelle);
end;
$$;

-- Verrouille ('verifie') ou déverrouille ('aucun') une ligne, via la
-- colonne "statut" (verrouillage) — distincte de "flag_verifie"
-- (simple annotation "à vérifier", voir annoter_operation_banque
-- ci-dessous). Contrairement à caisse_mouvements, ces deux notions sont
-- ici deux champs séparés (fidèle à COLS_BANQUE dans les sheets).
create or replace function verrouiller_operation_banque(p_id uuid, p_verrouiller boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update banque_mouvements set statut = case when p_verrouiller then 'verifie' else 'aucun' end where id = p_id;
    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    values (auth.jwt() ->> 'email', 'MODIF', 'banque_mouvements', p_id::text, case when p_verrouiller then 'Verrouillée' else 'Déverrouillée' end);
end;
$$;

create or replace function annoter_operation_banque(p_id uuid, p_commentaire text, p_resolu boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update banque_mouvements set
        flag_verifie = not p_resolu,
        flag_commentaire = case when p_resolu then null else p_commentaire end
    where id = p_id and statut <> 'verifie';
end;
$$;

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

    -- Libère le chèque/la remise éventuellement rattaché(e), pour ne pas
    -- les laisser marqués "encaissé" sans mouvement bancaire réel.
    update cheques set statut = 'en_attente', date_encaissement = null, ref_banque = null where ref_banque = p_id;
    update remises_cheques set statut = 'en_attente', date_encaissement = null, ref_banque = null where ref_banque = p_id;

    insert into journal_audit_compta (user_email, action, onglet, ligne_ref, detail)
    select auth.jwt() ->> 'email', 'SUPPRESSION', 'banque_mouvements', p_id::text, libelle from banque_mouvements where id = p_id;

    delete from banque_mouvements where id = p_id;
end;
$$;

-- Rattache un mouvement bancaire à un ou plusieurs enregistrements Suivi
-- (adhésion, don, adoption, réservation) — accepte désormais une
-- ventilation sur plusieurs lignes en un seul appel (un virement de
-- 300€ peut couvrir un don de 100€ + une adhésion de 50€ + un autre don
-- de 150€, par exemple). Avant, un seul lien était possible par
-- mouvement — limite signalée en revue de code.
--
-- p_liens : jsonb, tableau d'objets avec exactement UNE des 4 clés
-- cible remplie, ex.
--   '[{"don_id":"...","montant":100},
--     {"adhesion_id":"...","montant":50},
--     {"don_id":"...","montant":150}]'
--
-- banque_mouvements.suivi_ref devient un simple indicateur ('oui'/null)
-- signalant qu'au moins un lien existe — ce n'est plus un id unique,
-- puisqu'il peut désormais y en avoir plusieurs pour un même mouvement.
-- Le détail complet se lit dans banque_mouvement_suivi_liens.
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
    v_item jsonb;
    v_count integer := 0;
    v_nb_cibles integer;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    if p_liens is null or jsonb_array_length(p_liens) = 0 then
        raise exception 'Ajoutez au moins un lien.';
    end if;

    delete from banque_mouvement_suivi_liens where banque_mouvement_id = p_banque_mouvement_id;

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
        v_count := v_count + 1;
    end loop;

    update banque_mouvements set suivi_ref = 'oui' where id = p_banque_mouvement_id;
    return v_count;
end;
$$;

create or replace function delier_banque_suivi(p_banque_mouvement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    delete from banque_mouvement_suivi_liens where banque_mouvement_id = p_banque_mouvement_id;
    update banque_mouvements set suivi_ref = null where id = p_banque_mouvement_id;
end;
$$;

-- Symétrique côté Caisse (n'existait pas du tout avant — seul le délier
-- avait été construit). Même logique de ventilation multi-lignes.
create or replace function lier_caisse_suivi(
    p_caisse_mouvement_id uuid,
    p_liens jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_item jsonb;
    v_count integer := 0;
    v_nb_cibles integer;
    v_statut text;
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    select flag_statut into v_statut from caisse_mouvements where id = p_caisse_mouvement_id;
    if v_statut = 'verifie' then
        raise exception 'Ligne verrouillée — décochez "Vérifié" avant de modifier le rapprochement.';
    end if;
    if p_liens is null or jsonb_array_length(p_liens) = 0 then
        raise exception 'Ajoutez au moins un lien.';
    end if;

    delete from caisse_mouvement_suivi_liens where caisse_mouvement_id = p_caisse_mouvement_id;

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

        insert into caisse_mouvement_suivi_liens (caisse_mouvement_id, adhesion_id, don_id, adoption_id, reservation_id, materiel_mouvement_id, montant)
        values (
            p_caisse_mouvement_id,
            (v_item->>'adhesion_id')::uuid,
            (v_item->>'don_id')::uuid,
            (v_item->>'adoption_id')::uuid,
            (v_item->>'reservation_id')::uuid,
            (v_item->>'materiel_mouvement_id')::uuid,
            (v_item->>'montant')::numeric
        );
        v_count := v_count + 1;
    end loop;

    update caisse_mouvements set suivi_ref = 'oui' where id = p_caisse_mouvement_id;
    return v_count;
end;
$$;

create or replace function delier_banque_cheque(p_banque_mouvement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update cheques set statut = 'en_attente', date_encaissement = null, ref_banque = null where ref_banque = p_banque_mouvement_id;
    update banque_mouvements set ref_cheque = null where id = p_banque_mouvement_id;
end;
$$;

create or replace function delier_banque_remise(p_banque_mouvement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if role_compta_courant() <> 'admin' then
        raise exception 'Accès refusé : réservé aux comptes admin.';
    end if;
    update remises_cheques set statut = 'en_attente', date_encaissement = null, ref_banque = null where ref_banque = p_banque_mouvement_id;
    update banque_mouvements set ref_remise = null where id = p_banque_mouvement_id;
end;
$$;

-- ============================================================
-- Symétrique côté Caisse : la page caisse.html modifiait jusqu'ici ces
-- deux champs par un appel direct .update() sur la table (bordereau,
-- suivi_ref), en contournant le verrouillage — corrigé.
-- ============================================================
create or replace function delier_caisse_bordereau(p_caisse_mouvement_id uuid)
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
    select flag_statut into v_statut from caisse_mouvements where id = p_caisse_mouvement_id;
    if v_statut = 'verifie' then
        raise exception 'Ligne verrouillée — décochez "Vérifié" avant de modifier le rapprochement.';
    end if;
    update caisse_mouvements set numero_bordereau = null where id = p_caisse_mouvement_id;
end;
$$;

create or replace function delier_caisse_suivi(p_caisse_mouvement_id uuid)
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
    select flag_statut into v_statut from caisse_mouvements where id = p_caisse_mouvement_id;
    if v_statut = 'verifie' then
        raise exception 'Ligne verrouillée — décochez "Vérifié" avant de modifier le rapprochement.';
    end if;
    delete from caisse_mouvement_suivi_liens where caisse_mouvement_id = p_caisse_mouvement_id;
    update caisse_mouvements set suivi_ref = null where id = p_caisse_mouvement_id;
end;
$$;

-- ============================================================
-- Recherche unifiée pour l'écran de ventilation (lier un mouvement
-- bancaire ou de caisse à un ou plusieurs enregistrements Suivi).
-- Interroge adhésions/dons/adoptions/réservations en une fois, avec le
-- nom de la personne associée. N'existait pas du tout avant (aucune
-- interface pour lier plusieurs enregistrements) — construit avec la
-- fonction lier_banque_suivi()/lier_caisse_suivi() ci-dessus.
-- ============================================================
create or replace function rechercher_suivi_pour_ventilation(p_recherche text)
returns table (
    type            text,
    id              uuid,
    nom_affiche     text,
    montant_suggere numeric,
    date_operation  date
)
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
    select 'adhesion'::text, a.id, coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme'), a.montant_total, a.date_adhesion
    from adhesions a join personnes p on p.id = a.personne_id
    where p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
    union all
    select 'don'::text, d.id, coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme'), d.montant, d.date_signature
    from dons d left join personnes p on p.id = d.personne_id
    where p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
    union all
    select 'adoption'::text, ad.id, coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme'), ad.tarif_particulier, ad.date_adoption
    from adoptions ad join personnes p on p.id = ad.personne_id
    where p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
    union all
    select 'reservation'::text, r.id, coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme'), r.montant, r.date_reservation
    from reservations r join personnes p on p.id = r.personne_id
    where p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
    union all
    -- Prêt de matériel : une caution est versée à l'Arche mais
    -- materiel_mouvements ne stocke pas de montant (juste le
    -- type/la personne/le matériel) — pas de montant suggéré ici,
    -- l'admin le saisit à la main dans la ventilation. Absent du
    -- système de rapprochement jusqu'ici (signalé).
    select 'materiel_mouvement'::text, m.id, coalesce(p.prenom || ' ' || p.nom, p.raison_sociale, 'Anonyme') || ' — ' || coalesce(m.materiel, ''), null::numeric, m.date_mouvement
    from materiel_mouvements m join personnes p on p.id = m.personne_id
    where m.type_mouvement = 'pret'
      and (p_recherche is null or btrim(p_recherche) = ''
       or p.nom ilike '%'||p_recherche||'%' or p.prenom ilike '%'||p_recherche||'%' or p.raison_sociale ilike '%'||p_recherche||'%'
       or m.materiel ilike '%'||p_recherche||'%')
    order by date_operation desc nulls last
    limit 30;
end;
$$;
