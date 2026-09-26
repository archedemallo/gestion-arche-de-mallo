-- ============================================================
-- 046_statuts_exclut_relache.sql
-- ============================================================
-- Un chat relâché ne doit plus apparaître dans la liste des animaux
-- qu'on peut faire évoluer depuis statuts_animaux.html. Nouveau
-- contexte dédié 'statuts' (copie de 'recherche' sans 'relache') pour
-- ne pas toucher les autres pages qui utilisent encore 'recherche'.
-- ============================================================

create or replace function rechercher_animaux(
    p_recherche text,
    p_contexte text default 'adoption'
)
returns table (
    id uuid, numero_interne text, nom_usuel text, nom_adoption text,
    statut_actuel text, puce text, couleur text
)
language plpgsql security definer set search_path = public stable
as $$
declare
    v_statuts text[];
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    case p_contexte
        when 'reservation' then v_statuts := array['adoptable'];
        when 'adoption' then v_statuts := array['adoptable', 'reserve'];
        when 'recherche' then v_statuts := array['en_observation', 'adoptable', 'non_adoptable',
            'malade', 'relache', 'reservation_annulee', 'reserve', 'au_veto', 'famille_accueil'];
        when 'statuts' then v_statuts := array['en_observation', 'adoptable', 'non_adoptable',
            'malade', 'reservation_annulee', 'reserve', 'au_veto', 'famille_accueil'];
        else raise exception 'Contexte de recherche invalide : %', p_contexte;
    end case;

    return query
    select a.id, a.numero_interne, a.nom_usuel, a.nom_adoption, a.statut_actuel, a.puce, a.couleur
    from animaux a
    where a.statut_actuel = any(v_statuts)
      and (p_recherche is null or btrim(p_recherche) = ''
           or a.nom_usuel ilike '%' || btrim(p_recherche) || '%'
           or a.numero_interne ilike '%' || btrim(p_recherche) || '%')
    order by a.nom_usuel
    limit 20;
end;
$$;
