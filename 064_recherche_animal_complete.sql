-- ============================================================
-- 064_recherche_animal_complete.sql
-- ============================================================
-- Page Recherche animal (recherche_chat.html) :
--
-- 1. Tous les animaux n'apparaissaient pas : la recherche passait par
--    rechercher_animaux(..., 'recherche') qui (a) exclut les animaux
--    adoptés et décédés (046) et (b) s'arrête à 20 résultats.
--    -> nouvelle fonction rechercher_animaux_fiche() : AUCUN filtre de
--    statut, filtre optionnel par ANNÉE D'ARRIVÉE, pas de limite à 20.
--    -> annees_arrivee_animaux() : alimente la liste déroulante des années.
--
-- 2. La fiche ne montrait pas la personne à l'origine de l'arrivée
--    (trappage, dépôt, abandon, saisie…) : animaux.personne_origine_id
--    n'était jamais lu par obtenir_fiche_animal(). Ajout des clés
--    'personne_origine' et 'icad' (transfert ICAD / certificat de
--    stérilisation). Méthode identique à 061 : l'ancienne fonction (059)
--    est conservée sous le nom obtenir_fiche_animal_base.
--
-- Idempotent : peut être rejoué sans erreur.
-- Ne modifie PAS rechercher_animaux() (utilisée par les autres pages).
-- ============================================================

-- ---------- 1. Recherche sans filtre de statut, par année ----------
create or replace function rechercher_animaux_fiche(
    p_recherche text default null,
    p_annee integer default null      -- null = toutes ; 0 = date d'arrivée inconnue
)
returns table (
    id uuid,
    numero_interne text,
    nom_usuel text,
    nom_adoption text,
    statut_actuel text,
    puce text,
    couleur text,
    espece text,
    date_arrivee date,
    origine_arrivee text
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    return query
    select a.id, a.numero_interne, a.nom_usuel, a.nom_adoption, a.statut_actuel,
           a.puce, a.couleur, a.espece, a.date_arrivee, a.origine_arrivee
    from animaux a
    where (p_annee is null
           or (p_annee = 0 and a.date_arrivee is null)
           or (p_annee > 0 and extract(year from a.date_arrivee) = p_annee))
      and (p_recherche is null or btrim(p_recherche) = ''
           or a.nom_usuel ilike '%' || btrim(p_recherche) || '%'
           or a.nom_adoption ilike '%' || btrim(p_recherche) || '%'
           or a.numero_interne ilike '%' || btrim(p_recherche) || '%'
           or a.puce ilike '%' || btrim(p_recherche) || '%')
    order by a.date_arrivee desc nulls last, a.nom_usuel
    limit 2000;
end;
$$;

create or replace function annees_arrivee_animaux()
returns table (annee integer, nb bigint)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    return query
    select coalesce(extract(year from a.date_arrivee)::integer, 0) as annee, count(*) as nb
    from animaux a
    group by 1
    order by 1 desc;
end;
$$;

-- ---------- 2. Fiche animal : personne à l'origine + ICAD ----------
do $$
begin
    if exists (select 1 from pg_proc where proname = 'obtenir_fiche_animal')
       and not exists (select 1 from pg_proc where proname = 'obtenir_fiche_animal_base') then
        alter function obtenir_fiche_animal(uuid) rename to obtenir_fiche_animal_base;
    end if;
end $$;

create or replace function obtenir_fiche_animal(p_animal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
    v_fiche jsonb;
    v_personne_origine jsonb;
    v_icad jsonb;
    v_table_icad text;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    v_fiche := obtenir_fiche_animal_base(p_animal_id);
    if v_fiche is null then
        return null;
    end if;

    -- Personne qui a amené l'animal (trappage, dépôt, abandon, saisie…)
    select to_jsonb(p) into v_personne_origine
    from personnes p
    where p.id = (v_fiche->'animal'->>'personne_origine_id')::uuid;

    -- Suivi ICAD (la table a pu être renommée par 053)
    v_table_icad := case
        when to_regclass('public.animaux_sterilisation_icad') is not null then 'animaux_sterilisation_icad'
        when to_regclass('public.icad_suivi') is not null then 'icad_suivi'
        else null end;
    if v_table_icad is not null then
        execute format('select to_jsonb(i) from %I i where i.animal_id = $1', v_table_icad)
        into v_icad using p_animal_id;
    end if;

    return v_fiche || jsonb_build_object(
        'personne_origine', v_personne_origine,
        'icad', v_icad
    );
end;
$$;
