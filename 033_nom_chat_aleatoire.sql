-- ============================================================
-- 033_nom_chat_aleatoire.sql
--
-- Support de la fonction "Nom aléatoire" à la déclaration d'une
-- arrivée (statuts_animaux.html) : le navigateur a besoin de savoir
-- quels noms sont actuellement utilisés par un chat PRÉSENT à
-- l'association, pour ne jamais suggérer un nom déjà pris.
--
-- Un nom déjà porté par un chat parti (adopté / décédé / relâché)
-- n'est PAS exclu : rien n'empêche de le réutiliser, seul un doublon
-- avec un chat actuellement présent est gênant.
-- ============================================================
create or replace function noms_animaux_presents()
returns table (nom text)
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
    select distinct x.nom from (
        select nom_usuel as nom from animaux
        where statut_actuel is null or statut_actuel not in ('decede', 'relache', 'adopte')
        union all
        select nom_adoption as nom from animaux
        where nom_adoption is not null
          and (statut_actuel is null or statut_actuel not in ('decede', 'relache', 'adopte'))
    ) x
    where x.nom is not null and btrim(x.nom) <> '';
end;
$$;

grant execute on function noms_animaux_presents() to authenticated, anon;
