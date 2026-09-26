-- ============================================================
-- 046_recherche_exclusions_et_relache.sql
--
-- 1. rechercher_animaux() : le contexte 'recherche' (utilisé par
--    statuts_animaux.html) ne filtrait aucun statut — un chat adopté
--    ou décédé restait donc trouvable et modifiable indéfiniment.
--    Exclusion de 'adopte' et 'decede' (états finaux, plus rien à
--    faire évoluer sur leur statut).
--
-- 2. Ajoute la transition directe vers 'relache' depuis
--    'en_observation' et 'adoptable' : un chat trappé peut être
--    relâché directement après évaluation, sans passer par 'au_veto'.
-- ============================================================

create or replace function rechercher_animaux(
    p_recherche text,
    p_contexte text default 'adoption'
)
returns table (
    id uuid,
    numero_interne text,
    nom_usuel text,
    nom_adoption text,
    statut_actuel text,
    puce text,
    couleur text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
    v_statuts text[];
    v_sans_filtre boolean := false;
begin
    if role_suivi_courant() is null then
        raise exception 'Accès refusé : connexion requise.';
    end if;

    case p_contexte
        when 'reservation' then v_statuts := array['adoptable'];
        when 'adoption' then v_statuts := array['adoptable', 'reserve'];
        when 'recherche' then v_statuts := array['en_observation', 'adoptable', 'non_adoptable',
            'malade', 'relache', 'reservation_annulee', 'reserve', 'au_veto', 'famille_accueil'];
        else raise exception 'Contexte de recherche invalide : %', p_contexte;
    end case;

    return query
    select a.id, a.numero_interne, a.nom_usuel, a.nom_adoption, a.statut_actuel, a.puce, a.couleur
    from animaux a
    where (v_sans_filtre or a.statut_actuel = any(v_statuts))
      and (p_recherche is null or btrim(p_recherche) = ''
           or a.nom_usuel ilike '%' || btrim(p_recherche) || '%'
           or a.numero_interne ilike '%' || btrim(p_recherche) || '%')
    order by a.nom_usuel
    limit 20;
end;
$$;

insert into transitions_statut_animal (statut_depart, statut_arrivee) values
    ('en_observation', 'relache'),
    ('adoptable', 'relache')
on conflict do nothing;
