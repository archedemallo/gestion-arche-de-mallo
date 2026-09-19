-- ============================================================
-- 031_numero_interne_animaux.sql
--
-- Dépend de 027 et 030.
--
-- Ajoute un numéro interne unique et lisible, format A-2026-0042
-- (A = préfixe fixe, année d'arrivée, séquence sur 4 chiffres),
-- généré automatiquement à la création de chaque fiche animal.
--
-- rechercher_animaux() (utilisée par tous les sélecteurs d'animal des
-- formulaires) renvoie désormais aussi ce numéro, pour que les listes
-- déroulantes affichent "A-2026-0042 — Minou (gris) — adoptable" plutôt
-- qu'un simple nom.
-- ============================================================

alter table animaux add column if not exists numero_interne text;

create sequence if not exists animaux_numero_interne_seq;

create or replace function generer_numero_interne_animal()
returns trigger
language plpgsql
as $$
begin
    if new.numero_interne is null then
        new.numero_interne := 'A-' || to_char(coalesce(new.date_arrivee, current_date), 'YYYY')
            || '-' || lpad(nextval('animaux_numero_interne_seq')::text, 4, '0');
    end if;
    return new;
end;
$$;

drop trigger if exists trg_generer_numero_interne_animal on animaux;
create trigger trg_generer_numero_interne_animal
    before insert on animaux
    for each row execute function generer_numero_interne_animal();

-- Numéros pour les fiches déjà existantes, qui n'en ont pas encore
-- (le trigger ne joue qu'à la création). Ordonné par date d'arrivée
-- pour garder une séquence globalement chronologique.
do $$
declare
    v_animal record;
begin
    for v_animal in
        select id, date_arrivee from animaux where numero_interne is null order by date_arrivee nulls last, id
    loop
        update animaux set numero_interne = 'A-' || to_char(coalesce(v_animal.date_arrivee, current_date), 'YYYY')
            || '-' || lpad(nextval('animaux_numero_interne_seq')::text, 4, '0')
        where id = v_animal.id;
    end loop;
end;
$$;

alter table animaux add constraint animaux_numero_interne_unique unique (numero_interne);
alter table animaux alter column numero_interne set not null;


-- rechercher_animaux() : ajout de numero_interne au résultat.
-- Changement du type de retour -> DROP puis CREATE (impossible en
-- CREATE OR REPLACE simple).
drop function if exists rechercher_animaux(text, text);

create function rechercher_animaux(
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
        when 'adoption'    then v_statuts := array['adoptable', 'reserve'];
        when 'recherche'   then v_sans_filtre := true;
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
