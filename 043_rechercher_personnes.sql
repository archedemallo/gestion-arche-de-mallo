-- ============================================================
-- 043_rechercher_personnes.sql
-- ============================================================
-- Crée la fonction rechercher_personnes(), appelée par
-- selecteur-personne.js (utilisé par 11 formulaires) et par
-- formulaires_preremplis.html, mais absente de toutes les migrations
-- précédentes du dépôt — l'auto-complétion Nom/Prénom ne proposait
-- donc jamais rien (erreur avalée en console.error, aucun message
-- visible). Même principe que rechercher_animaux() (voir 027/031).
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
    where p.nom ilike '%' || btrim(p_recherche) || '%'
       or p.prenom ilike '%' || btrim(p_recherche) || '%'
       or p.raison_sociale ilike '%' || btrim(p_recherche) || '%'
       or p.email ilike '%' || btrim(p_recherche) || '%'
       or p.telephone ilike '%' || btrim(p_recherche) || '%'
    order by coalesce(p.nom, p.raison_sociale)
    limit 20;
end;
$$;
