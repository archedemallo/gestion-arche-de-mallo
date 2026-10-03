-- ============================================================
-- 056_correction_recherche_personnes_null.sql
-- ============================================================
-- Correctif de rechercher_personnes() (055).
--
-- Bug : dans le "not exists ... where not (champ1 ilike ... or champ2
-- ilike ...)", un champ NULL (raison_sociale est NULL pour tous les
-- particuliers, souvent aussi email / telephone) rend le "or" NULL
-- quand rien ne correspond. "not (NULL)" reste NULL, donc le mot
-- n'était jamais considéré comme "non trouvé" : TOUTE personne ayant
-- un champ NULL remontait quelle que soit la recherche (liste
-- polluée, triée par nom, coupée à 20 -> la bonne personne pouvait
-- ne pas apparaître).
--
-- Correction : chaque test est enveloppé dans coalesce(..., false).
-- Signature, colonnes, tri et limite inchangés.
-- ============================================================

create or replace function rechercher_personnes(p_recherche text)
returns table (
    id uuid,
    type_personne text,
    civilite text,
    nom text,
    prenom text,
    raison_sociale text,
    adresse text,
    code_postal text,
    ville text,
    email text,
    telephone text
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

    if p_recherche is null or btrim(p_recherche) = '' then
        return;
    end if;

    return query
    select p.id, p.type_personne, p.civilite, p.nom, p.prenom, p.raison_sociale,
           p.adresse, p.code_postal, p.ville, p.email, p.telephone
    from personnes p
    where not exists (
        select 1
        from unnest(regexp_split_to_array(btrim(p_recherche), '\s+')) as mot
        where not coalesce(
               p.nom            ilike '%' || mot || '%'
            or p.prenom         ilike '%' || mot || '%'
            or p.raison_sociale ilike '%' || mot || '%'
            or p.email          ilike '%' || mot || '%'
            or p.telephone      ilike '%' || mot || '%'
            , false)
    )
    order by coalesce(p.nom, p.raison_sociale), p.prenom
    limit 20;
end;
$$;
